#!/usr/bin/env bash
set -euo pipefail
set -x
IFS=$'\n\t'

REPO_DIR="$(cd "$(dirname "$(dirname "${BASH_SOURCE[0]}")")" && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
BASE_DIR="${TEMP_DIR}/repo"

# Test committed HEAD only, without untracked runtime files (such as sockets).
# --no-local honors --depth even when cloning from a local filesystem path.
git clone --depth 1 --no-local "$REPO_DIR" "$BASE_DIR"
# Send nested files in one top-level archive: some container CLI versions
# silently omit directory contents when transferring a build context.
git -C "$BASE_DIR" archive --format=tar --output="${BASE_DIR}/dotfiles.tar" HEAD
echo "$BASE_DIR"

# check container system is up and running
container system status >&/dev/null || container system start
container build --tag dotfiles-test --build-arg DOTFILES_SOURCE=dotfiles.tar \
  --file "${BASE_DIR}/Dockerfile" "$BASE_DIR" &&
  container run --name my-dotfiles --interactive --tty --rm dotfiles-test
