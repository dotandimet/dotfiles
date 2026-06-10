#!/usr/bin/env bats
# Tests for install.sh symlink behavior

DOTFILES_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  mkdir -p "$HOME"

  # Fake config source dir with sample files
  TEST_CONF_DIR="$TEST_DIR/config"
  mkdir -p "$TEST_CONF_DIR"
  touch "$TEST_CONF_DIR/bashrc"
  touch "$TEST_CONF_DIR/bash_profile"
  touch "$TEST_CONF_DIR/inputrc"
  mkdir -p "$TEST_CONF_DIR/nvim"
  touch "$TEST_CONF_DIR/nvim/init.lua"

}

teardown() {
  rm -rf "$TEST_DIR"
}

# Source install.sh without running it, then invoke only the symlink logic.
# This avoids exercising the software-installation step (curl/mise/brew),
# which is covered separately by tests/docker_test_mac.sh.
_run_install() {
  # shellcheck source=/dev/null
  source "$DOTFILES_DIR/install.sh"
  install_links "$TEST_CONF_DIR"
}

# --- dot-file symlinks (bashrc, bash_profile, inputrc) ---

@test "bashrc is symlinked to ~/.bashrc" {
  run _run_install
  [ "$status" -eq 0 ]
  [ -L "$HOME/.bashrc" ]
  [ "$(readlink "$HOME/.bashrc")" = "$TEST_CONF_DIR/bashrc" ]
}

@test "bash_profile is symlinked to ~/.bash_profile" {
  run _run_install
  [ "$status" -eq 0 ]
  [ -L "$HOME/.bash_profile" ]
  [ "$(readlink "$HOME/.bash_profile")" = "$TEST_CONF_DIR/bash_profile" ]
}

@test "inputrc is symlinked to ~/.inputrc" {
  run _run_install
  [ "$status" -eq 0 ]
  [ -L "$HOME/.inputrc" ]
  [ "$(readlink "$HOME/.inputrc")" = "$TEST_CONF_DIR/inputrc" ]
}

# --- XDG config symlinks ---

@test "nvim config directory is symlinked to ~/.config/nvim" {
  run _run_install
  [ "$status" -eq 0 ]
  [ -L "$HOME/.config/nvim" ]
  [ "$(readlink "$HOME/.config/nvim")" = "$TEST_CONF_DIR/nvim" ]
}

@test "~/.config directory is created if it does not exist" {
  rm -rf "$HOME/.config"
  run _run_install
  [ "$status" -eq 0 ]
  [ -d "$HOME/.config" ]
}

# --- script symlinks ---

@test "scripts from bin/ are symlinked into ~/.local/bin/" {
  run _run_install
  [ "$status" -eq 0 ]
  for script in "$DOTFILES_DIR"/bin/*; do
    name="$(basename "$script")"
    [ -L "$HOME/.local/bin/$name" ]
    [ "$(readlink "$HOME/.local/bin/$name")" = "$script" ]
  done
}

@test "~/.local/bin is created if it does not exist" {
  rm -rf "$HOME/.local/bin"
  run _run_install
  printf "Output:\n%s\n${output}\n"
  tree "$HOME/.local/bin"
  [ "$status" -eq 0 ]
  [ -d "$HOME/.local/bin" ]
}

# --- backup behavior ---

@test "existing regular file is backed up with _bak suffix" {
  echo "original content" >"$HOME/.bashrc"
  run _run_install
  [ "$status" -eq 0 ]
  [ -L "$HOME/.bashrc" ]
  [ -f "$HOME/.bashrc_bak" ]
}

@test "wrong symlink is replaced and backed up" {
  ln -s /dev/null "$HOME/.bashrc"
  run _run_install
  [ "$status" -eq 0 ]
  [ -L "$HOME/.bashrc" ]
  [ "$(readlink "$HOME/.bashrc")" = "$TEST_CONF_DIR/bashrc" ]
  [ -L "$HOME/.bashrc_bak" ]
}

# --- idempotency ---

@test "running install twice does not error" {
  run _run_install
  [ "$status" -eq 0 ]
  run _run_install
  [ "$status" -eq 0 ]
}

@test "running install twice does not create extra _bak files" {
  run _run_install
  run _run_install
  [ "$status" -eq 0 ]
  # No _bak files should exist after a clean double-run
  bak_count=$(find "$HOME" -name '*_bak' | wc -l)
  [ "$bak_count" -eq 0 ]
}
