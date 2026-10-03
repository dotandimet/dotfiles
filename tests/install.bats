#!/usr/bin/env bats
# Exercise native mise bootstrap in an isolated HOME, without installing tools.

DOTFILES_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  MISE_BIN="$(command -v mise)"
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  REPO="$TEST_DIR/repo with spaces"
  mkdir -p "$HOME" "$REPO/scripts" "$REPO/config/_pi/agent" \
    "$REPO/config/_agents/skills/example" "$REPO/config/lazyvim/_nested" \
    "$REPO/config/git" "$REPO/bin" "$REPO/mise/conf.d"
  cp "$DOTFILES_DIR/mise.toml" "$REPO/"
  cp "$DOTFILES_DIR/scripts/check-dotfiles.sh" "$REPO/scripts/"
  cp "$DOTFILES_DIR"/mise/conf.d/*.toml "$REPO/mise/conf.d/"
  printf 'export DOTFILES_TEST=first\n' >"$REPO/config/_bashrc"
  printf 'source ~/.bashrc\n' >"$REPO/config/_bash_profile"
  printf 'set show-all-if-ambiguous on\n' >"$REPO/config/_inputrc"
  printf '[alias]\n  example = status\n' >"$REPO/config/git/config"
  printf '*.log\n' >"$REPO/config/git/ignore"
  printf 'return {}\n' >"$REPO/config/lazyvim/init.lua"
  printf 'hidden\n' >"$REPO/config/lazyvim/.tracked"
  printf 'nested\n' >"$REPO/config/lazyvim/_nested/config"
  printf '{}\n' >"$REPO/config/_pi/agent/settings.json"
  printf 'skill\n' >"$REPO/config/_agents/skills/example/SKILL.md"
  printf '#!/bin/sh\necho test\n' >"$REPO/bin/example"
  chmod +x "$REPO/bin/example"
  git -C "$REPO" init -q
  git -C "$REPO" add .
}

teardown() {
  rm -rf "$TEST_DIR"
}

# env -i prevents the calling shell's mise activation/cache from leaking in.
_mise() {
  env -i PATH="$PATH" HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    MISE_DATA_DIR="$TEST_DIR/data" MISE_STATE_DIR="$TEST_DIR/state" \
    MISE_CACHE_DIR="$TEST_DIR/cache" MISE_SYSTEM_CONFIG_DIR="$TEST_DIR/system" \
    MISE_TRUSTED_CONFIG_PATHS="$TEST_DIR" MISE_YES=1 \
    "$MISE_BIN" -C "$REPO" "$@"
}

_apply() {
  _mise bootstrap --only dotfiles --yes
}

@test "bootstrap copies configs and scripts into real files and directories" {
  run _apply
  [ "$status" -eq 0 ]
  for pair in 'config/lazyvim/init.lua:.config/lazyvim/init.lua' \
    'config/_pi/agent/settings.json:.pi/agent/settings.json' \
    'config/_agents/skills/example/SKILL.md:.agents/skills/example/SKILL.md' \
    'bin/example:.local/bin/example'; do
    target="$HOME/${pair#*:}"
    [ ! -L "$target" ]
    cmp "$REPO/${pair%%:*}" "$target"
  done
  [ ! -L "$HOME/.pi" ]
  [ ! -L "$XDG_CONFIG_HOME/lazyvim" ]
  [ -x "$HOME/.local/bin/example" ]
  [ ! -e "$XDG_CONFIG_HOME/_pi" ]
}

@test "block edits preserve existing shell, inputrc and Git customizations" {
  mkdir -p "$XDG_CONFIG_HOME/git"
  for target in .bashrc .bash_profile .inputrc .config/git/config; do
    printf '# environment customization\n' >"$HOME/$target"
  done
  run _apply
  [ "$status" -eq 0 ]
  for target in .bashrc .bash_profile .inputrc .config/git/config; do
    grep -qx '# environment customization' "$HOME/$target"
    [ "$(grep -c '^# >>> mise:dotfiles >>>' "$HOME/$target")" -eq 1 ]
    [ "$(grep -c '^# <<< mise:dotfiles <<<' "$HOME/$target")" -eq 1 ]
  done
  grep -qx 'export DOTFILES_TEST=first' "$HOME/.bashrc"
}

@test "reapply is idempotent and replaces only the fenced content" {
  _apply
  printf '# customization after block\n' >>"$HOME/.bashrc"
  cp "$HOME/.bashrc" "$TEST_DIR/before"
  run _apply
  [ "$status" -eq 0 ]
  cmp "$TEST_DIR/before" "$HOME/.bashrc"
  printf 'export DOTFILES_TEST=second\n' >"$REPO/config/_bashrc"
  run _apply
  [ "$status" -eq 0 ]
  grep -qx 'export DOTFILES_TEST=second' "$HOME/.bashrc"
  ! grep -q 'DOTFILES_TEST=first' "$HOME/.bashrc"
  grep -qx '# customization after block' "$HOME/.bashrc"
  [ "$(grep -c '^# >>> mise:dotfiles >>>' "$HOME/.bashrc")" -eq 1 ]
}

@test "only indexed files are copied, including hidden and nested underscore names" {
  printf 'private\n' >"$REPO/config/_pi/agent/auth.json"
  printf 'ignored.log\n' >"$REPO/.gitignore"
  touch "$REPO/config/lazyvim/ignored.log" "$REPO/bin/untracked"
  run _apply
  [ "$status" -eq 0 ]
  [ -f "$XDG_CONFIG_HOME/lazyvim/.tracked" ]
  [ -f "$XDG_CONFIG_HOME/lazyvim/_nested/config" ]
  [ ! -e "$HOME/.pi/agent/auth.json" ]
  [ ! -e "$XDG_CONFIG_HOME/lazyvim/ignored.log" ]
  [ ! -e "$HOME/.local/bin/untracked" ]
}

@test "copies sync from source without deleting unrelated runtime state" {
  _apply
  mkdir -p "$HOME/.pi/agent/sessions"
  printf 'credential\n' >"$HOME/.pi/agent/auth.json"
  printf 'session\n' >"$HOME/.pi/agent/sessions/local.json"
  printf 'local edit\n' >"$XDG_CONFIG_HOME/lazyvim/init.lua"
  grep -qx 'return {}' "$REPO/config/lazyvim/init.lua"
  printf 'return { updated = true }\n' >"$REPO/config/lazyvim/init.lua"
  run _apply
  [ "$status" -eq 0 ]
  cmp "$REPO/config/lazyvim/init.lua" "$XDG_CONFIG_HOME/lazyvim/init.lua"
  grep -qx credential "$HOME/.pi/agent/auth.json"
  grep -qx session "$HOME/.pi/agent/sessions/local.json"
  [ ! -e "$REPO/config/_pi/agent/auth.json" ]
}

@test "deleted source copies are left for explicit cleanup" {
  _apply
  git -C "$REPO" rm -q -f config/lazyvim/init.lua
  run _apply
  [ "$status" -eq 0 ]
  [ -f "$XDG_CONFIG_HOME/lazyvim/init.lua" ]
}

@test "dry run does not write dotfiles" {
  run _mise bootstrap --only dotfiles --dry-run
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.bashrc" ]
  [ ! -e "$HOME/.pi" ]
  [ ! -e "$HOME/.local/bin/example" ]
  [[ "$output" != *"ignoring entry"* ]]
}

@test "native status converges after apply" {
  _apply
  run _mise dot status --missing
  [ "$status" -eq 0 ]
  [[ "$output" != *"ignoring entry"* ]]
}

@test "legacy leaf links for copy entries become copies without changing the source" {
  mkdir -p "$XDG_CONFIG_HOME/lazyvim"
  ln -s "$REPO/config/lazyvim/init.lua" "$XDG_CONFIG_HOME/lazyvim/init.lua"
  run _apply
  [ "$status" -eq 0 ]
  [ ! -L "$XDG_CONFIG_HOME/lazyvim/init.lua" ]
  grep -qx 'return {}' "$REPO/config/lazyvim/init.lua"
}

@test "legacy directory links fail before any files are deployed" {
  ln -s "$REPO/config/_pi" "$HOME/.pi"
  run _apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"directory symlink"* ]]
  [ ! -e "$HOME/.bashrc" ]
  [ ! -e "$XDG_CONFIG_HOME/lazyvim" ]
}

@test "nested directory links fail before writes" {
  mkdir -p "$HOME/.pi"
  ln -s "$REPO/config/_pi/agent" "$HOME/.pi/agent"
  run _apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"directory symlink"* ]]
  [ ! -e "$HOME/.bashrc" ]
}

@test "block target symlinks fail without changing the linked source" {
  ln -s "$REPO/config/_bashrc" "$HOME/.bashrc"
  run _apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"is a symlink"* ]]
  grep -qx 'export DOTFILES_TEST=first' "$REPO/config/_bashrc"
  ! grep -q 'mise:dotfiles' "$REPO/config/_bashrc"
  [ ! -e "$HOME/.pi" ]
}

@test "corrupt block markers are refused" {
  printf '# >>> mise:dotfiles >>> managed by mise - do not edit between markers\nlocal content\n' >"$HOME/.bashrc"
  cp "$HOME/.bashrc" "$TEST_DIR/before"
  run _apply
  [ "$status" -ne 0 ]
  cmp "$TEST_DIR/before" "$HOME/.bashrc"
}

@test "custom XDG_CONFIG_HOME is rejected instead of silently deploying to the wrong path" {
  export XDG_CONFIG_HOME="$TEST_DIR/custom-config"
  run _apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"requires XDG_CONFIG_HOME"* ]]
  [ ! -e "$HOME/.bashrc" ]
}

@test "tool fragments are available globally without replacing personal mise config" {
  mkdir -p "$XDG_CONFIG_HOME/mise"
  printf '[env]\nPERSONAL_SETTING = "keep"\n' >"$XDG_CONFIG_HOME/mise/config.toml"
  _apply
  for name in common linux macos; do
    cmp "$REPO/mise/conf.d/dotfiles-$name.toml" "$XDG_CONFIG_HOME/mise/conf.d/dotfiles-$name.toml"
  done
  grep -q PERSONAL_SETTING "$XDG_CONFIG_HOME/mise/config.toml"
  cd "$HOME"
  REPO="$HOME"
  run _mise config ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"dotfiles-common.toml"* ]]
  [[ "$output" == *"dotfiles-linux.toml"* ]]
  [[ "$output" == *"dotfiles-macos.toml"* ]]
}

@test "Linux manifest uses prebuilt user tools and macOS packages have explicit selectors" {
  ! grep -q '^\[bootstrap.packages\]' "$REPO/mise/conf.d/dotfiles-linux.toml"
  [ "$(grep -c 'os = \["linux"\]' "$REPO/mise/conf.d/dotfiles-linux.toml")" -eq 2 ]
  [ "$(grep -c '^"brew.*os = "macos"' "$REPO/mise/conf.d/dotfiles-macos.toml")" -eq 8 ]
}
