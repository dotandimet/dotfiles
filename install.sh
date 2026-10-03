#!/usr/bin/env bash
# Compatibility entry point for Codespaces/Coder and machines without mise.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v mise >/dev/null 2>&1; then
  MISE="$(command -v mise)"
elif [[ -x "$HOME/.local/bin/mise" ]]; then
  MISE="$HOME/.local/bin/mise"
else
  # Download before executing: a failed transfer must not run a partial script.
  installer="$(mktemp)"
  trap 'rm -f "$installer"' EXIT
  curl -fsSL https://mise.run -o "$installer"
  sh "$installer"
  rm -f "$installer"
  trap - EXIT
  MISE="$HOME/.local/bin/mise"
fi

"$MISE" trust "$SCRIPT_DIR/mise.toml"
exec "$MISE" -C "$SCRIPT_DIR" bootstrap "$@"
