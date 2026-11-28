#!/usr/bin/env python3
"""
scripts/uaa-merge-routes.py — merge multiple UAA route manifests with toggle filtering

Usage: uaa-merge-routes.py <toggles.yml> <out.yml> <routes1.yml> [routes2.yml ...]

Reads each routes file in order, filters routes whose toggle is disabled in
toggles.yml, merges all active routes into out.yml. Used by lib/routes.sh
merge_routes_files() and server/start.sh.
"""
import yaml, sys, os

toggles_file = sys.argv[1]
out_file     = sys.argv[2]
route_files  = sys.argv[3:]

toggles = {}
if os.path.isfile(toggles_file):
    with open(toggles_file) as f:
        tgl = yaml.safe_load(f) or {}
    toggles = tgl.get('toggles', {}) or {}

all_routes = []
for rf in route_files:
    if not os.path.isfile(rf):
        print(f'[uaa/merge-routes] not found: {rf}', file=sys.stderr)
        continue
    with open(rf) as f:
        cfg = yaml.safe_load(f) or {}
    for route in cfg.get('routes', []) or []:
        toggle_name = route.get('toggle')
        if toggle_name:
            t = toggles.get(toggle_name, {})
            if not t.get('enabled', True):
                print(f'[uaa/merge-routes] toggle \'{toggle_name}\' disabled — skipping {route.get("path")}', file=sys.stderr)
                continue
        all_routes.append(route)

with open(out_file, 'w') as f:
    yaml.dump({'routes': all_routes}, f, default_flow_style=False, allow_unicode=True, sort_keys=False)

print(f'[uaa/merge-routes] {len(all_routes)} routes from {len(route_files)} file(s) → {out_file}', file=sys.stderr)
