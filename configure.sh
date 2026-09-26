#!/usr/bin/env bash
# Fill the Supabase project URL and anon key into index.html.
#
#   ./configure.sh https://xxxxxxxx.supabase.co eyJhbGciOi...
#
# Safe to re-run: it rewrites whatever values are currently in the file.
set -euo pipefail

URL="${1:-}"
KEY="${2:-}"

if [[ -z "$URL" || -z "$KEY" ]]; then
  echo "usage: $0 <supabase-project-url> <supabase-anon-key>" >&2
  exit 1
fi

if [[ ! "$URL" =~ ^https://[a-z0-9-]+\.supabase\.(co|in)$ ]]; then
  echo "error: '$URL' does not look like a Supabase project URL (https://<ref>.supabase.co)" >&2
  exit 1
fi

if [[ ${#KEY} -lt 40 ]]; then
  echo "error: that anon key looks too short (${#KEY} chars)" >&2
  exit 1
fi

if [[ "$KEY" == *"service_role"* ]]; then
  echo "error: that looks like the service_role key — use the anon/publishable key" >&2
  exit 1
fi

cd "$(dirname "$0")"
python3 - "$URL" "$KEY" <<'PY'
import re, sys
url, key = sys.argv[1], sys.argv[2]
html = open('index.html', encoding='utf-8').read()
html, n1 = re.subn(r"(const CONFIG=\{url:')[^']*(')", lambda m: m.group(1) + url + m.group(2), html, count=1)
html, n2 = re.subn(r"(,key:')[^']*('\};)", lambda m: m.group(1) + key + m.group(2), html, count=1)
if n1 != 1 or n2 != 1:
    sys.exit('error: could not find the CONFIG block in index.html')
open('index.html', 'w', encoding='utf-8').write(html)
print('configured ->', url)
PY
