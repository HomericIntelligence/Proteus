#!/usr/bin/env bats

@test "release workflow exists and triggers on version tags" {
  run grep -E "^[[:space:]]*- 'v\*\.\*\.\*'" .github/workflows/release.yml
  [ "$status" -eq 0 ]
}

@test "release workflow uses --generate-notes" {
  run grep -F -- "--generate-notes" .github/workflows/release.yml
  [ "$status" -eq 0 ]
}

@test "RELEASES.md points users to GitHub Releases" {
  run grep -F "github.com/HomericIntelligence/ProjectProteus/releases" RELEASES.md
  [ "$status" -eq 0 ]
}

@test "docs/releases.md documents SemVer tag format" {
  run grep -E "vX\.Y\.Z|v[0-9]+\.[0-9]+\.[0-9]+" docs/releases.md
  [ "$status" -eq 0 ]
}
