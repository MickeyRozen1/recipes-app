# ספר המתכונים המשפחתי — family recipe book

A single-page recipe app (Hebrew, RTL) backed by Supabase, so everyone holding
the share link reads and writes the **same** book.

```
index.html     the whole app — markup, styles, logic
schema.sql     run once in the Supabase SQL editor
configure.sh   writes your project URL + anon key into index.html
```

## Setup

1. **Create a Supabase project** — https://supabase.com/dashboard, free tier is
   plenty. Note the *Project URL* and the *anon / publishable* key from
   Project Settings → API. (Never the `service_role` key.)

2. **Create the tables and functions** — SQL Editor → New query → paste all of
   `schema.sql` → Run.

3. **Point the app at the project**

   ```bash
   ./configure.sh https://<your-ref>.supabase.co <your-anon-key>
   ```

4. **Open it.** Any static host works — `index.html` has no build step:

   ```bash
   python3 -m http.server 8777    # then http://localhost:8777
   ```

5. **Create the book.** The first visit shows a "create a new recipe book"
   screen. Click it once — it mints a book, seeds three starter recipes, and
   lands you on `?family=<uuid>`.

6. **Share.** Hit **🔗 שיתוף עם המשפחה** in the header to copy the link, and
   send it to the family. That link *is* the book.

## How sharing works

The `family` UUID in the URL is a capability token: holding the link grants full
read/write access to that one book, and grants nothing else.

That is enforced in the database, not the client:

- Both tables have RLS enabled with **zero policies**, and all direct grants to
  `anon` are revoked — the anon key alone can read nothing.
- The only reachable surface is four `SECURITY DEFINER` functions, each of which
  takes the family UUID as an argument and scopes every row to it.

So the anon key being visible in page source is fine — it is not a secret, and
it is not sufficient. Guessing a v4 UUID is the only way in.

**What this is not:** there are no accounts and no per-person permissions.
Anyone with the link can edit or delete any recipe in that book, and there is no
undo. That is the intended trade-off for a family book — no logins to explain to
anyone. Treat the link like a house key and don't post it publicly.

## Behaviour notes

- **Photos** can come from four places: the camera (📷, opens the camera directly
  on a phone via `capture="environment"`; on desktop it falls back to a file
  dialog), a file, a `https://` image link, or pasting an image into the form.
  A saved photo can also be removed, not just replaced.
  All four funnel through the same gate — reject non-images, reject over 5MB,
  resize to max 1000px, JPEG-compress, then store as base64 in the recipe row
  (~750KB client cap, 1MB server cap). No storage bucket to configure.
- **Photo-by-link is best-effort:** the browser fetches the image to compress it,
  so a site that doesn't send CORS headers will refuse. The form says so and
  points you at uploading the file instead.
- **Freshness** is polled, not live: the gallery refreshes every 30s and on tab
  focus, and never mid-edit. Someone else's new recipe shows up within half a
  minute, not instantly.
- **Concurrent edits** are last-write-wins per recipe. Two people editing the
  same recipe at once means one of them silently loses; different recipes never
  conflict.
- **Unconfigured fallback** — with no Supabase keys filled in, the app still runs
  standalone off `localStorage` and says so in a banner. Useful for trying the UI,
  useless for sharing.

## Deploying

It is one static file, so anything serves it: GitHub Pages, Netlify drop,
Cloudflare Pages, Vercel. Point the host at this folder; no build, no env vars
(the keys are baked into `index.html` by `configure.sh`).

If you redeploy to a new domain, existing links keep working as long as the
`?family=<uuid>` part is preserved — the data lives in Supabase, not the host.
