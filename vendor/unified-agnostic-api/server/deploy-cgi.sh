#!/usr/bin/env bash
# server/deploy-cgi.sh — deploy filtered adapter routes as Apache CGI endpoints
#
# Usage: ./server/deploy-cgi.sh [CGI_DIR] [ROUTES_FILE]
# ROUTES_FILE should be the merged/toggle-filtered manifest produced by start.sh.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/lib/log.sh"

CGI_DIR="${1:-/usr/lib/cgi-bin/uaa}"
ROUTES_FILE="${2:-$REPO_ROOT/config/routes.yml}"
[[ -f "$ROUTES_FILE" ]] || { error "routes file not found: $ROUTES_FILE"; exit 1; }
mkdir -p "$CGI_DIR"

# Parse the exact route manifest supplied by the caller. In server mode this
# is the merged, toggle-filtered manifest, not the unfiltered source YAML.
python3 - "$ROUTES_FILE" "$CGI_DIR" "$REPO_ROOT" << 'PYEOF'
import yaml, sys, os, stat

routes_file, cgi_dir, repo_root = sys.argv[1], sys.argv[2], sys.argv[3]
with open(routes_file, encoding="utf-8") as f:
    config = yaml.safe_load(f) or {}

for route in config.get('routes', []):
    script_rel = route.get('script', '')
    script_abs = os.path.join(repo_root, script_rel)
    if not script_rel or not os.path.isfile(script_abs):
        print(f"[warn] script not found: {script_rel}", file=sys.stderr)
        continue
    st = os.stat(script_abs)
    os.chmod(script_abs, st.st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
    cgi_name = route.get('cgi_name', os.path.basename(script_abs))
    link = os.path.join(cgi_dir, cgi_name)
    if os.path.lexists(link):
        os.remove(link)
    os.symlink(script_abs, link)
    print(f"  linked {script_rel} -> {link}")
PYEOF

info "CGI deployment complete: $CGI_DIR"
