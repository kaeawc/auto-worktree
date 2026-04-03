#!/usr/bin/env bats
# Tests for src/commands/pr.sh
#
# Coverage:
#   - _aw_pr_action_menu: maps gum choice to action strings
#   - _aw_pr_build_prompt: generates AI prompts for each action type
#   - _aw_pr_build_prompt: uses correct PR/MR label per provider

load 'test_helper/common-setup'
load 'helpers/setup_git_repo'
load 'helpers/stub_gum'

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

setup() {
  _common_setup
  setup_git_repo
  setup_stub_gum

  # Stub dependencies that pr.sh expects
  _aw_get_issue_provider() { echo "github"; }
  export -f _aw_get_issue_provider
  _aw_get_ai_tool_cmd() { echo ""; }
  export -f _aw_get_ai_tool_cmd

  # shellcheck source=../src/lib/utils.sh
  source "${REPO_ROOT}/src/lib/utils.sh"
  # shellcheck source=../src/lib/config.sh
  source "${REPO_ROOT}/src/lib/config.sh"
  # shellcheck source=../src/lib/ai.sh
  source "${REPO_ROOT}/src/lib/ai.sh"
  # shellcheck source=../src/lib/worktree.sh
  source "${REPO_ROOT}/src/lib/worktree.sh"
  # shellcheck source=../src/lib/environment.sh
  source "${REPO_ROOT}/src/lib/environment.sh"
  # shellcheck source=../src/commands/pr.sh
  source "${REPO_ROOT}/src/commands/pr.sh"
}

teardown() {
  teardown_stub_gum
  teardown_git_repo
}

# ============================================================================
# _aw_pr_action_menu
# ============================================================================

@test "_aw_pr_action_menu: returns 'continue' for 'Continue work'" {
  gum_respond "Continue work"
  run _aw_pr_action_menu
  assert_success
  assert_line "continue"
}

@test "_aw_pr_action_menu: returns 'fix' for 'Fix issues'" {
  gum_respond "Fix issues"
  run _aw_pr_action_menu
  assert_success
  assert_line "fix"
}

@test "_aw_pr_action_menu: returns 'review' for 'Review & suggest fixes'" {
  gum_respond "Review & suggest fixes"
  run _aw_pr_action_menu
  assert_success
  assert_line "review"
}

@test "_aw_pr_action_menu: returns empty for 'Cancel'" {
  gum_respond "Cancel"
  run _aw_pr_action_menu
  assert_success
  assert_output ""
}

# ============================================================================
# _aw_pr_build_prompt
# ============================================================================

@test "_aw_pr_build_prompt: continue prompt includes PR metadata" {
  run _aw_pr_build_prompt "continue" "github" "42" "Fix login" "alice" "feature-branch" "main"
  assert_success
  assert_output --partial "PR #42"
  assert_output --partial "Fix login"
  assert_output --partial "@alice"
  assert_output --partial "feature-branch"
  assert_output --partial "main"
}

@test "_aw_pr_build_prompt: continue prompt mentions diff and TODOs" {
  run _aw_pr_build_prompt "continue" "github" "42" "Fix login" "alice" "feature-branch" "main"
  assert_success
  assert_output --partial "diff"
  assert_output --partial "continue"
}

@test "_aw_pr_build_prompt: fix prompt mentions CI and tests" {
  run _aw_pr_build_prompt "fix" "github" "42" "Fix login" "alice" "feature-branch" "main"
  assert_success
  assert_output --partial "CI"
  assert_output --partial "test"
}

@test "_aw_pr_build_prompt: review prompt says READ-ONLY" {
  run _aw_pr_build_prompt "review" "github" "42" "Fix login" "alice" "feature-branch" "main"
  assert_success
  assert_output --partial "READ-ONLY"
  assert_output --partial "do NOT modify"
}

@test "_aw_pr_build_prompt: gitlab uses MR label instead of PR" {
  run _aw_pr_build_prompt "continue" "gitlab" "15" "Update docs" "bob" "docs-branch" "develop"
  assert_success
  assert_output --partial "MR !15"
  refute_output --partial "PR #"
}

@test "_aw_pr_build_prompt: review prompt includes severity levels" {
  run _aw_pr_build_prompt "review" "github" "42" "Fix login" "alice" "feat" "main"
  assert_success
  assert_output --partial "critical"
  assert_output --partial "major"
  assert_output --partial "minor"
}
