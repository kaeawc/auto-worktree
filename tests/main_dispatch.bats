#!/usr/bin/env bats
# Tests for src/main.sh
#
# Coverage:
#   - auto-worktree command dispatch: each subcommand routes correctly
#   - Unknown command handling
#   - help/--help/-h flag
#   - Source-time loading: all modules load without error

load 'test_helper/common-setup'
load 'helpers/setup_git_repo'
load 'helpers/stub_gum'

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

setup() {
  _common_setup
  setup_git_repo
  setup_stub_gum

  # Override _aw_get_ai_tool_cmd to prevent global config leakage
  _aw_get_ai_tool_cmd() { echo ""; }
  export -f _aw_get_ai_tool_cmd

  # Source main.sh to get the auto-worktree function
  # shellcheck source=../src/main.sh
  source "${REPO_ROOT}/src/main.sh"
}

teardown() {
  teardown_stub_gum
  teardown_git_repo
}

# ============================================================================
# Source-time loading
# ============================================================================

@test "main.sh: all modules source without error" {
  # If we got here, source in setup() succeeded
  # Verify the auto-worktree function exists
  declare -f auto-worktree > /dev/null
}

@test "main.sh: auto-worktree function is defined" {
  run type -t auto-worktree
  assert_success
  assert_output "function"
}

@test "main.sh: aw wrapper function is defined" {
  run type -t aw
  assert_success
  assert_output "function"
}

# ============================================================================
# help command
# ============================================================================

@test "auto-worktree help: prints usage information" {
  run auto-worktree help
  assert_success
  assert_output --partial "Usage: auto-worktree"
  assert_output --partial "Commands:"
}

@test "auto-worktree --help: prints usage information" {
  run auto-worktree --help
  assert_success
  assert_output --partial "Usage: auto-worktree"
}

@test "auto-worktree -h: prints usage information" {
  run auto-worktree -h
  assert_success
  assert_output --partial "Usage: auto-worktree"
}

@test "auto-worktree help: lists all subcommands" {
  run auto-worktree help
  assert_success
  assert_output --partial "new"
  assert_output --partial "resume"
  assert_output --partial "issue"
  assert_output --partial "milestone"
  assert_output --partial "create"
  assert_output --partial "pr"
  assert_output --partial "list"
  assert_output --partial "cleanup"
  assert_output --partial "settings"
}

@test "auto-worktree help: includes safety warning" {
  run auto-worktree help
  assert_success
  assert_output --partial "SAFETY WARNING"
}

# ============================================================================
# Unknown command
# ============================================================================

@test "auto-worktree: unknown command returns 1 with error message" {
  run auto-worktree nonexistent_command
  assert_failure
  assert_output --partial "Unknown command: nonexistent_command"
  assert_output --partial "auto-worktree help"
}

# ============================================================================
# Command dispatch (verify routing by stubbing target functions)
# ============================================================================

@test "auto-worktree list: dispatches to _aw_list" {
  local called=false
  _aw_list() { called=true; echo "LIST_CALLED"; }
  export -f _aw_list

  run auto-worktree list
  assert_output --partial "LIST_CALLED"
}

@test "auto-worktree resume: dispatches to _aw_resume" {
  _aw_resume() { echo "RESUME_CALLED"; }
  export -f _aw_resume

  run auto-worktree resume
  assert_output --partial "RESUME_CALLED"
}

@test "auto-worktree cleanup: dispatches to _aw_cleanup_interactive" {
  _aw_cleanup_interactive() { echo "CLEANUP_CALLED"; }
  export -f _aw_cleanup_interactive

  run auto-worktree cleanup
  assert_output --partial "CLEANUP_CALLED"
}

@test "auto-worktree new: dispatches to _aw_new" {
  _aw_new() { echo "NEW_CALLED"; }
  export -f _aw_new

  run auto-worktree new
  assert_output --partial "NEW_CALLED"
}

@test "auto-worktree settings: dispatches to _aw_settings_menu" {
  _aw_settings_menu() { echo "SETTINGS_CALLED"; }
  export -f _aw_settings_menu

  run auto-worktree settings
  assert_output --partial "SETTINGS_CALLED"
}
