#!/usr/bin/env bash
# validate-host.sh — Validate a Myrmidons dispatch host against
# RFC 1123 format AND configs/allowed-hosts.txt. Fails closed.
# See docs/dispatch-contract.md and issue #97.

set -euo pipefail

validate_host() {
    local host="${1:-}"
    local allowlist="${2:-configs/allowed-hosts.txt}"
    local pattern='^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$'

    if [[ -z "$host" ]]; then
        echo "Error: host is empty. See docs/dispatch-contract.md (#97)." >&2
        return 1
    fi
    if [[ ! "$host" =~ $pattern ]]; then
        # Do NOT echo the raw host — it may contain control characters.
        echo "Error: host failed RFC 1123 format check. See docs/dispatch-contract.md (#97)." >&2
        return 1
    fi
    if [[ ! -r "$allowlist" ]]; then
        echo "Error: allowlist file not readable: ${allowlist} (#97)." >&2
        return 1
    fi
    # grep -Fx: fixed-string, full-line match; strip comments/blanks first.
    if ! grep -vE '^\s*(#|$)' "$allowlist" | grep -Fxq -- "$host"; then
        echo "Error: host '${host}' is not in allowlist ${allowlist}. See docs/dispatch-contract.md (#97)." >&2
        return 1
    fi
    return 0
}

# Allow direct invocation: `scripts/validate-host.sh <host> [allowlist]`
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    validate_host "$@"
fi
