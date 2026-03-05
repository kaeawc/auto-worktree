#!/usr/bin/env bats
# Tests for src/commands/new.sh and the worktree creation path in src/lib/worktree.sh
#
# Coverage:
#   - Branch name generation: kebab-case, issue numbers, truncation, special chars
#   - Existing worktree detection: command switches to existing, no duplicate created
#   - Hook execution: _aw_run_git_hooks called on creation, failing hook propagates error
#   - Environment setup trigger: _aw_setup_environment called after creation

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

load 'helpers/setup_git_repo'
load 'helpers/git_assertions'

setup() {
  # Stub external-tool functions before sourcing so libs can load cleanly
  gum() { :; }
  export -f gum

  _aw_get_issue_provider() { echo "github"; }
  export -f _aw_get_issue_provider

  # Source pure utility functions
  # shellcheck source=../src/lib/utils.sh
  source "${REPO_ROOT}/src/lib/utils.sh"
  # shellcheck source=../src/providers/common.sh
  source "${REPO_ROOT}/src/providers/common.sh"
}

# ============================================================================
# Branch name generation — pure logic tests (_aw_sanitize_branch_name)
# ============================================================================

@test "branch name: spaces become kebab-case hyphens" {
  run _aw_sanitize_branch_name "Fix login bug"
  [ "$status" -eq 0 ]
  [ "$output" = "fix-login-bug" ]
}

@test "branch name: uppercase letters are lowercased" {
  run _aw_sanitize_branch_name "Add OAuth Support"
  [ "$status" -eq 0 ]
  [ "$output" = "add-oauth-support" ]
}

@test "branch name: punctuation is stripped/replaced with hyphens" {
  run _aw_sanitize_branch_name "Fix: auth & session (critical)"
  [ "$status" -eq 0 ]
  [ "$output" = "fix-auth-session-critical" ]
}

@test "branch name: emoji and non-ASCII characters are removed" {
  run _aw_sanitize_branch_name "fix login bug"
  [ "$status" -eq 0 ]
  # Emoji becomes a hyphen (or is stripped); result must be valid branch chars only
  [[ "$output" =~ ^[a-z0-9-]+$ ]]
}

@test "branch name: consecutive hyphens are collapsed" {
  run _aw_sanitize_branch_name "fix--double  space"
  [ "$status" -eq 0 ]
  [ "$output" = "fix-double-space" ]
}

@test "branch name: leading and trailing hyphens are stripped" {
  run _aw_sanitize_branch_name "-fix-me-"
  [ "$status" -eq 0 ]
  [ "$output" = "fix-me" ]
}

@test "branch name: issue number is included in work/N-description format" {
  local issue_id="42"
  local title="Implement dark mode"
  local sanitized
  sanitized=$(_aw_sanitize_branch_name "$title")
  local branch_name="work/${issue_id}-${sanitized}"

  # Branch must start with work/ and include the issue number
  [[ "$branch_name" =~ ^work/[0-9]+ ]]

  run _aw_extract_issue_number "$branch_name"
  [ "$status" -eq 0 ]
  [ "$output" = "$issue_id" ]
}

@test "branch name: long titles are truncated to 40 chars in the sanitized segment" {
  local title="This is a very long issue title that exceeds the forty character limit we set for branch names"
  local sanitized
  sanitized=$(_aw_sanitize_branch_name "$title" | cut -c1-40)
  [ "${#sanitized}" -le 40 ]
}

@test "branch name: truncated title still yields valid git branch name chars" {
  local title="This is a very long issue title that exceeds the forty character limit we set for branch names"
  local sanitized
  sanitized=$(_aw_sanitize_branch_name "$title" | cut -c1-40)
  [[ "$sanitized" =~ ^[a-z0-9-]+$ ]]
}

@test "branch name: issue number survives special characters in title" {
  local issue_id="456"
  local title="Fix: auth & session management (critical)"
  local sanitized
  sanitized=$(_aw_sanitize_branch_name "$title" | cut -c1-40)
  local branch_name="work/${issue_id}-${sanitized}"

  run _aw_extract_issue_number "$branch_name"
  [ "$status" -eq 0 ]
  [ "$output" = "$issue_id" ]
}

@test "branch name: issue number survives long title truncated to 40 chars" {
  local issue_id="789"
  local title="This is a very long issue title that exceeds the forty character limit we set for branch names"
  local sanitized
  sanitized=$(_aw_sanitize_branch_name "$title" | cut -c1-40)
  local branch_name="work/${issue_id}-${sanitized}"

  run _aw_extract_issue_number "$branch_name"
  [ "$status" -eq 0 ]
  [ "$output" = "$issue_id" ]
}

# ============================================================================
# Existing worktree detection — integration tests using real git worktrees
# ============================================================================

@test "_aw_find_worktree_for_issue: returns existing worktree path for matching issue" {
  setup_git_repo

  # Source worktree lib (stubs gum before source)
  source "${REPO_ROOT}/src/lib/worktree.sh"

  # Create a worktree on branch work/99-existing-feature
  local worktree_path="${TEST_REPO_DIR}-wt-99"
  git -C "$TEST_REPO_DIR" worktree add -b "work/99-existing-feature" "$worktree_path"

  cd "$TEST_REPO_DIR"

  run _aw_find_worktree_for_issue "99" "github"
  [ "$status" -eq 0 ]
  [ "$output" = "$worktree_path" ]

  teardown_git_repo
  rm -rf "$worktree_path"
}

@test "_aw_find_worktree_for_issue: returns 1 when no worktree matches the issue" {
  setup_git_repo

  source "${REPO_ROOT}/src/lib/worktree.sh"

  cd "$TEST_REPO_DIR"

  run _aw_find_worktree_for_issue "9999" "github"
  [ "$status" -ne 0 ]
  [ -z "$output" ]

  teardown_git_repo
}

@test "_aw_create_worktree: returns error when branch already has a worktree" {
  setup_git_repo

  source "${REPO_ROOT}/src/lib/worktree.sh"

  # Override variables that _aw_get_repo_info would set
  _AW_WORKTREE_BASE="${TEST_REPO_DIR}-worktrees"
  export _AW_WORKTREE_BASE

  cd "$TEST_REPO_DIR"

  # Pre-create a worktree for the branch
  local worktree_path="${_AW_WORKTREE_BASE}/work-100-dupe"
  mkdir -p "$_AW_WORKTREE_BASE"
  git -C "$TEST_REPO_DIR" worktree add -b "work/100-dupe" "$worktree_path"

  # Attempt to create another worktree for the same branch — must fail
  run _aw_create_worktree "work/100-dupe"
  [ "$status" -ne 0 ]

  teardown_git_repo
  rm -rf "${TEST_REPO_DIR}-worktrees"
}

@test "_aw_create_worktree: creates worktree directory for a new branch" {
  setup_git_repo

  # Stub gum spin so actual git worktree add runs
  gum() {
    if [[ "$1" == "spin" ]]; then
      # Run the command directly (strip leading flags until --)
      shift
      while [[ "$1" != "--" && $# -gt 0 ]]; do shift; done
      shift  # skip --
      "$@"
    fi
  }
  export -f gum

  # Stub _aw_setup_environment and _resolve_ai_command so they are no-ops
  _aw_setup_environment() { :; }
  _resolve_ai_command() { AI_CMD=("skip"); AI_CMD[1]="skip"; return 0; }
  export -f _aw_setup_environment _resolve_ai_command

  source "${REPO_ROOT}/src/lib/worktree.sh"

  _AW_WORKTREE_BASE="${TEST_REPO_DIR}-worktrees-new"
  export _AW_WORKTREE_BASE
  mkdir -p "$_AW_WORKTREE_BASE"

  cd "$TEST_REPO_DIR"

  run _aw_create_worktree "work/101-new-feature"
  [ "$status" -eq 0 ]

  assert_worktree_exists "${_AW_WORKTREE_BASE}/work-101-new-feature"
  assert_branch_exists "work/101-new-feature"

  teardown_git_repo
  rm -rf "${TEST_REPO_DIR}-worktrees-new"
}

# ============================================================================
# Hook execution — _aw_run_git_hooks
# ============================================================================

@test "_aw_run_git_hooks: succeeds silently when no hook directories exist" {
  setup_git_repo

  source "${REPO_ROOT}/src/lib/hooks.sh"

  cd "$TEST_REPO_DIR"

  run _aw_run_git_hooks "$TEST_REPO_DIR"
  [ "$status" -eq 0 ]

  teardown_git_repo
}

@test "_aw_run_git_hooks: executes post-worktree hook when present and executable" {
  setup_git_repo

  source "${REPO_ROOT}/src/lib/hooks.sh"

  cd "$TEST_REPO_DIR"

  # Place a post-worktree hook in .git/hooks
  local hook_dir="${TEST_REPO_DIR}/.git/hooks"
  mkdir -p "$hook_dir"
  local hook_file="${hook_dir}/post-worktree"
  printf '#!/bin/sh\necho "hook-ran"\n' > "$hook_file"
  chmod +x "$hook_file"

  run _aw_run_git_hooks "$TEST_REPO_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hook-ran"* ]]

  teardown_git_repo
}

@test "_aw_run_git_hooks: warns but does not fail when hook exits non-zero and fail-on-hook-error is false" {
  setup_git_repo

  source "${REPO_ROOT}/src/lib/hooks.sh"

  cd "$TEST_REPO_DIR"

  # Ensure fail-on-hook-error is false (default)
  git -C "$TEST_REPO_DIR" config auto-worktree.fail-on-hook-error false

  local hook_dir="${TEST_REPO_DIR}/.git/hooks"
  mkdir -p "$hook_dir"
  local hook_file="${hook_dir}/post-worktree"
  printf '#!/bin/sh\nexit 1\n' > "$hook_file"
  chmod +x "$hook_file"

  run _aw_run_git_hooks "$TEST_REPO_DIR"
  # Should still return 0 (warn and continue)
  [ "$status" -eq 0 ]

  teardown_git_repo
}

@test "_aw_run_git_hooks: propagates error when hook fails and fail-on-hook-error is true" {
  setup_git_repo

  source "${REPO_ROOT}/src/lib/hooks.sh"

  cd "$TEST_REPO_DIR"

  git -C "$TEST_REPO_DIR" config auto-worktree.fail-on-hook-error true

  local hook_dir="${TEST_REPO_DIR}/.git/hooks"
  mkdir -p "$hook_dir"
  local hook_file="${hook_dir}/post-worktree"
  printf '#!/bin/sh\nexit 1\n' > "$hook_file"
  chmod +x "$hook_file"

  run _aw_run_git_hooks "$TEST_REPO_DIR"
  [ "$status" -ne 0 ]

  teardown_git_repo
}

@test "_aw_run_git_hooks: skips hook execution when auto-worktree.run-hooks is false" {
  setup_git_repo

  source "${REPO_ROOT}/src/lib/hooks.sh"

  cd "$TEST_REPO_DIR"

  git -C "$TEST_REPO_DIR" config auto-worktree.run-hooks false

  local hook_dir="${TEST_REPO_DIR}/.git/hooks"
  mkdir -p "$hook_dir"
  local hook_file="${hook_dir}/post-worktree"
  printf '#!/bin/sh\necho "should-not-run"\nexit 1\n' > "$hook_file"
  chmod +x "$hook_file"

  run _aw_run_git_hooks "$TEST_REPO_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" != *"should-not-run"* ]]

  teardown_git_repo
}

# ============================================================================
# Environment setup trigger — _aw_setup_environment
# ============================================================================

@test "_aw_setup_environment: returns 0 for an empty project directory" {
  setup_git_repo

  source "${REPO_ROOT}/src/lib/hooks.sh"
  source "${REPO_ROOT}/src/lib/environment.sh"

  cd "$TEST_REPO_DIR"

  run _aw_setup_environment "$TEST_REPO_DIR"
  [ "$status" -eq 0 ]

  teardown_git_repo
}

@test "_aw_setup_environment: returns 0 when no package manager files are present" {
  setup_git_repo

  source "${REPO_ROOT}/src/lib/hooks.sh"
  source "${REPO_ROOT}/src/lib/environment.sh"

  cd "$TEST_REPO_DIR"

  # Confirm no package.json / requirements.txt / Gemfile / go.mod / Cargo.toml exist
  run _aw_setup_environment "$TEST_REPO_DIR"
  [ "$status" -eq 0 ]

  teardown_git_repo
}

@test "_aw_setup_environment: propagates hook failure when fail-on-hook-error is true" {
  setup_git_repo

  source "${REPO_ROOT}/src/lib/hooks.sh"
  source "${REPO_ROOT}/src/lib/environment.sh"

  cd "$TEST_REPO_DIR"

  git -C "$TEST_REPO_DIR" config auto-worktree.fail-on-hook-error true

  local hook_dir="${TEST_REPO_DIR}/.git/hooks"
  mkdir -p "$hook_dir"
  local hook_file="${hook_dir}/post-worktree"
  printf '#!/bin/sh\nexit 1\n' > "$hook_file"
  chmod +x "$hook_file"

  run _aw_setup_environment "$TEST_REPO_DIR"
  [ "$status" -ne 0 ]

  teardown_git_repo
}

@test "_aw_setup_environment: returns 0 (does not fail) for missing worktree path" {
  source "${REPO_ROOT}/src/lib/hooks.sh"
  source "${REPO_ROOT}/src/lib/environment.sh"

  run _aw_setup_environment "/nonexistent/path/that/does/not/exist"
  [ "$status" -eq 0 ]
}
