#!/usr/bin/env bash
set -euo pipefail
set -x
IFS=$'\n\t'

BASE_DIR="$(cd "$(dirname "$(dirname "${BASH_SOURCE[0]}")")" && pwd)"
echo "$BASE_DIR"
container build --tag dotfiles-test --file "${BASE_DIR}/Dockerfile" "$BASE_DIR" &&
  container run --name my-dotfiles --interactive --tty --rm dotfiles-test
