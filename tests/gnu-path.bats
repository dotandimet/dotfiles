#!/usr/bin/env bats
# Test the GNU PATH block with a fake Homebrew prefix, on Linux and macOS.

DOTFILES_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  TEST_DIR="$(mktemp -d)"
  PREFIX="$TEST_DIR/homebrew with spaces"
  GNU_SETUP="$(awk '/^# GNU tools use unprefixed names/,/^# End GNU tools PATH setup/' "$DOTFILES_DIR/config/_bashrc")"
  local real_prefix=/opt/homebrew
  GNU_SETUP="${GNU_SETUP//"$real_prefix"/$PREFIX}"
  local package command
  for package in coreutils findutils gnu-sed gnu-tar gawk grep make; do
    case "$package" in
      coreutils) command="ls" ;;
      findutils) command="find" ;;
      gnu-sed) command="sed" ;;
      gnu-tar) command="tar" ;;
      gawk) command="awk" ;;
      *) command="$package" ;;
    esac
    mkdir -p "$PREFIX/opt/$package/libexec/gnubin"
    printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$package" >"$PREFIX/opt/$package/libexec/gnubin/$command"
    chmod +x "$PREFIX/opt/$package/libexec/gnubin/$command"
  done
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "GNU commands take precedence without duplicates on system and current Bash" {
  local shell
  for shell in /bin/bash bash; do
    run "$shell" --noprofile --norc -c '
      OSTYPE=darwin
      PATH=/usr/bin:/bin
      eval "$1"
      first_path="$PATH"
      for pair in coreutils:ls findutils:find gnu-sed:sed gnu-tar:tar gawk:awk grep:grep make:make; do
        package="${pair%%:*}"
        command="${pair#*:}"
        [[ "$(command -v "$command")" == "$2/opt/$package/libexec/gnubin/$command" ]] || exit 1
        [[ "$("$command")" == "$package" ]] || exit 1
      done
      # A later tool prepending its own path must not cause repeated additions.
      PATH="/another/tool/bin:$PATH"
      eval "$1"
      [[ "$PATH" == "/another/tool/bin:$first_path" ]] || exit 1
      [[ "$PATH" == *:/usr/bin:/bin ]] || exit 1
      [[ -z ${_gnu_package+x} && -z ${_gnu_bin+x} ]]
    ' bash "$GNU_SETUP" "$PREFIX"
    [ "$status" -eq 0 ]
  done
}

@test "GNU PATH setup skips missing packages" {
  rm -rf "$PREFIX/opt/gnu-sed" "$PREFIX/opt/make"
  local shell
  for shell in /bin/bash bash; do
    run "$shell" --noprofile --norc -c '
      OSTYPE=darwin
      PATH=/usr/bin:/bin
      eval "$1"
      [[ "$(command -v awk)" == "$2/opt/gawk/libexec/gnubin/awk" ]] || exit 1
      [[ ":$PATH:" != *":$2/opt/gnu-sed/libexec/gnubin:"* ]] || exit 1
      [[ ":$PATH:" != *":$2/opt/make/libexec/gnubin:"* ]] || exit 1
      [[ "$PATH" == *:/usr/bin:/bin ]]
    ' bash "$GNU_SETUP" "$PREFIX"
    [ "$status" -eq 0 ]
  done
}

@test "GNU PATH setup leaves Linux unchanged even when package directories exist" {
  local shell
  for shell in /bin/bash bash; do
    run "$shell" --noprofile --norc -c '
      OSTYPE=linux-gnu
      PATH=/usr/bin:/bin
      eval "$1"
      [[ "$PATH" == /usr/bin:/bin ]]
    ' bash "$GNU_SETUP"
    [ "$status" -eq 0 ]
  done
}

@test "GNU tools have macOS-only bootstrap package declarations" {
  local package
  for package in coreutils findutils gnu-sed gnu-tar gawk grep make; do
    grep -Fx "\"brew:$package\" = { os = \"macos\" }" "$DOTFILES_DIR/mise/conf.d/dotfiles-macos.toml"
  done
}
