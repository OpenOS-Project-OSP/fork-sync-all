#!/usr/bin/env bash
# Verify FSA API rejects network binds before loading optional UAA runtime files.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

source fsa-api/server/host-guard.sh

for host in 127.0.0.1 localhost ::1; do
  fsa_validate_host "$host"
done

for host in 0.0.0.0 192.0.2.10 2001:db8::1; do
  if output="$(fsa_validate_host "$host" 2>&1)"; then
    echo "ERROR: non-loopback host '$host' unexpectedly accepted" >&2
    exit 1
  fi
  if ! grep -q "refusing non-loopback bind" <<<"$output"; then
    echo "ERROR: host '$host' failed for an unexpected reason:" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
done

expect_launcher_rejection() {
  local label="$1"
  shift
  local output
  if output="$(env -u GH_TOKEN "$@" bash fsa-api/server/fsa-start.sh 2>&1)"; then
    echo "ERROR: $label unexpectedly accepted" >&2
    exit 1
  fi
  if ! grep -q "refusing non-loopback bind" <<<"$output"; then
    echo "ERROR: $label reached a later failure instead of the host guard:" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

expect_launcher_rejection "non-loopback environment bind" FSA_HOST=0.0.0.0

output="$(env -u GH_TOKEN FSA_HOST=127.0.0.1 bash fsa-api/server/fsa-start.sh --host 192.0.2.10 2>&1)" || status=$?
if [[ "${status:-0}" -eq 0 ]] || ! grep -q "refusing non-loopback bind" <<<"$output"; then
  echo "ERROR: non-loopback command-line override was not rejected:" >&2
  printf '%s\n' "$output" >&2
  exit 1
fi

echo "FSA API loopback containment: ok"
