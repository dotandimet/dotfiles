#!/usr/bin/env bats
# Tests for bin/new-project
#
# Uses the real mise and jq installed on the system (both are assumed
# dependencies of this dotfiles repo). HOME is isolated so no real
# state is modified.

DOTFILES_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$DOTFILES_DIR/bin/new-project"

setup() {
  TEST_DIR="$(mktemp -d)"

  # Isolate HOME so the real ~/.pi/agent/trust.json is never touched.
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME"

  export PROJECTS="$TEST_DIR/projects"
  mkdir -p "$PROJECTS"
}

teardown() {
  rm -rf "$TEST_DIR"
}

TRUST_FILE_REL=".pi/agent/trust.json"

# --- argument validation ---

@test "exits non-zero on empty/whitespace name" {
  run "$SCRIPT" "   "
  [ "$status" -ne 0 ]
  [[ "$output" == *"no project name given"* ]]
}

@test "rejects name containing a slash" {
  run "$SCRIPT" "foo/bar"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid project name"* ]]
}

@test "rejects name starting with a dot" {
  run "$SCRIPT" ".hidden"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid project name"* ]]
}

@test "exits non-zero when the project directory already exists" {
  mkdir -p "$PROJECTS/already"
  run "$SCRIPT" already
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}

# --- directory creation ---

@test "creates the project directory under PROJECTS" {
  run "$SCRIPT" demoproj
  [ "$status" -eq 0 ]
  [ -d "$PROJECTS/demoproj" ]
}

@test "prints the created project path on stdout (last line)" {
  run "$SCRIPT" pathproj
  [ "$status" -eq 0 ]
  last_line="$(printf '%s\n' "$output" | tail -1)"
  [ "$last_line" = "$PROJECTS/pathproj" ]
}

@test "strips surrounding whitespace from the name" {
  run "$SCRIPT" "  spaced  "
  [ "$status" -eq 0 ]
  [ -d "$PROJECTS/spaced" ]
}

# --- prompting ---

@test "prompts for a name when no argument is given (reads from stdin)" {
  run bash -c "printf 'pipedname\n' | '$SCRIPT'"
  [ "$status" -eq 0 ]
  [ -d "$PROJECTS/pipedname" ]
}

# --- mise trust ---

@test "runs mise trust on the project directory" {
  run "$SCRIPT" miseproj
  [ "$status" -eq 0 ]
  [ -d "$PROJECTS/miseproj" ]
}

# --- pi trust ---

@test "creates trust.json and adds the project path set to true" {
  run "$SCRIPT" trustproj
  [ "$status" -eq 0 ]
  [ -f "$HOME/$TRUST_FILE_REL" ]
  val="$(jq -r --arg d "$PROJECTS/trustproj" '.[$d]' "$HOME/$TRUST_FILE_REL")"
  [ "$val" = "true" ]
}

@test "preserves existing trust.json entries" {
  mkdir -p "$HOME/.pi/agent"
  printf '{"/existing/path": true}\n' > "$HOME/$TRUST_FILE_REL"
  run "$SCRIPT" mergeproj
  [ "$status" -eq 0 ]
  old="$(jq -r '."/existing/path"' "$HOME/$TRUST_FILE_REL")"
  new="$(jq -r --arg d "$PROJECTS/mergeproj" '.[$d]' "$HOME/$TRUST_FILE_REL")"
  [ "$old" = "true" ]
  [ "$new" = "true" ]
}