#!/usr/bin/env bats
# Exercise complete startup files with Apple's Bash, not Homebrew's Bash.
# Linux /bin/bash cannot establish macOS Bash 3.2 compatibility.

DOTFILES_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  [[ "$OSTYPE" == darwin* ]] || skip "requires macOS /bin/bash"
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home with spaces"
  mkdir -p "$TEST_HOME/.local/bin"
  cp "$DOTFILES_DIR/config/_bashrc" "$TEST_HOME/.bashrc"
  cp "$DOTFILES_DIR/config/_bash_profile" "$TEST_HOME/.bash_profile"
  printf 'FZF_GIT_LOADS=$(( ${FZF_GIT_LOADS:-0} + 1 ))\n' >"$TEST_HOME/.local/bin/fzf-git.sh"
}

teardown() {
  [[ -z "${TEST_DIR:-}" ]] || rm -rf "$TEST_DIR"
}

@test "macOS compatibility tests use Apple's Bash 3.2" {
  run /bin/bash --noprofile --norc -c '[[ ${BASH_VERSINFO[0]} == 3 && ${BASH_VERSINFO[1]} == 2 ]]'
  [ "$status" -eq 0 ]
}

@test "_bashrc parses with macOS /bin/bash" {
  run /bin/bash --noprofile --norc -n "$TEST_HOME/.bashrc"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_bash_profile parses with macOS /bin/bash" {
  run /bin/bash --noprofile --norc -n "$TEST_HOME/.bash_profile"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

_check_startup() {
  # Clear inherited shell hooks, activation state, and BASH_ENV. Functions mock
  # tools even if the Darwin PATH block prepends a real Homebrew installation.
  run env -i HOME="$TEST_HOME" PATH=/usr/bin:/bin LC_ALL=en_US.UTF-8 \
    /bin/bash --noprofile --norc -c '
      set -E
      trap '\''printf "Startup failed at line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2; exit 1'\'' ERR

      mise() {
        case "$*" in
          "activate bash") printf "MISE_ACTIVATED=1\n" ;;
          "completion bash") printf "MISE_COMPLETION_LOADED=1\n" ;;
          "bin-paths github:HalFrgrd/flyline") printf "%s\n" "$HOME/missing-flyline" ;;
          "bin-paths --bin-names github:HalFrgrd/flyline") printf "flyline.so\n" ;;
          *) return 1 ;;
        esac
      }
      fzf() { [[ "$*" == "--bash" ]] && printf "FZF_LOADED=1\n"; }
      starship() { [[ "$*" == "init bash" ]] && printf "STARSHIP_LOADED=1\n"; }
      # Skip host Xcode completions; they are not part of this repository.
      which() { return 1; }

      PATH="/compat/sentinel:/usr/bin:$HOME/.local/bin:/bin:$HOME/.local/bin"
      if [[ "$2" == array ]]; then
        PROMPT_COMMAND=(first_hook second_hook)
      else
        PROMPT_COMMAND=environment_prompt
      fi

      for iteration in 1 2; do
        source "$HOME/$1"
        [[ "$EDITOR" == nvim && "$NVIM_APPNAME" == lazyvim ]]
        [[ "$HISTFILE" == "$HOME/.all_history" ]]
        shopt -q histappend
        declare -F go_to_project >/dev/null
        alias lv >/dev/null
        [[ "$MISE_ACTIVATED" == 1 && "$MISE_COMPLETION_LOADED" == 1 ]]
        [[ "$FZF_LOADED" == 1 && "$STARSHIP_LOADED" == 1 ]]
        [[ "$FZF_GIT_LOADS" == "$iteration" ]]

        # Check preservation as well as deduplication: malformed substitution
        # can retain local/bin while destroying unrelated search directories.
        local_bin_count=0
        remaining="$PATH:"
        while [[ -n "$remaining" ]]; do
          entry="${remaining%%:*}"
          remaining="${remaining#*:}"
          case "$entry" in
            "$HOME/.local/bin") local_bin_count=$((local_bin_count + 1)) ;;
            /compat/sentinel|/usr/bin|/bin|/opt/homebrew/bin|/usr/local/bin|/Applications/Obsidian.app/Contents/MacOS) ;;
            *) printf "Unexpected PATH entry: %s\n" "$entry" >&2; exit 1 ;;
          esac
        done
        [[ "$local_bin_count" == 1 ]]
        for entry in /compat/sentinel /usr/bin /bin; do
          [[ ":$PATH:" == *":$entry:"* ]]
        done
        [[ "$(command -v env)" == /usr/bin/env ]]

        if [[ "$2" == array ]]; then
          [[ "${PROMPT_COMMAND[0]}" == first_hook ]]
          [[ "${PROMPT_COMMAND[1]}" == second_hook ]]
          [[ "${PROMPT_COMMAND[2]}" == "history -a" ]]
          [[ "${#PROMPT_COMMAND[@]}" == 3 ]]
        else
          [[ "$PROMPT_COMMAND" == "environment_prompt; history -a" ]]
        fi
      done
    ' bash "$1" "$2"
  if [[ "$status" -ne 0 || -n "$output" ]]; then
    printf '%s\n' "$output"
    return 1
  fi
}

@test "_bashrc sources twice on macOS Bash with a scalar prompt hook" {
  _check_startup .bashrc scalar
}

@test "_bashrc sources twice on macOS Bash with array prompt hooks" {
  _check_startup .bashrc array
}

@test "_bash_profile loads _bashrc twice on macOS Bash with a scalar prompt hook" {
  _check_startup .bash_profile scalar
}

@test "_bash_profile loads _bashrc twice on macOS Bash with array prompt hooks" {
  _check_startup .bash_profile array
}
