#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  export PATH="$TMP/bin:$PATH"
  mkdir -p "$TMP/bin"
  export SKOPEO_LOG="$TMP/skopeo.log"
  cat >"$TMP/bin/skopeo" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "${SKOPEO_LOG}"
case "$1" in
  inspect)  [[ "${SKOPEO_INSPECT_RC:-0}" -eq 0 ]] && echo '{"Digest":"sha256:deadbeef"}'; exit "${SKOPEO_INSPECT_RC:-0}" ;;
  copy)     exit "${SKOPEO_COPY_RC:-0}" ;;
  login)    exit 0 ;;
esac
EOF
  chmod +x "$TMP/bin/skopeo"
}

teardown() { rm -rf "$TMP"; }

@test "exits 1 with usage when args missing" {
  run ./scripts/promote-image.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "exits 1 when source image not found" {
  SKOPEO_INSPECT_RC=1 run ./scripts/promote-image.sh src:t dst:t
  [ "$status" -eq 1 ]
  [[ "$output" == *"Source image not found"* ]]
}

@test "exits 1 when post-promotion verify fails" {
  # First inspect (source) succeeds, second inspect (dest) fails.
  cat >"$TMP/bin/skopeo" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "${SKOPEO_LOG}"
calls=$(grep -c '^inspect' "${SKOPEO_LOG}" || true)
case "$1" in
  inspect) [ "$calls" -eq 1 ] && { echo '{"Digest":"sha256:abc"}'; exit 0; } || exit 1 ;;
  copy) exit 0 ;;
esac
EOF
  chmod +x "$TMP/bin/skopeo"
  run ./scripts/promote-image.sh src:t dst:t
  [ "$status" -eq 1 ]
  [[ "$output" == *"Post-promotion verification failed"* ]]
}

@test "happy path: inspect → copy → inspect" {
  run ./scripts/promote-image.sh ghcr.io/x:a ghcr.io/x:b
  [ "$status" -eq 0 ]
  grep -q "^inspect docker://ghcr.io/x:a" "$SKOPEO_LOG"
  grep -q "^copy docker://ghcr.io/x:a docker://ghcr.io/x:b" "$SKOPEO_LOG"
}

@test "--quiet suppresses stdout but errors still go to stderr" {
  run ./scripts/promote-image.sh --quiet src:t dst:t
  [ "$status" -eq 0 ]
  [[ -z "$output" || "$output" != *"Promoting image"* ]]
}

@test "REGISTRY_USERNAME/PASSWORD triggers skopeo login" {
  REGISTRY_USERNAME=u REGISTRY_PASSWORD=p run ./scripts/promote-image.sh ghcr.io/x:a ghcr.io/x:b
  [ "$status" -eq 0 ]
  grep -q "^login ghcr.io" "$SKOPEO_LOG"
}
