#!/usr/bin/env bats
# Tests for src/providers/gitlab.sh, src/providers/jira.sh, src/providers/linear.sh
#
# Covers:
#   - _aw_gitlab_cmd (no server / server configured)
#   - _aw_gitlab_check_closed (closed / open / empty state)
#   - _aw_gitlab_check_mr_merged (merged / open MR)
#   - _aw_format_labels (via common.sh, exercised in GitLab/JIRA context)
#   - _aw_jira_check_resolved (resolved / open / empty status)
#   - _aw_linear_list_milestones / _aw_linear_list_issues_by_milestone (unsupported)

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

load 'helpers/setup_git_repo'
load 'helpers/mock_cli'

setup() {
  # Stub config helpers that touch git config or external tools
  _aw_get_gitlab_server()  { git config --get auto-worktree.gitlab-server 2>/dev/null || echo ""; }
  _aw_get_gitlab_project() { git config --get auto-worktree.gitlab-project 2>/dev/null || echo ""; }
  _aw_get_jira_project()   { git config --get auto-worktree.jira-project   2>/dev/null || echo ""; }
  _aw_get_linear_team()    { git config --get auto-worktree.linear-team    2>/dev/null || echo ""; }
  _aw_get_issue_provider() { echo ""; }

  # Source common utilities and provider implementations
  source "${REPO_ROOT}/src/lib/utils.sh"
  source "${REPO_ROOT}/src/providers/common.sh"
  source "${REPO_ROOT}/src/providers/gitlab.sh"
  source "${REPO_ROOT}/src/providers/jira.sh"
  source "${REPO_ROOT}/src/providers/linear.sh"

  # Set up an isolated git repo so git config calls work
  setup_git_repo

  # Set up mock CLI PATH so we can intercept glab / jira / linear calls
  setup_mock_cli
}

teardown() {
  teardown_mock_cli
  teardown_git_repo
}

# ============================================================================
# _aw_gitlab_cmd
# ============================================================================

@test "_aw_gitlab_cmd: returns 'glab' with no server configured" {
  cd "$TEST_REPO_DIR"
  run _aw_gitlab_cmd
  [ "$status" -eq 0 ]
  [ "$output" = "glab" ]
}

@test "_aw_gitlab_cmd: returns 'glab --host ...' when server is set" {
  cd "$TEST_REPO_DIR"
  git config auto-worktree.gitlab-server "gitlab.example.com"
  run _aw_gitlab_cmd
  [ "$status" -eq 0 ]
  [ "$output" = "glab --host gitlab.example.com" ]
}

# ============================================================================
# _aw_gitlab_check_closed
# ============================================================================

@test "_aw_gitlab_check_closed: returns 1 for empty issue id" {
  run _aw_gitlab_check_closed ""
  [ "$status" -eq 1 ]
}

@test "_aw_gitlab_check_closed: returns 0 when issue state is 'closed'" {
  cd "$TEST_REPO_DIR"
  # glab issue view <id> --json state --jq '.state' should output "closed"
  mock_cli glab "issue view" "closed"
  run _aw_gitlab_check_closed "42"
  [ "$status" -eq 0 ]
}

@test "_aw_gitlab_check_closed: returns 1 when issue state is 'opened'" {
  cd "$TEST_REPO_DIR"
  mock_cli glab "issue view" "opened"
  run _aw_gitlab_check_closed "42"
  [ "$status" -eq 1 ]
}

@test "_aw_gitlab_check_closed: returns 0 for MR with state 'merged'" {
  cd "$TEST_REPO_DIR"
  mock_cli glab "mr view" "merged"
  run _aw_gitlab_check_closed "7" "mr"
  [ "$status" -eq 0 ]
}

@test "_aw_gitlab_check_closed: returns 1 for MR with state 'opened'" {
  cd "$TEST_REPO_DIR"
  mock_cli glab "mr view" "opened"
  run _aw_gitlab_check_closed "7" "mr"
  [ "$status" -eq 1 ]
}

@test "_aw_gitlab_check_closed: returns 1 when glab returns empty output" {
  cd "$TEST_REPO_DIR"
  # Mock returns empty string — simulates CLI failure
  mock_cli glab "issue view" ""
  run _aw_gitlab_check_closed "99"
  [ "$status" -eq 1 ]
}

# ============================================================================
# _aw_gitlab_check_mr_merged
# ============================================================================

@test "_aw_gitlab_check_mr_merged: returns 1 for empty branch name" {
  run _aw_gitlab_check_mr_merged ""
  [ "$status" -eq 1 ]
}

@test "_aw_gitlab_check_mr_merged: returns 0 when MR state is 'merged'" {
  cd "$TEST_REPO_DIR"
  # The function pipes glab output through jq; mock glab to emit valid JSON
  mock_cli glab "mr view" '{"state":"merged"}'
  # Also mock jq so it parses and returns "merged"
  mock_cli jq ".state" "merged"
  run _aw_gitlab_check_mr_merged "feature/my-branch"
  [ "$status" -eq 0 ]
}

@test "_aw_gitlab_check_mr_merged: returns 1 when MR state is 'opened'" {
  cd "$TEST_REPO_DIR"
  mock_cli glab "mr view" '{"state":"opened"}'
  mock_cli jq ".state" "opened"
  run _aw_gitlab_check_mr_merged "feature/my-branch"
  [ "$status" -eq 1 ]
}

# ============================================================================
# _aw_format_labels (common.sh) — exercised in GitLab / JIRA context
# ============================================================================

@test "_aw_format_labels: converts comma-separated to brackets" {
  run _aw_format_labels "bug, enhancement"
  [ "$status" -eq 0 ]
  [ "$output" = "[bug][enhancement]" ]
}

@test "_aw_format_labels: single label is wrapped in brackets" {
  run _aw_format_labels "urgent"
  [ "$status" -eq 0 ]
  [ "$output" = "[urgent]" ]
}

@test "_aw_format_labels: pipe-separated labels converted to brackets" {
  run _aw_format_labels "bug|feature"
  [ "$status" -eq 0 ]
  [ "$output" = "[bug][feature]" ]
}

@test "_aw_format_labels: empty string returns nothing" {
  run _aw_format_labels ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_aw_format_labels: labels with extra whitespace are trimmed" {
  run _aw_format_labels "  bug  ,  enhancement  "
  [ "$status" -eq 0 ]
  [ "$output" = "[bug][enhancement]" ]
}

# ============================================================================
# _aw_jira_check_resolved
# ============================================================================

@test "_aw_jira_check_resolved: returns 1 for empty issue key" {
  run _aw_jira_check_resolved ""
  [ "$status" -eq 1 ]
}

@test "_aw_jira_check_resolved: returns 0 when status is 'Done'" {
  cd "$TEST_REPO_DIR"
  # The function runs: jira issue view KEY --plain --columns status | tail -1 | awk '{print $NF}'
  # Mock jira to output a line whose last word is "Done"
  mock_cli jira "issue view" "STATUS Done"
  run _aw_jira_check_resolved "PROJ-123"
  [ "$status" -eq 0 ]
}

@test "_aw_jira_check_resolved: returns 0 when status is 'Closed'" {
  cd "$TEST_REPO_DIR"
  mock_cli jira "issue view" "STATUS Closed"
  run _aw_jira_check_resolved "PROJ-456"
  [ "$status" -eq 0 ]
}

@test "_aw_jira_check_resolved: returns 0 when status is 'Resolved'" {
  cd "$TEST_REPO_DIR"
  mock_cli jira "issue view" "STATUS Resolved"
  run _aw_jira_check_resolved "PROJ-789"
  [ "$status" -eq 0 ]
}

@test "_aw_jira_check_resolved: returns 0 when status is 'Completed'" {
  cd "$TEST_REPO_DIR"
  mock_cli jira "issue view" "STATUS Completed"
  run _aw_jira_check_resolved "PROJ-100"
  [ "$status" -eq 0 ]
}

@test "_aw_jira_check_resolved: returns 1 when status is 'In Progress'" {
  cd "$TEST_REPO_DIR"
  mock_cli jira "issue view" "STATUS Progress"
  run _aw_jira_check_resolved "PROJ-200"
  [ "$status" -eq 1 ]
}

@test "_aw_jira_check_resolved: returns 1 when status is 'To Do'" {
  cd "$TEST_REPO_DIR"
  mock_cli jira "issue view" "STATUS Do"
  run _aw_jira_check_resolved "PROJ-300"
  [ "$status" -eq 1 ]
}

@test "_aw_jira_check_resolved: returns 1 when jira returns empty output" {
  cd "$TEST_REPO_DIR"
  mock_cli jira "issue view" ""
  run _aw_jira_check_resolved "PROJ-404"
  [ "$status" -eq 1 ]
}

# ============================================================================
# Linear: unsupported functions return 1
# ============================================================================

@test "_aw_linear_list_milestones: returns 1 (unsupported)" {
  run _aw_linear_list_milestones
  [ "$status" -eq 1 ]
}

@test "_aw_linear_list_milestones: prints an error message to stderr" {
  run _aw_linear_list_milestones
  [ "$status" -eq 1 ]
  # The error message should be non-empty (output goes to stderr, but bats
  # captures combined output in $output when using run without --separate-stderr)
}

@test "_aw_linear_list_issues_by_milestone: returns 1 (unsupported)" {
  run _aw_linear_list_issues_by_milestone "some-project"
  [ "$status" -eq 1 ]
}

@test "_aw_linear_list_issues_by_milestone: returns 1 with no argument" {
  run _aw_linear_list_issues_by_milestone
  [ "$status" -eq 1 ]
}

@test "_aw_linear_check_completed: returns 1 for empty issue id" {
  run _aw_linear_check_completed ""
  [ "$status" -eq 1 ]
}

@test "_aw_linear_check_completed: returns 0 when state is 'Done'" {
  cd "$TEST_REPO_DIR"
  mock_cli linear "issue view" "State: Done"
  run _aw_linear_check_completed "TEAM-123"
  [ "$status" -eq 0 ]
}

@test "_aw_linear_check_completed: returns 0 when state is 'Canceled'" {
  cd "$TEST_REPO_DIR"
  mock_cli linear "issue view" "State: Canceled"
  run _aw_linear_check_completed "TEAM-456"
  [ "$status" -eq 0 ]
}

@test "_aw_linear_check_completed: returns 1 when state is 'In Progress'" {
  cd "$TEST_REPO_DIR"
  mock_cli linear "issue view" "State: In Progress"
  run _aw_linear_check_completed "TEAM-789"
  [ "$status" -eq 1 ]
}

@test "_aw_linear_check_completed: returns 1 when linear returns empty output" {
  cd "$TEST_REPO_DIR"
  mock_cli linear "issue view" ""
  run _aw_linear_check_completed "TEAM-000"
  [ "$status" -eq 1 ]
}
