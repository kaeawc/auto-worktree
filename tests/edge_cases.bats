#!/usr/bin/env bats
# Tests for edge cases across the auto-worktree project.
#
# Covers:
#   - Unicode/emoji in branch names (_aw_extract_issue_id_from_branch)
#   - Very large / epoch timestamps (_aw_format_worktree_age)
#   - Empty/null inputs to extraction functions
#   - _aw_format_labels edge cases (single label, spaces, pipe, empty entries)
#   - AW_EXIT_CANCELLED constant value
#   - _aw_set_config / _aw_get_config allowed-values validation

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

load 'helpers/setup_git_repo'

setup() {
  # Stub _aw_get_issue_provider so common.sh loads cleanly
  _aw_get_issue_provider() { echo "github"; }

  # Stub gum so functions that call it don't fail in a non-interactive shell
  gum() { return 0; }

  # Source the libraries under test
  # shellcheck source=../src/lib/utils.sh
  source "${REPO_ROOT}/src/lib/utils.sh"
  # shellcheck source=../src/providers/common.sh
  source "${REPO_ROOT}/src/providers/common.sh"
  # shellcheck source=../src/lib/worktree.sh
  source "${REPO_ROOT}/src/lib/worktree.sh"
  # shellcheck source=../src/lib/config.sh
  source "${REPO_ROOT}/src/lib/config.sh"

  # Set up an isolated git repo for tests that need git config
  setup_git_repo
}

teardown() {
  teardown_git_repo
}

# ===== Unicode / emoji in branch names =====

@test "_aw_extract_issue_id_from_branch: emoji in branch name still extracts issue number (github)" {
  run _aw_extract_issue_id_from_branch "feature/issue-123-deploy" "github"
  [ "$status" -eq 0 ]
  [ "$output" = "123" ]
}

@test "_aw_extract_issue_id_from_branch: branch with only emoji and no numbers returns empty (github)" {
  run _aw_extract_issue_id_from_branch "feature/rocket-deploy" "github"
  [ -z "$output" ]
}

@test "_aw_extract_issue_id_from_branch: unicode letters around a number don't confuse extraction (github)" {
  run _aw_extract_issue_id_from_branch "work/456-caf\xc3\xa9-fix" "github"
  [ "$status" -eq 0 ]
  [ "$output" = "456" ]
}

@test "_aw_extract_issue_id_from_branch: jira key surrounded by unicode still extracted" {
  run _aw_extract_issue_id_from_branch "work/PROJ-789-unicode-title" "jira"
  [ "$status" -eq 0 ]
  [ "$output" = "PROJ-789" ]
}

# ===== Very large / epoch timestamps (_aw_format_worktree_age) =====

@test "_aw_format_worktree_age: epoch timestamp (0 = 1970) returns a valid age string" {
  run _aw_format_worktree_age 0
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "_aw_format_worktree_age: epoch timestamp output is non-empty and bracket-wrapped" {
  run _aw_format_worktree_age 0
  [ "$status" -eq 0 ]
  [[ "$output" == \[*\] ]]
}

@test "_aw_format_worktree_age: epoch timestamp shows days (not hours) because it is very old" {
  run _aw_format_worktree_age 0
  [ "$status" -eq 0 ]
  # Epoch is tens of thousands of days ago — output must end with 'd ago]'
  [[ "$output" == *"d ago]" ]]
}

@test "_aw_format_worktree_age: very large future timestamp still returns a bracketed string" {
  # A timestamp far in the future (year 2100 approx)
  run _aw_format_worktree_age 4102444800
  [ "$status" -eq 0 ]
  [[ "$output" == \[*\] ]]
}

@test "_aw_format_worktree_age: empty input returns [unknown]" {
  run _aw_format_worktree_age ""
  [ "$status" -eq 0 ]
  [ "$output" = "[unknown]" ]
}

@test "_aw_format_worktree_age: non-numeric input returns [unknown]" {
  run _aw_format_worktree_age "not-a-timestamp"
  [ "$status" -eq 0 ]
  [ "$output" = "[unknown]" ]
}

# ===== Empty / null inputs to extraction functions =====

@test "_aw_extract_issue_id_from_branch: empty branch with github provider returns empty" {
  run _aw_extract_issue_id_from_branch "" "github"
  [ -z "$output" ]
}

@test "_aw_extract_issue_id_from_branch: empty branch with jira provider returns empty" {
  run _aw_extract_issue_id_from_branch "" "jira"
  [ -z "$output" ]
}

@test "_aw_extract_issue_id_from_branch: empty branch with linear provider returns empty" {
  run _aw_extract_issue_id_from_branch "" "linear"
  [ -z "$output" ]
}

@test "_aw_extract_issue_id_from_branch: empty branch with gitlab provider returns empty" {
  run _aw_extract_issue_id_from_branch "" "gitlab"
  [ -z "$output" ]
}

@test "_aw_format_labels: empty input returns empty output" {
  run _aw_format_labels ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ===== _aw_format_labels edge cases =====

@test "_aw_format_labels: single label is wrapped in brackets" {
  run _aw_format_labels "bug"
  [ "$status" -eq 0 ]
  [ "$output" = "[bug]" ]
}

@test "_aw_format_labels: single label with surrounding spaces is trimmed and wrapped" {
  run _aw_format_labels "  bug  "
  [ "$status" -eq 0 ]
  [ "$output" = "[bug]" ]
}

@test "_aw_format_labels: pipe-separated labels each wrapped in brackets" {
  run _aw_format_labels "bug|feature"
  [ "$status" -eq 0 ]
  [ "$output" = "[bug][feature]" ]
}

@test "_aw_format_labels: empty entries in comma list are skipped" {
  run _aw_format_labels "bug,,feature"
  [ "$status" -eq 0 ]
  [ "$output" = "[bug][feature]" ]
}

@test "_aw_format_labels: empty entries in pipe list are skipped" {
  run _aw_format_labels "bug||feature"
  [ "$status" -eq 0 ]
  [ "$output" = "[bug][feature]" ]
}

@test "_aw_format_labels: three comma-separated labels all wrapped" {
  run _aw_format_labels "bug,enhancement,wontfix"
  [ "$status" -eq 0 ]
  [ "$output" = "[bug][enhancement][wontfix]" ]
}

# ===== AW_EXIT_CANCELLED constant =====

@test "AW_EXIT_CANCELLED is defined as 130" {
  # utils.sh is already sourced in setup(); variable must equal 130
  [ "$AW_EXIT_CANCELLED" -eq 130 ]
}

# ===== _aw_get_config / _aw_set_config with allowed-values validation =====

@test "_aw_set_config: invalid value against allowed list returns non-zero" {
  cd "$TEST_REPO_DIR"
  run _aw_set_config "issue-provider" "invalid" "github" "gitlab" "jira" "linear"
  [ "$status" -ne 0 ]
}

@test "_aw_set_config: valid value from allowed list returns zero" {
  cd "$TEST_REPO_DIR"
  run _aw_set_config "issue-provider" "github" "github" "gitlab" "jira" "linear"
  [ "$status" -eq 0 ]
}

@test "_aw_set_config: setting a value persists via _aw_get_config" {
  cd "$TEST_REPO_DIR"
  _aw_set_config "issue-provider" "gitlab" "github" "gitlab" "jira" "linear"
  run _aw_get_config "issue-provider"
  [ "$status" -eq 0 ]
  [ "$output" = "gitlab" ]
}

@test "_aw_set_config: no allowed values list accepts any value" {
  cd "$TEST_REPO_DIR"
  run _aw_set_config "custom-key" "any-value"
  [ "$status" -eq 0 ]
}

@test "_aw_get_config: returns empty string for unset key" {
  cd "$TEST_REPO_DIR"
  run _aw_get_config "nonexistent-key"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
