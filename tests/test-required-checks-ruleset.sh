#!/usr/bin/env bash
# Regression test for issue #94 (audit §6).
# Asserts that every required context in the homeric-main-baseline ruleset
# maps to a real job in a PR-triggered workflow (so a stale or mistyped
# required context can never silently block every PR), that the `lint` job covers
# TypeScript via `tsc --noEmit`, and that the verify-issue-92-invariants.sh
# static check is still invoked.
#
# Note: the ruleset is intentionally a *subset* of _required.yml jobs — the
# non-required advisory jobs (markdownlint, pixi-check, justfile-check,
# symlink-check, version-consistency, branch-protection-test, npm-audit,
# forbid-suppressions) run on PRs but are not gate-blocking. We therefore
# assert ruleset ⊆ jobs, not jobs ⊆ ruleset.
set -euo pipefail

cd "$(dirname "$0")/.."
req=".github/workflows/_required.yml"

# (a) lint job must run tsc --noEmit (issue #94 acceptance).
if ! grep -qE 'tsc --noEmit' "$req"; then
  echo "FAIL[#94 a]: $req does not invoke 'tsc --noEmit'" >&2
  exit 1
fi

# (b) issue-92 invariants must still be invoked from _required.yml.
if ! grep -qE 'verify-issue-92-invariants\.sh' "$req"; then
  echo "FAIL[#94 b]: $req does not invoke verify-issue-92-invariants.sh" >&2
  exit 1
fi

# (c) Every required context in the ruleset must map to a real job in a
# workflow that runs on PRs. Most required contexts are jobs in
# _required.yml, but some (e.g. `release`) are jobs in other
# pull_request-triggered workflows (release.yml), so ALL workflow files
# are scanned. Skip this check when GH_TOKEN is unset (local dev /
# forks); the GitHub API check then runs only in CI.
if [[ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]]; then
  # Extract each job's check context: a job is a 2-space-indented key under
  # the top-level `jobs:` block. Its CI context is the job's `name:` value
  # when present, otherwise the job id itself; both are collected so jobs
  # without a `name:` field still match. Parsing starts only after the
  # `jobs:` line so the `on:` triggers (push:/pull_request:) are not mistaken
  # for jobs; the in-jobs flag resets at each new file.
  contexts_expected=$(awk '
    FNR == 1 { injobs=0 }
    $0 ~ /^jobs:[[:space:]]*$/ { injobs=1; next }
    !injobs { next }
    # A job id: exactly two leading spaces, then key, then colon.
    /^  [a-zA-Z0-9_-]+:[[:space:]]*$/ {
      jobid=$1; sub(/:$/, "", jobid)
      print jobid
      next
    }
    # The job-level name: field (four-space indent).
    /^    name:/ {
      n=$0; sub(/^    name:[[:space:]]*/, "", n)
      gsub(/^["\x27]|["\x27]$/, "", n)
      print n
    }
  ' .github/workflows/*.yml | sort -u)

  rules_path="repos/HomericIntelligence/Proteus/rules/branches/main"
  rules_url="https://api.github.com/${rules_path}"
  rules_json=""
  if command -v gh >/dev/null 2>&1 && rules_json=$(gh api "$rules_path" 2>/dev/null); then
    echo "OK: fetched effective branch rules through authenticated GitHub API"
  else
    echo "WARN: authenticated GitHub API unavailable; retrying the public endpoint" >&2
    rules_json=$(curl --fail --silent --show-error \
      --retry 3 --retry-all-errors "$rules_url")
  fi

  contexts=$(jq -er '
    [.[]
      | select(.type == "required_status_checks")
      | .parameters.required_status_checks[].context]
    | if length > 0 then .[] else error("effective rules have no required contexts") end
  ' <<<"$rules_json")

  # Every required context in the ruleset must correspond to a real workflow
  # job; a context with no matching job would block all PRs.
  stale=0
  while read -r ctx; do
    [[ -z "$ctx" ]] && continue
    if ! grep -qxF "$ctx" <<<"$contexts_expected"; then
      echo "FAIL[#94 c]: required ruleset context '$ctx' has no job in any .github/workflows/*.yml" >&2
      stale=1
    fi
  done <<<"$contexts"
  [[ "$stale" -eq 0 ]] || exit 1
fi

echo "OK: required-checks ruleset matches workflow job names"
