# shellcheck shell=bash
# Structured logging helper for Proteus shell scripts.
#
# Source this file from a script:
#
#   #!/usr/bin/env bash
#   set -euo pipefail
#   # shellcheck source=scripts/lib/log.sh
#   source "$(dirname "$0")/lib/log.sh"
#
#   log_info "starting promote"
#   log_warn "unexpected response: %s" "$resp"
#   log_error "skopeo failed (exit %d)" "$?"
#
# Output is a single line per call, prefixed with an ISO-8601 timestamp,
# the calling script's basename, and a severity level. Errors and warnings
# go to stderr; info/debug to stdout. Output is plain text (Bash 4-safe);
# downstream log aggregators can parse the prefix.

_proteus_log_script_name() {
  # The script that *sourced* this file.
  basename "${BASH_SOURCE[2]:-${BASH_SOURCE[1]:-$0}}"
}

_proteus_log_ts() {
  date -u +'%Y-%m-%dT%H:%M:%SZ'
}

_proteus_log_emit() {
  local level="$1"; shift
  local fd="$1"; shift
  local fmt="$1"
  # `shift` after consuming the format string may have no remaining
  # arguments; that is intentional, so guard with a positional check
  # rather than the forbidden `|| true` silent-failure idiom.
  if [ "$#" -gt 0 ]; then
    shift
  fi
  # shellcheck disable=SC2059
  printf '%s level=%s script=%s message="%s"\n' \
    "$(_proteus_log_ts)" \
    "$level" \
    "$(_proteus_log_script_name)" \
    "$(printf "$fmt" "$@")" >&"$fd"
}

log_debug() {
  [ "${LOG_LEVEL:-INFO}" = "DEBUG" ] || return 0
  _proteus_log_emit DEBUG 1 "$@"
}

log_info() {
  _proteus_log_emit INFO 1 "$@"
}

log_warn() {
  _proteus_log_emit WARN 2 "$@"
}

log_error() {
  _proteus_log_emit ERROR 2 "$@"
}
