#!/usr/bin/env bash
# server/start.sh — unified-agnostic-api HTTP server
#
# Starts the API server using shell2http (preferred), webhook, or CGI.
# Supports multiple --routes files and toggle-based route filtering.
#
# Usage:
#   ./server/start.sh [--port PORT] [--host HOST] [--backend BACKEND]
#   ./server/start.sh --routes config/routes.yml --routes extra/routes.yml
#   UAA_PORT=9090 ./server/start.sh
#
# Environment:
#   UAA_PORT     — listen port (default: 8080)
#   UAA_HOST     — listen host (default: 127.0.0.1; loopback only)
#   UAA_BACKEND  — http backend: shell2http | cgi | webhook (default: shell2http)
#   UAA_LOG      — log level: debug | info | warn (default: info)
#   UAA_AUTH     — bearer token; route-level HTTP enforcement is not yet verified
#   UAA_TOGGLES  — path to toggles.yml (default: config/toggles.yml)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$REPO_ROOT/lib/log.sh"
source "$REPO_ROOT/lib/shared.sh"
source "$REPO_ROOT/lib/routes.sh"

UAA_PORT="${UAA_PORT:-8080}"
UAA_HOST="${UAA_HOST:-127.0.0.1}"
UAA_BACKEND="${UAA_BACKEND:-shell2http}"
UAA_LOG="${UAA_LOG:-info}"
# UAA_TOGGLES_FILE is canonical; keep UAA_TOGGLES as a backwards-compatible alias.
UAA_TOGGLES_FILE="${UAA_TOGGLES_FILE:-${UAA_TOGGLES:-$REPO_ROOT/config/toggles.yml}}"
UAA_TOGGLES="$UAA_TOGGLES_FILE"

# Until every backend has a verified route-authentication boundary, do not
# expose this server on a LAN or public interface. Local CLI invocation is
# unaffected; this restriction applies only to the HTTP server launcher.
case "$UAA_HOST" in
  127.*|localhost|::1) ;;
  *)
    error "refusing non-loopback bind ($UAA_HOST): HTTP route authentication is not yet enforced consistently across backends"
    exit 1
    ;;
esac

# Collect --routes arguments; default to config/routes.yml
EXTRA_ROUTES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)    UAA_PORT="$2";    shift 2 ;;
    --host)    UAA_HOST="$2";    shift 2 ;;
    --backend) UAA_BACKEND="$2"; shift 2 ;;
    --log)     UAA_LOG="$2";     shift 2 ;;
    --toggles) UAA_TOGGLES="$2"; UAA_TOGGLES_FILE="$2"; shift 2 ;;
    --routes)  EXTRA_ROUTES+=("$2"); shift 2 ;;
    --help|-h) grep '^#' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) warn "unknown argument: $1"; shift ;;
  esac
done

# Re-check after command-line overrides.
case "$UAA_HOST" in
  127.*|localhost|::1) ;;
  *)
    error "refusing non-loopback bind ($UAA_HOST): HTTP route authentication is not yet enforced consistently across backends"
    exit 1
    ;;
esac

export UAA_PORT UAA_HOST UAA_LOG REPO_ROOT

# Wire shared.sh toggle system — point at config/toggles.yml if it exists
[[ -f "$UAA_TOGGLES_FILE" ]] && export UAA_TOGGLES_FILE || unset UAA_TOGGLES_FILE

# ── Merge route manifests ─────────────────────────────────────────────────────
DEFAULT_ROUTES="$REPO_ROOT/config/routes.yml"
[[ -f "$DEFAULT_ROUTES" ]] || { error "config/routes.yml not found"; exit 1; }

ALL_ROUTES=("$DEFAULT_ROUTES" "${EXTRA_ROUTES[@]}")
MERGED_ROUTES="/tmp/uaa-merged-routes-$$.yml"
trap 'rm -f "$MERGED_ROUTES"' EXIT

merge_routes_files "$UAA_TOGGLES" "$MERGED_ROUTES" "${ALL_ROUTES[@]}"

info "unified-agnostic-api server starting"
info "  backend  : $UAA_BACKEND"
info "  listen   : $UAA_HOST:$UAA_PORT (loopback-only safety mode)"
info "  root     : $REPO_ROOT"
info "  routes   : ${#ALL_ROUTES[@]} file(s) merged"
info "  toggles  : $UAA_TOGGLES"

# ── Backend dispatch ──────────────────────────────────────────────────────────
case "$UAA_BACKEND" in
  shell2http)
    if ! command -v shell2http &>/dev/null; then
      error "shell2http not found. Install: go install github.com/msoap/shell2http@latest"
      exit 1
    fi
    mapfile -t ROUTE_ARGS < <(routes_to_shell2http_args "$MERGED_ROUTES")
    info "registering ${#ROUTE_ARGS[@]} route arg(s)"
    exec shell2http -host "$UAA_HOST" -port "$UAA_PORT" -log "${ROUTE_ARGS[@]}"
    ;;

  cgi)
    CGI_DIR="${CGI_DIR:-/usr/lib/cgi-bin/uaa}"
    info "deploying CGI scripts to $CGI_DIR"
    "$SCRIPT_DIR/deploy-cgi.sh" "$CGI_DIR" "$MERGED_ROUTES"
    info "CGI deployed. Configure Apache to serve $CGI_DIR on port $UAA_PORT."
    ;;

  webhook)
    if ! command -v webhook &>/dev/null; then
      error "webhook not found. Install: go install github.com/adnanh/webhook@latest"
      exit 1
    fi
    HOOKS_FILE="/tmp/uaa-hooks-$$.json"
    trap 'rm -f "$MERGED_ROUTES" "$HOOKS_FILE"' EXIT
    routes_to_hooks_json "$MERGED_ROUTES" > "$HOOKS_FILE"
    exec webhook -hooks "$HOOKS_FILE" -port "$UAA_PORT" -ip "$UAA_HOST" -verbose
    ;;

  *)
    error "unknown backend: $UAA_BACKEND (valid: shell2http | cgi | webhook)"
    exit 1
    ;;
esac
