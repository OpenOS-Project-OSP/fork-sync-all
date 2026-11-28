#!/usr/bin/env bash
# Minimal host validation kept independent of UAA runtime dependencies.

fsa_validate_host() {
  local host="${1:-}"
  case "$host" in
    127.*|localhost|::1)
      return 0
      ;;
    *)
      printf 'ERROR: refusing non-loopback bind (%s): FSA route authentication is not yet enforced consistently across backends\n' "$host" >&2
      return 1
      ;;
  esac
}
