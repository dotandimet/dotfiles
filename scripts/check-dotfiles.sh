#!/usr/bin/env bash
# Fail before any copies/edits if legacy directory links could write into the
# checkout. Leaf links in copy-mode destinations are replaced safely by mise.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "${XDG_CONFIG_HOME:-$HOME/.config}" != "$HOME/.config" ]]; then
  echo "This mise dotfiles manifest requires XDG_CONFIG_HOME=$HOME/.config." >&2
  echo "mise does not expand environment variables in dotfile target paths." >&2
  exit 1
fi

check_parents() {
  local path="$1"
  while [[ "$path" != / && "$path" != "$HOME" ]]; do
    if [[ -L "$path" ]]; then
      echo "$path is a directory symlink; migrate it to a real directory first (see README.md)." >&2
      exit 1
    fi
    path="${path%/*}"
  done
}

# Include nested directories, not just the top-level deployment roots.
while IFS= read -r -d '' file; do
  case "$file" in
    config/_bashrc|config/_bash_profile|config/_inputrc) continue ;;
    config/_pi/*|config/_agents/*) target="$HOME/.${file#config/_}" ;;
    config/*) target="$HOME/.config/${file#config/}" ;;
    bin/*) target="$HOME/.local/bin/${file#bin/}" ;;
    mise/conf.d/*) target="$HOME/.config/mise/conf.d/${file#mise/conf.d/}" ;;
    *) continue ;;
  esac
  check_parents "${target%/*}"
done < <(git -C "$repo" ls-files -z -- config bin mise/conf.d)

# Blocks cannot safely edit symlinks. Reject all of them before copying files.
for target in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.inputrc" "$HOME/.config/git/config"; do
  check_parents "${target%/*}"
  if [[ -L "$target" ]]; then
    echo "$target is a symlink; back it up and migrate to a regular file first (see README.md)." >&2
    exit 1
  fi
done
