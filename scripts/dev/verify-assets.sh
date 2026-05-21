#!/usr/bin/env bash
# Quick check that dev (or prod) can serve hashed desk assets.
#
# Usage:
#   ./scripts/dev/verify-assets.sh           # dev stack
#   STACK=ets_prod SITE=erp.aca.local PORT=8080 ./scripts/dev/verify-assets.sh
set -euo pipefail

STACK="${STACK:-ets_dev}"
SITE="${SITE:-frontend}"
PORT="${PORT:-8081}"
CTR="${STACK}_backend"

die() { printf '\033[1;31m[verify-assets]\033[0m %s\n' "$*" >&2; exit 1; }

docker inspect "$CTR" >/dev/null 2>&1 || die "container $CTR not found"

read -r DESK_CSS DESK_JS < <(docker exec "$CTR" python3 -c "
import json
d=json.load(open('/home/frappe/frappe-bench/sites/assets/assets.json'))
css=d.get('desk.bundle.css','')
js=d.get('desk.bundle.js','')
print(css.split('/')[-1], js.split('/')[-1])
")

[[ -n "$DESK_CSS" ]] || die "desk.bundle.css not in assets.json"

echo "Site: $SITE  Port: $PORT  Stack: $STACK"
echo "Expected CSS: $DESK_CSS"
echo "Expected JS:  $DESK_JS"

docker exec "${STACK}_frontend" test -f "/home/frappe/frappe-bench/apps/frappe/frappe/public/dist/css/$DESK_CSS" \
  && echo "frontend filesystem: CSS OK" \
  || echo "frontend filesystem: CSS MISSING"

code_css="$(curl -s -o /dev/null -w '%{http_code}' -H "Host: $SITE" "http://127.0.0.1:${PORT}/assets/frappe/dist/css/${DESK_CSS}")"
code_js="$(curl -s -o /dev/null -w '%{http_code}' -H "Host: $SITE" "http://127.0.0.1:${PORT}/assets/frappe/dist/js/${DESK_JS}")"
echo "HTTP CSS: $code_css  HTTP JS: $code_js"

[[ "$code_css" == "200" && "$code_js" == "200" ]] || exit 1
echo "Assets look healthy."
