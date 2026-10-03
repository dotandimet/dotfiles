#!/usr/bin/env bats
# Tests for install.sh symlink behavior

DOTFILES_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  mkdir -p "$HOME"

  TEST_CONF_DIR="$TEST_DIR/config"
  mkdir -p "$TEST_CONF_DIR/nvim" "$TEST_CONF_DIR/tmux" \
    "$TEST_CONF_DIR/_pi/agent" "$TEST_CONF_DIR/_agents/skills/example"
  touch "$TEST_CONF_DIR/_bashrc" "$TEST_CONF_DIR/_bash_profile" "$TEST_CONF_DIR/_inputrc"
  touch "$TEST_CONF_DIR/nvim/init.lua" "$TEST_CONF_DIR/tmux/tmux.conf"
  printf '{}\n' >"$TEST_CONF_DIR/_pi/agent/settings.json"
  touch "$TEST_CONF_DIR/_agents/skills/example/SKILL.md"
  git -C "$TEST_DIR" init -q
  git -C "$TEST_DIR" add config
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Exercise only symlink installation, without curl/mise/brew.
_run_install() {
  # shellcheck source=/dev/null
  source "$DOTFILES_DIR/install.sh"
  install_links "$TEST_CONF_DIR"
}

_run_install_with_test_scripts() {
  source "$DOTFILES_DIR/install.sh"
  SCRIPT_DIR="$TEST_DIR"
  install_links "$TEST_CONF_DIR"
}

@test "missing config directory fails without creating a literal wildcard link" {
  rm -rf "$TEST_CONF_DIR"
  run _run_install
  [ "$status" -ne 0 ]
  [[ "$output" == *"No configuration files found"* ]]
  [ ! -L "$XDG_CONFIG_HOME/*" ]
}

@test "empty config directory fails without creating a literal wildcard link" {
  rm -rf "$TEST_CONF_DIR"
  mkdir -p "$TEST_CONF_DIR"
  run _run_install
  [ "$status" -ne 0 ]
  [[ "$output" == *"No configuration files found"* ]]
  [ ! -L "$XDG_CONFIG_HOME/*" ]
}

@test "config source must be in a git repository" {
  rm -rf "$TEST_DIR/.git"
  run _run_install
  [ "$status" -ne 0 ]
  [ ! -L "$HOME/.bashrc" ]
}

@test "missing scripts directory fails without creating a literal wildcard link" {
  run _run_install_with_test_scripts
  [ "$status" -ne 0 ]
  [[ "$output" == *"No scripts found"* ]]
  [ ! -L "$HOME/.local/bin/*" ]
}

@test "empty scripts directory fails without creating a literal wildcard link" {
  mkdir -p "$TEST_DIR/bin"
  run _run_install_with_test_scripts
  [ "$status" -ne 0 ]
  [[ "$output" == *"No scripts found"* ]]
  [ ! -L "$HOME/.local/bin/*" ]
}

@test "config directory paths containing spaces are supported" {
  git -C "$TEST_DIR" mv config 'config with spaces'
  TEST_CONF_DIR="$TEST_DIR/config with spaces"
  run _run_install
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.bashrc")" = "$TEST_CONF_DIR/_bashrc" ]
}

@test "underscore-prefixed files are symlinked under HOME" {
  run _run_install
  [ "$status" -eq 0 ]
  for name in bashrc bash_profile inputrc; do
    [ "$(readlink "$HOME/.$name")" = "$TEST_CONF_DIR/_$name" ]
    [ ! -e "$XDG_CONFIG_HOME/_$name" ]
  done
}

@test "agent files are linked inside real HOME directories" {
  run _run_install
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.pi/agent/settings.json")" = "$TEST_CONF_DIR/_pi/agent/settings.json" ]
  [ "$(readlink "$HOME/.agents/skills/example/SKILL.md")" = "$TEST_CONF_DIR/_agents/skills/example/SKILL.md" ]
  for name in pi agents; do
    [ -d "$HOME/.$name" ]
    [ ! -L "$HOME/.$name" ]
    [ ! -e "$XDG_CONFIG_HOME/_$name" ]
    [ ! -e "$XDG_CONFIG_HOME/$name" ]
  done
  [ ! -L "$HOME/.pi/agent" ]
  [ ! -L "$HOME/.agents/skills/example" ]
}

@test "custom XDG_CONFIG_HOME applies only to non-underscore paths" {
  export XDG_CONFIG_HOME="$TEST_DIR/custom-config"
  run _run_install
  [ "$status" -eq 0 ]
  [ "$(readlink "$XDG_CONFIG_HOME/nvim/init.lua")" = "$TEST_CONF_DIR/nvim/init.lua" ]
  [ "$(readlink "$HOME/.pi/agent/settings.json")" = "$TEST_CONF_DIR/_pi/agent/settings.json" ]
  [ ! -e "$XDG_CONFIG_HOME/_pi" ]
}

@test "existing directories and runtime state are left in place" {
  mkdir -p "$HOME/.pi/agent/sessions" "$XDG_CONFIG_HOME/nvim"
  printf 'session\n' >"$HOME/.pi/agent/sessions/local.json"
  printf 'local state\n' >"$XDG_CONFIG_HOME/nvim/runtime.txt"
  run _run_install
  [ "$status" -eq 0 ]
  run _run_install
  [ "$status" -eq 0 ]
  grep -qx session "$HOME/.pi/agent/sessions/local.json"
  grep -qx 'local state' "$XDG_CONFIG_HOME/nvim/runtime.txt"
  [ ! -e "$TEST_CONF_DIR/_pi/agent/sessions" ]
  [ ! -e "$TEST_CONF_DIR/nvim/runtime.txt" ]
  [ ! -e "$HOME/.pi_bak" ]
}

@test "XDG files are linked individually, not their directories" {
  run _run_install
  [ "$status" -eq 0 ]
  [ ! -L "$XDG_CONFIG_HOME/nvim" ]
  [ "$(readlink "$XDG_CONFIG_HOME/nvim/init.lua")" = "$TEST_CONF_DIR/nvim/init.lua" ]
  [ ! -L "$XDG_CONFIG_HOME/tmux" ]
  [ "$(readlink "$XDG_CONFIG_HOME/tmux/tmux.conf")" = "$TEST_CONF_DIR/tmux/tmux.conf" ]
}

@test "only tracked files are linked, including hidden files" {
  touch "$TEST_CONF_DIR/nvim/untracked.log" "$TEST_CONF_DIR/nvim/ignored.log"
  printf 'ignored.log\n' >"$TEST_CONF_DIR/.gitignore"
  touch "$TEST_CONF_DIR/nvim/.tracked"
  git -C "$TEST_DIR" add config/.gitignore config/nvim/.tracked
  run _run_install
  [ "$status" -eq 0 ]
  [ "$(readlink "$XDG_CONFIG_HOME/nvim/.tracked")" = "$TEST_CONF_DIR/nvim/.tracked" ]
  [ ! -e "$XDG_CONFIG_HOME/nvim/untracked.log" ]
  [ ! -e "$XDG_CONFIG_HOME/nvim/ignored.log" ]
}

@test "filenames with spaces and newlines are supported and nested underscores are preserved" {
  local name=$'_nested/file with space\nand newline'
  mkdir -p "$TEST_CONF_DIR/nvim/_nested"
  touch "$TEST_CONF_DIR/nvim/$name"
  git -C "$TEST_DIR" add config
  run _run_install
  [ "$status" -eq 0 ]
  [ "$(readlink "$XDG_CONFIG_HOME/nvim/$name")" = "$TEST_CONF_DIR/nvim/$name" ]
}

@test "underscore convention works for arbitrary names without a hardcoded list" {
  mkdir -p "$TEST_CONF_DIR/_example/_nested"
  touch "$TEST_CONF_DIR/_example/_nested/settings"
  git -C "$TEST_DIR" add config
  run _run_install
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.example/_nested/settings")" = "$TEST_CONF_DIR/_example/_nested/settings" ]
}

@test "tracked files deleted from the worktree are skipped" {
  rm "$TEST_CONF_DIR/nvim/init.lua"
  run _run_install
  [ "$status" -eq 0 ]
  [ ! -L "$XDG_CONFIG_HOME/nvim/init.lua" ]
}

@test "tracked file symlinks are supported but directory symlinks are not installed" {
  ln -s init.lua "$TEST_CONF_DIR/nvim/alias.lua"
  ln -s missing.lua "$TEST_CONF_DIR/nvim/dangling.lua"
  ln -s nvim "$TEST_CONF_DIR/directory-link"
  git -C "$TEST_DIR" add config
  run _run_install
  [ "$status" -eq 0 ]
  run _run_install
  [ "$status" -eq 0 ]
  [ "$(readlink "$XDG_CONFIG_HOME/nvim/alias.lua")" = "$TEST_CONF_DIR/nvim/alias.lua" ]
  [ "$(readlink "$XDG_CONFIG_HOME/nvim/dangling.lua")" = "$TEST_CONF_DIR/nvim/dangling.lua" ]
  [ ! -L "$XDG_CONFIG_HOME/directory-link" ]
  [ -z "$(find "$HOME" -name '*_bak')" ]
}

@test "legacy directory symlinks fail safely without modifying source files" {
  ln -s "$TEST_CONF_DIR/_pi" "$HOME/.pi"
  run _run_install
  [ "$status" -ne 0 ]
  [[ "$output" == *"replace it with a real directory"* ]]
  [ ! -L "$TEST_CONF_DIR/_pi/agent/settings.json" ]
  [ ! -e "$TEST_CONF_DIR/_pi/agent/settings.json_bak" ]
}

@test "nested directory symlinks also fail safely" {
  mkdir -p "$HOME/.pi"
  ln -s "$TEST_CONF_DIR/_pi/agent" "$HOME/.pi/agent"
  run _run_install
  [ "$status" -ne 0 ]
  [ ! -L "$TEST_CONF_DIR/_pi/agent/settings.json" ]
}

@test "scripts from bin are still symlinked into ~/.local/bin" {
  run _run_install
  [ "$status" -eq 0 ]
  [ -d "$HOME/.local/bin" ]
  for script in "$DOTFILES_DIR"/bin/*; do
    name="$(basename "$script")"
    [ "$(readlink "$HOME/.local/bin/$name")" = "$script" ]
  done
}

@test "existing regular file is backed up with _bak suffix" {
  echo "original content" >"$HOME/.bashrc"
  run _run_install
  [ "$status" -eq 0 ]
  [ -L "$HOME/.bashrc" ]
  grep -qx 'original content' "$HOME/.bashrc_bak"
}

@test "wrong symlink is replaced and backed up" {
  ln -s /dev/null "$HOME/.bashrc"
  run _run_install
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.bashrc")" = "$TEST_CONF_DIR/_bashrc" ]
  [ "$(readlink "$HOME/.bashrc_bak")" = /dev/null ]
}

@test "running install twice does not create backups" {
  run _run_install
  [ "$status" -eq 0 ]
  run _run_install
  [ "$status" -eq 0 ]
  [ -z "$(find "$HOME" -name '*_bak')" ]
}
