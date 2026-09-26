-- ספר המתכונים המשפחתי — Supabase schema
-- Run once in the Supabase dashboard: SQL Editor -> New query -> paste -> Run.
--
-- Security model: the family id (a v4 UUID) IS the secret. Anyone holding the
-- share link can read and write that family's book; nobody can read any other
-- family's book, and nobody can list which families exist.
--
-- That is enforced by keeping RLS on with NO policies (so the anon role can
-- touch nothing directly) and exposing only SECURITY DEFINER functions that
-- each demand the family id as an argument.

create extension if not exists "pgcrypto";

create table if not exists public.families (
  id         uuid primary key,
  name       text not null default 'ספר המתכונים שלנו',
  created_at timestamptz not null default now()
);

create table if not exists public.recipes (
  family_id   uuid not null references public.families (id) on delete cascade,
  id          text not null,
  name        text not null,
  category    text not null,
  "time"      integer not null check ("time" between 1 and 1440),
  ingredients jsonb not null default '[]'::jsonb,
  steps       jsonb not null default '[]'::jsonb,
  emoji       text not null default '🍽️',
  image       text not null default '',
  updated_at  timestamptz not null default now(),
  primary key (family_id, id)
);

create index if not exists recipes_family_updated_idx
  on public.recipes (family_id, updated_at desc);

-- Lock the tables down completely. RLS enabled with zero policies means the
-- anon/authenticated roles get no direct row access at all.
alter table public.families enable row level security;
alter table public.recipes  enable row level security;

revoke all on public.families from anon, authenticated;
revoke all on public.recipes  from anon, authenticated;

-- ---------------------------------------------------------------------------
-- RPCs. These are the entire public API surface.
-- ---------------------------------------------------------------------------

-- Create the family book if it does not exist yet. Idempotent, so a reopened
-- link never clobbers an existing book.
create or replace function public.family_ensure(p_family uuid, p_name text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.families (id, name)
  values (p_family, coalesce(nullif(btrim(p_name), ''), 'ספר המתכונים שלנו'))
  on conflict (id) do nothing;
end;
$$;

create or replace function public.recipes_list(p_family uuid)
returns table (
  id text, name text, category text, "time" integer,
  ingredients jsonb, steps jsonb, emoji text, image text,
  updated_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select r.id, r.name, r.category, r."time",
         r.ingredients, r.steps, r.emoji, r.image, r.updated_at
  from public.recipes r
  where r.family_id = p_family
  order by r.updated_at desc;
$$;

create or replace function public.recipe_save(
  p_family      uuid,
  p_id          text,
  p_name        text,
  p_category    text,
  p_time        integer,
  p_ingredients jsonb,
  p_steps       jsonb,
  p_emoji       text default '🍽️',
  p_image       text default ''
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Reject writes to a book that was never created, so a typo'd link cannot
  -- silently spawn an orphan book.
  if not exists (select 1 from public.families f where f.id = p_family) then
    raise exception 'unknown family';
  end if;

  if btrim(coalesce(p_name, '')) = '' or btrim(coalesce(p_category, '')) = '' then
    raise exception 'name and category are required';
  end if;

  if jsonb_typeof(p_ingredients) <> 'array' or jsonb_array_length(p_ingredients) = 0
     or jsonb_typeof(p_steps) <> 'array' or jsonb_array_length(p_steps) = 0 then
    raise exception 'ingredients and steps must be non-empty arrays';
  end if;

  -- Roughly 1MB of base64, matching the client-side compression ceiling.
  if length(coalesce(p_image, '')) > 1000000 then
    raise exception 'image too large';
  end if;

  insert into public.recipes (family_id, id, name, category, "time",
                              ingredients, steps, emoji, image, updated_at)
  values (p_family, p_id, btrim(p_name), btrim(p_category), p_time,
          p_ingredients, p_steps, coalesce(nullif(btrim(p_emoji), ''), '🍽️'),
          coalesce(p_image, ''), now())
  on conflict (family_id, id) do update
    set name        = excluded.name,
        category    = excluded.category,
        "time"      = excluded."time",
        ingredients = excluded.ingredients,
        steps       = excluded.steps,
        emoji       = excluded.emoji,
        image       = excluded.image,
        updated_at  = now();
end;
$$;

create or replace function public.recipe_delete(p_family uuid, p_id text)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.recipes r where r.family_id = p_family and r.id = p_id;
$$;

-- Only the functions are callable.
revoke all on function public.family_ensure(uuid, text) from public;
revoke all on function public.recipes_list(uuid) from public;
revoke all on function public.recipe_save(uuid, text, text, text, integer, jsonb, jsonb, text, text) from public;
revoke all on function public.recipe_delete(uuid, text) from public;

grant execute on function public.family_ensure(uuid, text) to anon, authenticated;
grant execute on function public.recipes_list(uuid) to anon, authenticated;
grant execute on function public.recipe_save(uuid, text, text, text, integer, jsonb, jsonb, text, text) to anon, authenticated;
grant execute on function public.recipe_delete(uuid, text) to anon, authenticated;
