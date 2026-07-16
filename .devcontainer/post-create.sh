#!/usr/bin/env bash
# Provision Proteus prerequisites inside the devcontainer.
#
# Installs: pixi, just, skopeo, shellcheck, Dagger CLI.
# Used by .devcontainer/devcontainer.json's postCreateCommand.

set -euo pipefail

log() { printf '[post-create] %s\n' "$*"; }

log "Updating apt index"
sudo apt-get update -y

log "Installing skopeo and shellcheck"
sudo apt-get install -y --no-install-recommends skopeo shellcheck

log "Installing just"
if ! command -v just >/dev/null 2>&1; then
  curl -fsSL --proto '=https' --tlsv1.2 https://just.systems/install.sh \
    | sudo bash -s -- --to /usr/local/bin
fi

log "Installing pixi"
if ! command -v pixi >/dev/null 2>&1; then
  curl -fsSL https://pixi.sh/install.sh | bash
  # shellcheck disable=SC2016
  echo 'export PATH="$HOME/.pixi/bin:$PATH"' >> "$HOME/.bashrc"
fi

log "Installing Dagger CLI"
if ! command -v dagger >/dev/null 2>&1; then
  curl -fsSL https://dl.dagger.io/dagger/install.sh \
    | BIN_DIR=/usr/local/bin sudo sh
fi

log "Installing dagger node module dependencies"
if [ -d /workspaces/Proteus/dagger ]; then
  ( cd /workspaces/Proteus/dagger && { npm ci || npm install; } )
fi

log "post-create complete"
