#!/usr/bin/env bats
# Tests for bin/git-dump

DOTFILES_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$DOTFILES_DIR/bin/git-dump"

setup() {
  TEST_DIR="$(mktemp -d)"
  export PATH="$TEST_DIR/bin:$PATH"
  mkdir -p "$TEST_DIR/bin"

  # Initialize a real git repo with commit history
  REPO_DIR="$TEST_DIR/repo"
  mkdir -p "$REPO_DIR"
  cd "$REPO_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"

  # First commit
  echo "version 1" > myfile.txt
  git add myfile.txt
  git commit -q -m "First commit"

  # Second commit
  echo "version 2" > myfile.txt
  git add myfile.txt
  git commit -q -m "Second commit"

  FIRST_SHA="$(git log --pretty=format:%h -- myfile.txt | tail -1)"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Helper: mock fzf to auto-select the first line
_mock_fzf_select_first() {
  cat > "$TEST_DIR/bin/fzf" << 'EOF'
#!/bin/bash
head -1
EOF
  chmod +x "$TEST_DIR/bin/fzf"
}

# Helper: mock fzf to simulate Esc (empty selection)
_mock_fzf_cancel() {
  cat > "$TEST_DIR/bin/fzf" << 'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x "$TEST_DIR/bin/fzf"
}

# --- argument validation ---

@test "exits 1 with usage message when no filename given" {
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

# --- normal operation ---

@test "creates output file with correct naming pattern" {
  cd "$REPO_DIR"
  _mock_fzf_select_first
  run "$SCRIPT" myfile.txt
  [ "$status" -eq 0 ]
  # Should have created myfile.txt.<sha>
  shopt -s nullglob
  files=(myfile.txt.*)
  [ "${#files[@]}" -eq 1 ]
}

@test "extracted file contains content from the selected commit" {
  cd "$REPO_DIR"
  _mock_fzf_select_first
  "$SCRIPT" myfile.txt
  shopt -s nullglob
  files=(myfile.txt.*)
  content="$(cat "${files[0]}")"
  # fzf selected the most recent commit (second), which has "version 2"
  [ "$content" = "version 2" ]
}

@test "prints confirmation message after extraction" {
  cd "$REPO_DIR"
  _mock_fzf_select_first
  run "$SCRIPT" myfile.txt
  [[ "$output" == *"Dumped version"* ]]
  [[ "$output" == *"myfile.txt"* ]]
}

# --- user cancels fzf ---

@test "exits 0 silently when user cancels fzf (no selection)" {
  cd "$REPO_DIR"
  _mock_fzf_cancel
  run "$SCRIPT" myfile.txt
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "does not create output file when fzf is cancelled" {
  cd "$REPO_DIR"
  _mock_fzf_cancel
  run "$SCRIPT" myfile.txt
  shopt -s nullglob
  files=(myfile.txt.*)
  [ "${#files[@]}" -eq 0 ]
}
