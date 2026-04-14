#!/usr/bin/env bats
# Tests for bin/check-keyboard-layout

DOTFILES_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$DOTFILES_DIR/bin/check-keyboard-layout"

setup() {
  TEST_DIR="$(mktemp -d)"
  export PATH="$TEST_DIR/bin:$PATH"
  mkdir -p "$TEST_DIR/bin"

  # Mock HOME so the script reads our fake plist path
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME/Library/Preferences"

  # Default mock: returns English layout
  _mock_defaults "com.apple.keylayout.ABC"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Helper: write a defaults mock that returns the given layout ID
_mock_defaults() {
  local layout_id="$1"
  cat > "$TEST_DIR/bin/defaults" << EOF
#!/bin/bash
echo "$layout_id"
exit 0
EOF
  chmod +x "$TEST_DIR/bin/defaults"
}

# --- English layouts: silent, exit 0 ---

@test "ABC layout exits 0 with no output" {
  _mock_defaults "com.apple.keylayout.ABC"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "US layout exits 0 with no output" {
  _mock_defaults "com.apple.keylayout.US"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "British layout exits 0 with no output" {
  _mock_defaults "com.apple.keylayout.British"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "USExtended layout exits 0 with no output" {
  _mock_defaults "com.apple.keylayout.USExtended"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- Non-English layouts: warn, exit 1 ---

@test "Hebrew layout exits 1" {
  _mock_defaults "com.apple.keylayout.Hebrew"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "Hebrew layout shows Hebrew text in output" {
  _mock_defaults "com.apple.keylayout.Hebrew"
  run "$SCRIPT"
  [[ "$output" == *"תירבע"* ]]
}

@test "Hebrew layout shows keyboard icon in output" {
  _mock_defaults "com.apple.keylayout.Hebrew"
  run "$SCRIPT"
  [[ "$output" == *"⌨"* ]]
}

@test "unknown layout exits 1" {
  _mock_defaults "com.apple.keylayout.French"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "unknown layout shows layout name and keyboard icon" {
  _mock_defaults "com.apple.keylayout.French"
  run "$SCRIPT"
  [[ "$output" == *"⌨"* ]]
  [[ "$output" == *"French"* ]]
}

# --- --tmux mode ---

@test "--tmux flag with English layout exits 0 with no output" {
  _mock_defaults "com.apple.keylayout.ABC"
  run "$SCRIPT" --tmux
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "--tmux flag with Hebrew layout includes tmux color codes" {
  _mock_defaults "com.apple.keylayout.Hebrew"
  run "$SCRIPT" --tmux
  [ "$status" -eq 1 ]
  [[ "$output" == *"#[fg=#ffc777]"* ]]
}

@test "--tmux flag with non-English layout includes #[default] reset" {
  _mock_defaults "com.apple.keylayout.French"
  run "$SCRIPT" --tmux
  [[ "$output" == *"#[default]"* ]]
}

# --- defaults command unavailable ---

@test "exits non-zero when defaults command is not found" {
  # Remove the mock so defaults is absent
  rm "$TEST_DIR/bin/defaults"
  # The script reads layout at startup; with no defaults it gets empty string
  # which is non-English, so should exit 1
  run "$SCRIPT"
  [ "$status" -ne 0 ]
}
