#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  SCRIPT="$(pwd)/scripts/check-symlinks.sh"
  cp "$SCRIPT" "$TMP/check-symlinks.sh"
  cd "$TMP"
  mkdir .git
}

teardown() { cd /tmp && rm -rf "$TMP"; }

@test "passes when no symlinks present" {
  run bash check-symlinks.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"All symlinks are valid"* ]]
}

@test "passes when symlinks resolve" {
  echo hi > target
  ln -s target alias
  run bash check-symlinks.sh
  [ "$status" -eq 0 ]
}

@test "fails with broken symlink" {
  ln -s nowhere broken
  run bash check-symlinks.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"Broken symlinks"* ]]
  [[ "$output" == *"broken -> nowhere"* ]]
}
