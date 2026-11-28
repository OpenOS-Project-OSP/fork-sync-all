#!/usr/bin/env bash
# lib/routes.sh — route manifest parser
#
# Reads one or more routes.yml files, applies toggle filtering, merges them,
# and emits backend-specific argument lists for shell2http, webhook, or CGI.
#
# New in this version:
#   - merge_routes_files: merges multiple route manifests into one temp file
#   - toggle filtering: routes with a toggle: field are skipped when disabled
#     in config/toggles.yml
#   - Existing routes_to_shell2http_args / routes_to_hooks_json unchanged

[[ -n "${_UAA_ROUTES_LOADED:-}" ]] && return 0
_UAA_ROUTES_LOADED=1

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/log.sh"

# merge_routes_files TOGGLES_FILE OUT_FILE ROUTES_FILE [ROUTES_FILE ...]
# Merges multiple route manifests, applies toggle filtering, writes to OUT_FILE.
# Caller is responsible for cleaning up OUT_FILE.
merge_routes_files() {
  local toggles_file="$1" out_file="$2"
  shift 2
  python3 scripts/uaa-merge-routes.py "$toggles_file" "$out_file" "$@"
}

# routes_to_shell2http_args ROUTES_FILE
# Emits alternating PATH SCRIPT pairs for shell2http, one per line.
routes_to_shell2http_args() {
  local routes_file="$1"
  python3 - "$routes_file" "$REPO_ROOT" << 'PYEOF'
import yaml, sys, os
routes_file, repo_root = sys.argv[1], sys.argv[2]
with open(routes_file) as f:
    config = yaml.safe_load(f)
for route in config.get('routes', []):
    path   = route.get('path', '')
    script = route.get('script', '')
    if not path or not script:
        continue
    script_abs = os.path.join(repo_root, script)
    if not os.path.isfile(script_abs):
        print(f'[warn] script not found: {script}', file=sys.stderr)
        continue
    print(path)
    print(f'bash {script_abs}')
PYEOF
}

# routes_to_hooks_json ROUTES_FILE — emit webhook hooks.json
routes_to_hooks_json() {
  local routes_file="$1"
  python3 - "$routes_file" "$REPO_ROOT" << 'PYEOF'
import yaml, sys, os, json
routes_file, repo_root = sys.argv[1], sys.argv[2]
with open(routes_file) as f:
    config = yaml.safe_load(f)
hooks = []
for route in config.get('routes', []):
    hook_id    = route.get('path', '').lstrip('/').replace('/', '-')
    script     = route.get('script', '')
    script_abs = os.path.join(repo_root, script)
    if not hook_id or not script:
        continue
    hooks.append({
        'id': hook_id,
        'execute-command': script_abs,
        'command-working-directory': repo_root,
        'response-message': 'queued',
        'trigger-rule': {
            'match': {
                'type': 'value',
                'value': route.get('secret', ''),
                'parameter': {'source': 'header', 'name': 'X-Hook-Secret'}
            }
        } if route.get('secret') else {}
    })
print(json.dumps(hooks, indent=2))
PYEOF
}
