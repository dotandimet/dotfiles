#!/usr/bin/env bats
# Tests for bin/project-picker. Uses real jq; terminal backends, fd, and fzf are mocked.

DOTFILES_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$DOTFILES_DIR/bin/project-picker"

setup() {
  TEST_DIR="$(mktemp -d)"
  export PATH="$TEST_DIR/bin:$PATH"
  export PROJECTS="$TEST_DIR/projects"
  export CALLS="$TEST_DIR/herdr.jsonl"
  export PICKER_OUTPUT=""
  export PICKER_STATUS=0
  export FD_STATUS=0
  export HERDR_STATUS=0
  export PROJECT_PICKER_BACKEND=auto
  unset TMUX HC_TERMINAL_ID HERDR_APP_RESPONSE HERDR_APP_FAIL_COMMAND
  export HERDR_ENV=1
  mkdir -p "$TEST_DIR/bin" "$PROJECTS/existing" "$PROJECTS/second"
  : >"$CALLS"

  cat >"$TEST_DIR/bin/fd" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' existing second
exit "$FD_STATUS"
EOF

  cat >"$TEST_DIR/bin/fzf" <<'EOF'
#!/usr/bin/env bash
# Drain the pipe so the producer cannot fail with SIGPIPE.
cat > /dev/null
printf '%s' "$PICKER_OUTPUT"
exit "$PICKER_STATUS"
EOF

  cat >"$TEST_DIR/bin/herdr" <<'EOF'
#!/usr/bin/env bash
jq -cn --args '$ARGS.positional' -- "$@" >> "$CALLS"
if [[ "$HERDR_STATUS" -ne 0 ]]; then
  exit "$HERDR_STATUS"
fi
printf '%s\n' '{"result":{"workspace":{"workspace_id":"workspace"},"tab":{"tab_id":"tab"},"root_pane":{"pane_id":"pane"}}}'
EOF

  cat >"$TEST_DIR/bin/herdr-app" <<'EOF'
#!/usr/bin/env bash
jq -cn --args '$ARGS.positional' -- "$@" >> "$CALLS"
if [[ "${HERDR_APP_FAIL_COMMAND:-}" == "$2" ]]; then
  exit 4
fi
if [[ -n "${HERDR_APP_RESPONSE:-}" ]]; then
  printf '%s\n' "$HERDR_APP_RESPONSE"
else
  count=$(jq -s 'map(select(.[1] == "space.new")) | length' "$CALLS")
  jq -cn --arg count "$count" '{space: ("space-" + $count), tab: ("pi-" + $count)}'
fi
EOF

  cat >"$TEST_DIR/bin/tmux" <<'EOF'
#!/usr/bin/env bash
jq -cn --args '$ARGS.positional' -- "$@" >> "$CALLS"
if [[ "$1" == has-session ]]; then
  exit "${TMUX_HAS_SESSION_STATUS:-1}"
fi
exit "${TMUX_STATUS:-0}"
EOF

  unset TMUX_HAS_SESSION_STATUS TMUX_STATUS
  chmod +x "$TEST_DIR/bin/"*
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Source without running main, then exercise one function in Bats' subshell.
_run_function() {
  source "$SCRIPT"
  "$@"
}

# Check workspace arguments, directory contents, and the final focus call.
assert_projects() {
  local project expected_names actual_names expected_dirs actual_dirs
  expected_names="$(printf '%s\n' "$@")"
  actual_names="$(jq -r 'select(.[0:2] == ["workspace", "create"]) | .[-1]' "$CALLS")"
  [ "$actual_names" = "$expected_names" ]

  for project in "$@"; do
    [ -d "$PROJECTS/$project" ]
    jq -se --arg dir "$PROJECTS/$project" --arg label "$project" \
      'map(select(. == ["workspace", "create", "--cwd", $dir, "--label", $label])) | length == 1' \
      "$CALLS" >/dev/null
  done

  expected_dirs="$(printf '%s\n' existing second "$@" | sort -u)"
  actual_dirs="$(find "$PROJECTS" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)"
  [ "$actual_dirs" = "$expected_dirs" ]
  jq -se '.[-1] == ["tab", "focus", "tab"]' "$CALLS" >/dev/null
}

assert_no_changes() {
  [ ! -s "$CALLS" ]
  [ "$(find "$PROJECTS" -mindepth 1 -maxdepth 1 -exec basename {} \; | sort)" = $'existing\nsecond' ]
}

# --- function-level tests ---

@test "sourcing the script does not run main or create the projects root" {
  export PROJECTS="$TEST_DIR/not-created"
  run _run_function declare -F main
  [ "$status" -eq 0 ]
  [ "$output" = main ]
  [ ! -e "$PROJECTS" ]
  [ ! -s "$CALLS" ]
}

@test "create_project creates a directory without opening a workspace" {
  run _run_function create_project "new project"
  [ "$status" -eq 0 ]
  [ -d "$PROJECTS/new project" ]
  [ ! -s "$CALLS" ]
}

@test "create_project rejects invalid directory names" {
  local name
  for name in "" . .. ../outside nested/project; do
    run _run_function create_project "$name"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Project name must be a single directory name"* ]]
  done
  [ ! -e "$TEST_DIR/outside" ]
  assert_no_changes
}

@test "pick_projects returns selected names without invoking Herdr" {
  export PICKER_OUTPUT=$'search\nexisting\nsecond\n'
  run _run_function pick_projects search
  [ "$status" -eq 0 ]
  [ "$output" = $'existing\nsecond' ]
  assert_no_changes
}

@test "pick_projects creates and returns an unmatched project without invoking Herdr" {
  export PICKER_OUTPUT=$'new project\n'
  export PICKER_STATUS=1
  run _run_function pick_projects <<< yes
  [ "$status" -eq 0 ]
  [[ "$output" == *'Create project "new project"? [y/N]'* ]]
  [[ "$output" == *"new project" ]]
  [ -d "$PROJECTS/new project" ]
  [ ! -s "$CALLS" ]
}

@test "pick_projects propagates listing errors without creating a project" {
  export FD_STATUS=3
  export PICKER_OUTPUT=$'new project\n'
  export PICKER_STATUS=1
  run _run_function pick_projects
  [ "$status" -eq 3 ]
  assert_no_changes
}

@test "create_command_tab creates and launches a command in the returned pane" {
  run _run_function create_command_tab workspace "$PROJECTS/existing" nvim
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  jq -se --arg dir "$PROJECTS/existing" '. == [
    ["tab", "create", "--workspace", "workspace", "--cwd", $dir, "--label", "nvim"],
    ["pane", "run", "pane", "nvim"]
  ]' "$CALLS" >/dev/null
}

@test "create_project_workspace sets up all three tabs and returns the pi tab ID" {
  run _run_function create_project_workspace existing
  [ "$status" -eq 0 ]
  [ "$output" = tab ]
  jq -se --arg dir "$PROJECTS/existing" '. == [
    ["workspace", "create", "--cwd", $dir, "--label", "existing"],
    ["tab", "rename", "tab", "pi"],
    ["pane", "run", "pane", "pi --continue"],
    ["tab", "create", "--workspace", "workspace", "--cwd", $dir, "--label", "nvim"],
    ["pane", "run", "pane", "nvim"],
    ["tab", "create", "--workspace", "workspace", "--cwd", $dir, "--label", "bash"],
    ["pane", "run", "pane", "bash"]
  ]' "$CALLS" >/dev/null
}

@test "open_projects does nothing for an empty selection" {
  run _run_function open_projects ""
  [ "$status" -eq 0 ]
  assert_no_changes
}

_open_projects_with_distinct_tabs() {
  source "$SCRIPT"
  create_project_workspace() {
    printf '%s-pi-tab\n' "$1"
  }
  open_projects $'existing\nsecond'
}

@test "open_projects focuses the first project's pi tab" {
  run _open_projects_with_distinct_tabs
  [ "$status" -eq 0 ]
  jq -se '. == [["tab", "focus", "existing-pi-tab"]]' "$CALLS" >/dev/null
}

@test "open_projects stops on workspace creation failure without focusing a tab" {
  export HERDR_STATUS=4
  run _run_function open_projects $'existing\nsecond'
  [ "$status" -eq 4 ]
  jq -se --arg dir "$PROJECTS/existing" '. == [
    ["workspace", "create", "--cwd", $dir, "--label", "existing"]
  ]' "$CALLS" >/dev/null
}

# --- end-to-end tests ---

@test "opens an existing selection without creating a directory for the query" {
  export PICKER_OUTPUT=$'ex\nexisting\n'
  run "$SCRIPT" ex
  [ "$status" -eq 0 ]
  assert_projects existing
}

@test "opens multiple selected projects" {
  export PICKER_OUTPUT=$'\nexisting\nsecond\n'
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  assert_projects existing second
}

@test "creates a project from an unmatched query containing spaces" {
  export PICKER_OUTPUT=$'new project\n'
  export PICKER_STATUS=1
  run "$SCRIPT" <<< yes
  [ "$status" -eq 0 ]
  assert_projects "new project"
}

@test "does nothing for an empty unmatched query" {
  export PICKER_OUTPUT=$'\n'
  export PICKER_STATUS=1
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  assert_no_changes
}

@test "preserves cancellation without creating a project" {
  export PICKER_OUTPUT=$'cancelled\n'
  export PICKER_STATUS=130
  run "$SCRIPT"
  [ "$status" -eq 130 ]
  assert_no_changes
}

@test "rejects an unmatched query containing a slash" {
  export PICKER_OUTPUT=$'../outside\n'
  export PICKER_STATUS=1
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Project name must be a single directory name"* ]]
  [ ! -e "$TEST_DIR/outside" ]
  assert_no_changes
}

@test "rejects a dot as the new project name" {
  export PICKER_OUTPUT=$'.\n'
  export PICKER_STATUS=1
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Project name must be a single directory name"* ]]
  assert_no_changes
}

@test "propagates picker errors without creating a project" {
  export PICKER_OUTPUT=$'failed\n'
  export PICKER_STATUS=2
  run "$SCRIPT"
  [ "$status" -eq 2 ]
  assert_no_changes
}

# --- desktop app / core backend ---

@test "core terminals automatically open a desktop space with pi, nvim, and bash" {
  unset HERDR_ENV
  export HC_TERMINAL_ID=t7
  export PICKER_OUTPUT=$'\nexisting\n'
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  jq -se --arg dir "$PROJECTS/existing" 'map([.[0], .[1], (.[2] | fromjson)]) == [
    ["do", "space.new", {name: "existing", folder: $dir, tab: "pi", argv: ["pi", "--continue"]}],
    ["do", "tab.new", {space: "space-1", folder: $dir, name: "nvim", argv: ["nvim"]}],
    ["do", "tab.new", {space: "space-1", folder: $dir, name: "bash", argv: ["bash"]}],
    ["do", "tab.select", {id: "pi-1"}]
  ]' "$CALLS" >/dev/null
}

@test "desktop workspace creation returns only the pi tab ID" {
  export PROJECT_PICKER_BACKEND=herdr-app
  run _run_function create_project_workspace existing
  [ "$status" -eq 0 ]
  [ "$output" = pi-1 ]
}

@test "desktop multi-selection targets each space and focuses the first pi tab" {
  export PROJECT_PICKER_BACKEND=herdr-app
  export PICKER_OUTPUT=$'\nexisting\nsecond\n'
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  jq -se 'map([.[1], (.[2] | fromjson)]) |
    map(select(.[0] == "tab.new") | .[1].space) == ["space-1", "space-1", "space-2", "space-2"]' \
    "$CALLS" >/dev/null
  jq -se '.[-1][1] == "tab.select" and (.[-1][2] | fromjson) == {id: "pi-1"}' "$CALLS" >/dev/null
}

@test "desktop backend creates unmatched project names with spaces and quotes" {
  export PROJECT_PICKER_BACKEND=herdr-app
  local name='new "project"'
  export PICKER_OUTPUT="$name" PICKER_STATUS=1
  run "$SCRIPT" <<< yes
  [ "$status" -eq 0 ]
  [ -d "$PROJECTS/$name" ]
  jq -se --arg name "$name" --arg dir "$PROJECTS/$name" \
    '(.[0][2] | fromjson) == {name: $name, folder: $dir, tab: "pi", argv: ["pi", "--continue"]}' \
    "$CALLS" >/dev/null
}

@test "TUI environment takes precedence over inherited core identity" {
  export HERDR_ENV=1 HC_TERMINAL_ID=t7
  export PICKER_OUTPUT=$'\nexisting\n'
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  assert_projects existing
}

@test "explicit backend overrides automatic detection" {
  export PROJECT_PICKER_BACKEND=herdr HC_TERMINAL_ID=t7
  export PICKER_OUTPUT=$'\nexisting\n'
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  assert_projects existing

  : >"$CALLS"
  export PROJECT_PICKER_BACKEND=herdr-app HERDR_ENV=1
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  jq -se '.[0][1] == "space.new"' "$CALLS" >/dev/null
}

@test "invalid backend fails before creating a project" {
  export PROJECT_PICKER_BACKEND=unknown
  export PICKER_OUTPUT=new PICKER_STATUS=1
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PROJECT_PICKER_BACKEND must be"* ]]
  assert_no_changes
}

@test "desktop cancellation and empty selection do not touch the app" {
  unset HERDR_ENV
  export HC_TERMINAL_ID=t7
  export PICKER_OUTPUT=$'cancelled\n' PICKER_STATUS=130
  run "$SCRIPT"
  [ "$status" -eq 130 ]
  assert_no_changes

  export PICKER_OUTPUT=$'\n' PICKER_STATUS=1
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  assert_no_changes
}

@test "desktop errors stop setup without opening more projects or focusing" {
  export PROJECT_PICKER_BACKEND=herdr-app
  local command expected_calls
  for command in space.new tab.new; do
    : >"$CALLS"
    export HERDR_APP_FAIL_COMMAND="$command"
    run _run_function open_projects $'existing\nsecond'
    [ "$status" -eq 4 ]
    expected_calls=1
    [[ "$command" != tab.new ]] || expected_calls=2
    jq -se --argjson count "$expected_calls" 'length == $count and all(.[]; .[1] != "tab.select")' \
      "$CALLS" >/dev/null
  done
}

@test "declining project creation leaves directories and backends untouched" {
  export PICKER_OUTPUT=new PICKER_STATUS=1
  run "$SCRIPT" <<< no
  [ "$status" -eq 0 ]
  [[ "$output" == *'Create project "new"? [y/N]'* ]]
  assert_no_changes
}

@test "EOF at the creation prompt does not create a project" {
  export PICKER_OUTPUT=new PICKER_STATUS=1
  run "$SCRIPT" </dev/null
  [ "$status" -eq 0 ]
  assert_no_changes
}

@test "plain terminals create three tmux windows and attach to pi" {
  unset HERDR_ENV
  export PICKER_OUTPUT=$'\nexisting\n'
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  jq -se --arg dir "$PROJECTS/existing" '. == [
    ["has-session", "-t", "=existing"],
    ["new-session", "-d", "-s", "existing", "-n", "pi", "-c", $dir, "bash"],
    ["send-keys", "-t", "=existing:pi", "pi --continue", "C-m"],
    ["new-window", "-t", "=existing:", "-n", "nvim", "-c", $dir, "bash"],
    ["send-keys", "-t", "=existing:nvim", "nvim", "C-m"],
    ["new-window", "-t", "=existing:", "-n", "bash", "-c", $dir, "bash"],
    ["select-window", "-t", "=existing:pi"],
    ["attach-session", "-t", "=existing:pi"]
  ]' "$CALLS" >/dev/null
}

@test "project-session delegates to the picker and switches existing tmux sessions" {
  export PROJECT_PICKER_BACKEND=tmux TMUX=test TMUX_HAS_SESSION_STATUS=0
  export PICKER_OUTPUT=$'ex\nexisting\n'
  run "$DOTFILES_DIR/bin/project-session" ex
  [ "$status" -eq 0 ]
  jq -se '. == [
    ["has-session", "-t", "=existing"],
    ["select-window", "-t", "=existing:pi"],
    ["switch-client", "-t", "=existing:pi"]
  ]' "$CALLS" >/dev/null
}

@test "tmux creates confirmed new projects with sanitized session names" {
  export PROJECT_PICKER_BACKEND=tmux PICKER_OUTPUT='new.project: one' PICKER_STATUS=1
  run "$SCRIPT" <<< yes
  [ "$status" -eq 0 ]
  [ -d "$PROJECTS/new.project: one" ]
  jq -se --arg dir "$PROJECTS/new.project: one" '
    .[1] == ["new-session", "-d", "-s", "new_project_ one", "-n", "pi", "-c", $dir, "bash"]
    and .[-1] == ["attach-session", "-t", "=new_project_ one:pi"]' "$CALLS" >/dev/null
}

@test "tmux multi-selection creates both sessions and focuses the first" {
  export PROJECT_PICKER_BACKEND=tmux PICKER_OUTPUT=$'\nexisting\nsecond\n'
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  jq -se 'map(select(.[0] == "new-session") | .[3]) == ["existing", "second"]
    and .[-1] == ["attach-session", "-t", "=existing:pi"]' "$CALLS" >/dev/null
}

@test "tmux creation failure stops without attaching" {
  export PROJECT_PICKER_BACKEND=tmux TMUX_STATUS=4 PICKER_OUTPUT=$'\nexisting\n'
  run "$SCRIPT"
  [ "$status" -eq 4 ]
  jq -se 'length == 2 and .[-1][0] == "new-session"' "$CALLS" >/dev/null
}

@test "desktop setup rejects missing or invalid space and tab IDs" {
  export PROJECT_PICKER_BACKEND=herdr-app
  local response
  for response in '{}' '{"space":"s1"}' '{"space":null,"tab":"t1"}' '{"space":"s1","tab":""}' 'invalid'; do
    : >"$CALLS"
    export HERDR_APP_RESPONSE="$response"
    run _run_function create_project_workspace existing
    [ "$status" -ne 0 ]
    jq -se 'length == 1 and .[0][1] == "space.new"' "$CALLS" >/dev/null
  done
}
