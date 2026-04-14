#!/usr/bin/env bats
# Tests for config/bashrc

DOTFILES_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
BASHRC="$DOTFILES_DIR/config/bashrc"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"

  # Create dirs while system PATH is still intact
  mkdir -p "$HOME/.local/bin"
  mkdir -p "$HOME/.claude/hooks/peon-ping"
  mkdir -p "$TEST_DIR/bin"

  # mise: used twice (activate --shims and completion bash)
  cat > "$HOME/.local/bin/mise" << 'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$HOME/.local/bin/mise"

  # fzf --bash: sourced for key bindings
  cat > "$TEST_DIR/bin/fzf" << 'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$TEST_DIR/bin/fzf"

  # fzf-git.sh: sourced directly
  touch "$HOME/.local/bin/fzf-git.sh"

  # starship init bash: sourced for prompt
  cat > "$TEST_DIR/bin/starship" << 'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$TEST_DIR/bin/starship"

  # xcode-select: checked with 'which' before use; absent = bashrc skips it
  # brew: only evaluated if /opt/homebrew/bin/brew exists (it won't in tests)

  # MOCK_PATH is passed into test subshells only — never exported to this process,
  # so teardown retains access to system commands (rm, mkdir, etc.)
  MOCK_PATH="$TEST_DIR/bin:$HOME/.local/bin"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Count occurrences of a directory in a colon-separated PATH
_count_in_path() {
  local dir="$1"
  local path_str="$2"
  echo "$path_str" | tr ':' '\n' | grep -Fxc "$dir" || true
}

# --- PATH idempotency ---

@test "~/.local/bin appears exactly once after sourcing bashrc once" {
  path_result="$(bash --norc --noprofile -c "
    export HOME='$HOME'
    export PATH='$MOCK_PATH'
    source '$BASHRC' 2>/dev/null
    echo \"\$PATH\"
  ")"
  count="$(_count_in_path "$HOME/.local/bin" "$path_result")"
  [ "$count" -eq 1 ]
}

@test "~/.local/bin appears exactly once after sourcing bashrc twice" {
  path_result="$(bash --norc --noprofile -c "
    export HOME='$HOME'
    export PATH='$MOCK_PATH'
    source '$BASHRC' 2>/dev/null
    source '$BASHRC' 2>/dev/null
    echo \"\$PATH\"
  ")"
  count="$(_count_in_path "$HOME/.local/bin" "$path_result")"
  [ "$count" -eq 1 ]
}

@test "~/.local/bin appears exactly once when PATH already contains it before sourcing" {
  path_result="$(bash --norc --noprofile -c "
    export HOME='$HOME'
    export PATH='$HOME/.local/bin:$MOCK_PATH'
    source '$BASHRC' 2>/dev/null
    echo \"\$PATH\"
  ")"
  count="$(_count_in_path "$HOME/.local/bin" "$path_result")"
  [ "$count" -eq 1 ]
}
