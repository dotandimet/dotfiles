#!/usr/bin/env bats

setup() {
  TEST_DIR="$(mktemp -d)"
  REPO="$TEST_DIR/repo"
  mkdir -p "$REPO/tests" "$TEST_DIR/bin"
  cp "$BATS_TEST_DIRNAME/docker_test_mac.sh" "$REPO/tests/"
  touch "$REPO/Dockerfile"
  git -C "$REPO" init -q
  git -C "$REPO" symbolic-ref HEAD refs/heads/feature/test-tags
  git -C "$REPO" add .
  git -C "$REPO" -c user.name=Test -c user.email=test@example.com \
    -c commit.gpgsign=false commit -qm initial
  export BUILD_ARGS="$TEST_DIR/build-args"
  printf '#!/bin/sh\nif [ "$1" = build ]; then printf "%%s\\n" "$@" > "$BUILD_ARGS"; fi\n' > "$TEST_DIR/bin/container"
  chmod +x "$TEST_DIR/bin/container"
  export PATH="$TEST_DIR/bin:$PATH"
  export GITHUB_TOKEN=test-placeholder
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "branch tags are sanitized and clean revision is labeled" {
  run bash "$REPO/tests/docker_test_mac.sh"
  [ "$status" -eq 0 ]
  grep -Fx 'dotfiles-test:feature-test-tags' "$BUILD_ARGS"
  grep -Fx "org.opencontainers.image.revision=$(git -C "$REPO" rev-parse HEAD)" "$BUILD_ARGS"
  grep -Fx 'io.dotfiles.worktree.dirty=false' "$BUILD_ARGS"
}

@test "explicit tags override the branch and dirty worktrees are labeled" {
  printf '# changed\n' >> "$REPO/Dockerfile"
  run bash "$REPO/tests/docker_test_mac.sh" --tag baseline
  [ "$status" -eq 0 ]
  grep -Fx 'dotfiles-test:baseline' "$BUILD_ARGS"
  grep -Fx 'io.dotfiles.worktree.dirty=true' "$BUILD_ARGS"
}

@test "detached HEAD uses a commit tag" {
  git -C "$REPO" checkout --detach -q
  revision="$(git -C "$REPO" rev-parse HEAD)"
  run bash "$REPO/tests/docker_test_mac.sh"
  [ "$status" -eq 0 ]
  grep -Fx "dotfiles-test:commit-${revision:0:12}" "$BUILD_ARGS"
}

@test "invalid tags and missing values fail before building" {
  for tag in 'bad/tag' '-bad' '.bad'; do
    run bash "$REPO/tests/docker_test_mac.sh" --tag "$tag"
    [ "$status" -ne 0 ]
  done
  run bash "$REPO/tests/docker_test_mac.sh" --tag
  [ "$status" -ne 0 ]
  [ ! -e "$BUILD_ARGS" ]
}
