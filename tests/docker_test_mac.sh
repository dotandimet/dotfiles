#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
BASE_DIR="$TEMP_DIR/repo"
mkdir -p "$BASE_DIR"

# Test this worktree, including edits and new bootstrap/test files, not just
# committed HEAD. Never archive ignored runtime state or an external .git file.
while IFS= read -r -d '' path; do
  [[ -f "$REPO_DIR/$path" || -L "$REPO_DIR/$path" ]] && printf '%s\0' "$path"
done < <(
  git -C "$REPO_DIR" ls-files -z --cached -- \
    AGENTS.md CLAUDE.md .gitignore mise.toml install.sh Dockerfile README.md \
    config bin mise scripts tests docs
  # Include new installer/test code, but never untracked application configs.
  git -C "$REPO_DIR" ls-files -z --others --exclude-standard -- mise scripts tests
) >"$TEMP_DIR/paths"
tar -C "$REPO_DIR" --null -T "$TEMP_DIR/paths" -cf "$TEMP_DIR/worktree.tar"
tar -C "$BASE_DIR" -xf "$TEMP_DIR/worktree.tar"
# manifest = "git" requires an index, not the original repository history.
git -C "$BASE_DIR" init -q
git -C "$BASE_DIR" add .

tar -C "$BASE_DIR" -cf "$TEMP_DIR/dotfiles.tar" .
mv "$TEMP_DIR/dotfiles.tar" "$BASE_DIR/dotfiles.tar"

container system status >/dev/null 2>&1 || container system start
build_args=()
export GITHUB_TOKEN="${GITHUB_TOKEN:-$(gh auth token 2>/dev/null || true)}"
if [[ -n "$GITHUB_TOKEN" ]]; then
  build_args+=(--secret 'id=GITHUB_TOKEN,env=GITHUB_TOKEN')
fi
container build --tag dotfiles-test --build-arg DOTFILES_SOURCE=dotfiles.tar \
  "${build_args[@]}" --file "$BASE_DIR/Dockerfile" "$BASE_DIR"
echo "Unprivileged Linux bootstrap and tests passed."
