#!/usr/bin/env bash
# scripts/scaffold-consumer.sh — generate a branded UAA consumer layer
#
# Creates a consumer/ directory with routes, toggles, a lib stub, and an
# example adapter. The consumer's routes are served under /api/<prefix>/...
# alongside the base UAA routes (/api/...) when start.sh is given
# --routes consumer/config/routes.yml.
#
# Usage:
#   bash scripts/scaffold-consumer.sh <brand-name> [api-prefix]
#
# Examples:
#   bash scripts/scaffold-consumer.sh "MyOrg API" myorg
#   bash scripts/scaffold-consumer.sh "OpenOS Control" ooc

set -euo pipefail

BRAND="${1:-}"
PREFIX="${2:-}"

[[ -z "$BRAND" ]] && { echo "Usage: $0 <brand-name> [api-prefix]" >&2; exit 1; }

if [[ -z "$PREFIX" ]]; then
  PREFIX=$(echo "$BRAND" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONSUMER_ROOT="$REPO_ROOT/consumer"

echo "[scaffold] brand  : $BRAND" >&2
echo "[scaffold] prefix : $PREFIX" >&2
echo "[scaffold] output : $CONSUMER_ROOT" >&2

mkdir -p "$CONSUMER_ROOT/adapters/meta" "$CONSUMER_ROOT/config" "$CONSUMER_ROOT/lib"

# ── Consumer routes ───────────────────────────────────────────────────────────
cat > "$CONSUMER_ROOT/config/routes.yml" << YAML
# consumer/config/routes.yml — ${BRAND} route manifest
#
# Routes served under /api/${PREFIX}/... alongside UAA base routes.
# Start with: server/start.sh --routes consumer/config/routes.yml

routes:
  - path: /api/${PREFIX}/health
    script: consumer/adapters/meta/health.sh
    method: GET

  # Add your routes below:
  # - path: /api/${PREFIX}/my-resource
  #   script: consumer/adapters/my-resource/list.sh
  #   method: GET
  #   toggle: my_toggle
YAML

# ── Consumer toggles ──────────────────────────────────────────────────────────
cat > "$CONSUMER_ROOT/config/toggles.yml" << YAML
# consumer/config/toggles.yml — ${BRAND} feature toggles
toggles: {}
# example_feature:
#   enabled: true
#   description: Example feature
#   affects:
#     - /api/${PREFIX}/my-resource
YAML

# ── Consumer lib stub ─────────────────────────────────────────────────────────
cat > "$CONSUMER_ROOT/lib/adapter.sh" << 'BASH'
#!/usr/bin/env bash
# consumer/lib/adapter.sh — consumer adapter helpers
# Sources UAA lib/adapter.sh then adds consumer-specific helpers.
[[ -n "${_CONSUMER_ADAPTER_LOADED:-}" ]] && return 0
_CONSUMER_ADAPTER_LOADED=1
_CONSUMER_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_CONSUMER_LIB/../../lib/adapter.sh"
CONSUMER_BRAND="${CONSUMER_BRAND:-}"
consumer_error() { local msg="$1" code="${2:-500}"; echo "{\"ok\":false,\"error\":\"${msg}\"}"; exit 0; }
BASH

# ── Health adapter ────────────────────────────────────────────────────────────
cat > "$CONSUMER_ROOT/adapters/meta/health.sh" << BASH
#!/usr/bin/env bash
# GET /api/${PREFIX}/health
source "\$(dirname "\${BASH_SOURCE[0]}")/../../lib/adapter.sh"
echo '{"ok":true,"brand":"${BRAND}","prefix":"${PREFIX}","status":"healthy"}'
BASH

chmod +x "$CONSUMER_ROOT/adapters/meta/health.sh" "$CONSUMER_ROOT/lib/adapter.sh"

echo "[scaffold] done." >&2
echo "  Start with: server/start.sh --routes consumer/config/routes.yml" >&2
echo "  Add routes to: $CONSUMER_ROOT/config/routes.yml" >&2
echo "  Add adapters to: $CONSUMER_ROOT/adapters/" >&2
