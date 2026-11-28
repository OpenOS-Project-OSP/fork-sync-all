#!/usr/bin/env bash
# Verify loopback-only containment and that browser routes stay disabled in CGI.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if output="$(bash server/start.sh --host 0.0.0.0 2>&1)"; then
  echo "ERROR: non-loopback bind unexpectedly accepted" >&2
  exit 1
fi
grep -q "refusing non-loopback bind" <<<"$output"

if output="$(UAA_HOST=192.0.2.10 bash server/start.sh 2>&1)"; then
  echo "ERROR: non-loopback environment bind unexpectedly accepted" >&2
  exit 1
fi
grep -q "refusing non-loopback bind" <<<"$output"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
python3 scripts/uaa-merge-routes.py config/toggles.yml "$tmp/filtered-routes.yml" config/routes.yml
bash server/deploy-cgi.sh "$tmp/cgi" "$tmp/filtered-routes.yml"

[[ -L "$tmp/cgi/health.sh" ]]
for name in screenshot.sh scrape.sh automate.sh; do
  if [[ -e "$tmp/cgi/$name" ]]; then
    echo "ERROR: disabled browser CGI route was deployed: $name" >&2
    exit 1
  fi
done

python3 - <<'PY'
import yaml
with open("config/routes.yml", encoding="utf-8") as stream:
    routes = yaml.safe_load(stream)["routes"]
browser = [r for r in routes if r["path"].startswith("/api/browser/")]
assert len(browser) == 3, f"expected 3 browser routes, found {len(browser)}"
assert all(r.get("toggle") == "browser_capture" for r in browser)
with open("config/toggles.yml", encoding="utf-8") as stream:
    toggles = yaml.safe_load(stream)["toggles"]
assert toggles["browser_capture"]["enabled"] is False
print("server containment and CGI filtering: ok")
PY
