#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [--tag TAG]"
  echo "Build dotfiles-test:TAG from this worktree (default: sanitized branch or commit-SHA)."
}

tag=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      [[ $# -ge 2 && -n "$2" ]] || { usage >&2; exit 1; }
      tag="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
  esac
done

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
revision="$(git -C "$REPO_DIR" rev-parse HEAD)"
branch="$(git -C "$REPO_DIR" symbolic-ref --quiet --short HEAD || true)"
if [[ -z "$tag" ]]; then
  tag="${branch:-commit-${revision:0:12}}"
  tag="$(printf '%s' "$tag" | LC_ALL=C tr -c 'a-zA-Z0-9_.-' '-')"
  while [[ "$tag" == [.-]* ]]; do tag="${tag:1}"; done
  tag="${tag:0:128}"
fi
if [[ ! "$tag" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$ || ${#tag} -gt 128 ]]; then
  echo "Invalid image tag: $tag" >&2
  exit 1
fi
image="dotfiles-test:$tag"
dirty=false
[[ -z "$(git -C "$REPO_DIR" status --porcelain)" ]] || dirty=true

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
container build --tag "$image" --build-arg DOTFILES_SOURCE=dotfiles.tar \
  --label "org.opencontainers.image.revision=$revision" \
  --label "io.dotfiles.worktree.dirty=$dirty" \
  "${build_args[@]}" --file "$BASE_DIR/Dockerfile" "$BASE_DIR"
echo "Unprivileged Linux bootstrap and tests passed: $image"
