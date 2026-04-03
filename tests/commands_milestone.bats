#!/usr/bin/env bats
# Tests for src/commands/milestone.sh
#
# Coverage:
#   - _aw_select_milestone: milestone ID/title extraction from selection string
#   - _aw_select_issue_by_milestone: issue ID extraction from selection string
#   - Provider dispatch: correct provider functions called

load 'test_helper/common-setup'
load 'helpers/setup_git_repo'
load 'helpers/stub_gum'
load 'helpers/mock_cli'

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

setup() {
  _common_setup
  setup_git_repo
  setup_stub_gum
  setup_mock_cli

  # Stub provider functions
  _aw_get_issue_provider() { echo "github"; }
  _aw_init_issue_provider() { echo "github"; }
  _aw_ensure_git_repo() { return 0; }
  _aw_get_repo_info() { return 0; }
  _aw_get_ai_tool_cmd() { echo ""; }
  export -f _aw_get_issue_provider _aw_init_issue_provider _aw_ensure_git_repo _aw_get_repo_info _aw_get_ai_tool_cmd

  AW_EXIT_CANCELLED=130
  export AW_EXIT_CANCELLED

  # shellcheck source=../src/lib/utils.sh
  source "${REPO_ROOT}/src/lib/utils.sh"
  # shellcheck source=../src/lib/config.sh
  source "${REPO_ROOT}/src/lib/config.sh"
  # shellcheck source=../src/providers/common.sh
  source "${REPO_ROOT}/src/providers/common.sh"
  # shellcheck source=../src/commands/milestone.sh
  source "${REPO_ROOT}/src/commands/milestone.sh"
}

teardown() {
  teardown_mock_cli
  teardown_stub_gum
  teardown_git_repo
}

# ============================================================================
# _aw_select_milestone
# ============================================================================

@test "_aw_select_milestone: extracts milestone_id and milestone_title from selection" {
  # Stub the list function to return milestones
  _aw_github_list_milestones() { echo "v1.0 | Release 1.0 | [3 issues]"; }
  export -f _aw_github_list_milestones

  # gum filter returns the full line
  gum_respond "v1.0 | Release 1.0 | [3 issues]"

  _aw_select_milestone "github" "Milestone"
  [[ "$milestone_id" == "v1.0" ]]
  [[ "$milestone_title" == "Release 1.0" ]]
}

@test "_aw_select_milestone: returns 1 when no milestones found" {
  _aw_github_list_milestones() { echo ""; }
  export -f _aw_github_list_milestones

  run _aw_select_milestone "github" "Milestone"
  assert_failure
  assert_output --partial "No open milestones found"
}

@test "_aw_select_milestone: returns cancelled when gum filter returns empty" {
  _aw_github_list_milestones() { echo "v1.0 | Release 1.0"; }
  export -f _aw_github_list_milestones

  # gum filter returns empty (user cancelled)
  gum_respond ""

  run _aw_select_milestone "github" "Milestone"
  [[ "$status" -eq 130 ]]
}

# ============================================================================
# _aw_select_issue_by_milestone
# ============================================================================

@test "_aw_select_issue_by_milestone: extracts issue_id from github selection" {
  _aw_github_list_issues_by_milestone() { echo "#42 | Fix login bug | [bug]"; }
  export -f _aw_github_list_issues_by_milestone

  gum_respond "#42 | Fix login bug | [bug]"

  _aw_select_issue_by_milestone "github" "v1.0" "Release 1.0" "Milestone"
  [[ "$issue_id" == "42" ]]
}

@test "_aw_select_issue_by_milestone: returns 1 when no issues found" {
  _aw_github_list_issues_by_milestone() { echo ""; }
  export -f _aw_github_list_issues_by_milestone

  run _aw_select_issue_by_milestone "github" "v1.0" "Release 1.0" "Milestone"
  assert_failure
  assert_output --partial "No open issues found"
}

@test "_aw_select_issue_by_milestone: returns 1 for linear (unsupported)" {
  run _aw_select_issue_by_milestone "linear" "proj-1" "Project 1" "Project"
  assert_failure
  assert_output --partial "Linear does not support"
}

@test "_aw_select_issue_by_milestone: extracts jira key from selection" {
  _aw_jira_list_issues_by_epic() { echo "PROJ-123 | Implement feature | [task]"; }
  export -f _aw_jira_list_issues_by_epic

  gum_respond "PROJ-123 | Implement feature | [task]"

  _aw_select_issue_by_milestone "jira" "EPIC-1" "Epic One" "Epic"
  [[ "$issue_id" == "PROJ-123" ]]
}

# ============================================================================
# _aw_milestone_terminology (from providers/common.sh)
# ============================================================================

@test "_aw_milestone: uses correct terminology for each provider" {
  # This tests that the terminology function is wired correctly
  run _aw_milestone_terminology "github"
  assert_output "Milestone"

  run _aw_milestone_terminology "jira"
  assert_output "Epic"

  run _aw_milestone_terminology "linear"
  assert_output "Project"
}
