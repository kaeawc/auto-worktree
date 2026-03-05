#!/usr/bin/env bats
# Tests for src/providers/common.sh
#
# Covers:
#   - _aw_extract_issue_id_from_branch (all 4 providers + edge cases)
#   - _aw_get_default_branch (main and master detection)
#   - _aw_milestone_terminology
#   - _aw_format_labels

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

load 'helpers/setup_git_repo'

setup() {
  # Stub _aw_get_issue_provider before sourcing so common.sh can load cleanly
  _aw_get_issue_provider() { echo "github"; }

  # Source the pure utility functions under test
  # shellcheck source=../src/lib/utils.sh
  source "${REPO_ROOT}/src/lib/utils.sh"
  # shellcheck source=../src/providers/common.sh
  source "${REPO_ROOT}/src/providers/common.sh"

  # Set up an isolated git repo for tests that need one
  setup_git_repo
}

teardown() {
  teardown_git_repo
}

# ===== _aw_extract_issue_id_from_branch =====

@test "_aw_extract_issue_id_from_branch: github extracts issue number" {
  run _aw_extract_issue_id_from_branch "feature/issue-123-my-feature" "github"
  [ "$status" -eq 0 ]
  [ "$output" = "123" ]
}

@test "_aw_extract_issue_id_from_branch: gitlab extracts issue number" {
  run _aw_extract_issue_id_from_branch "feature/456-my-feature" "gitlab"
  [ "$status" -eq 0 ]
  [ "$output" = "456" ]
}

@test "_aw_extract_issue_id_from_branch: jira extracts PROJ-456" {
  run _aw_extract_issue_id_from_branch "feature/PROJ-456-my-feature" "jira"
  [ "$status" -eq 0 ]
  [ "$output" = "PROJ-456" ]
}

@test "_aw_extract_issue_id_from_branch: linear extracts TEAM-789" {
  run _aw_extract_issue_id_from_branch "feature/TEAM-789-my-feature" "linear"
  [ "$status" -eq 0 ]
  [ "$output" = "TEAM-789" ]
}

@test "_aw_extract_issue_id_from_branch: returns empty for no match on github" {
  run _aw_extract_issue_id_from_branch "feature/no-issue-here" "github"
  [ -z "$output" ]
}

@test "_aw_extract_issue_id_from_branch: returns empty for no match on jira" {
  run _aw_extract_issue_id_from_branch "feature/no-issue-here" "jira"
  [ -z "$output" ]
}

@test "_aw_extract_issue_id_from_branch: empty branch name returns empty" {
  run _aw_extract_issue_id_from_branch "" "github"
  [ -z "$output" ]
}

@test "_aw_extract_issue_id_from_branch: empty branch name with jira returns empty" {
  run _aw_extract_issue_id_from_branch "" "jira"
  [ -z "$output" ]
}

@test "_aw_extract_issue_id_from_branch: github work/N-description format" {
  run _aw_extract_issue_id_from_branch "work/99-fix-login" "github"
  [ "$status" -eq 0 ]
  [ "$output" = "99" ]
}

@test "_aw_extract_issue_id_from_branch: jira multi-char prefix MYPROJ-100" {
  run _aw_extract_issue_id_from_branch "work/MYPROJ-100-some-fix" "jira"
  [ "$status" -eq 0 ]
  [ "$output" = "MYPROJ-100" ]
}

@test "_aw_extract_issue_id_from_branch: linear single-char team prefix A-1" {
  run _aw_extract_issue_id_from_branch "work/A-1-tiny-fix" "linear"
  [ "$status" -eq 0 ]
  [ "$output" = "A-1" ]
}

@test "_aw_extract_issue_id_from_branch: branch with only text and no numbers returns empty for github" {
  run _aw_extract_issue_id_from_branch "refactor-cleanup-everything" "github"
  [ -z "$output" ]
}

# ===== _aw_get_default_branch =====

@test "_aw_get_default_branch: detects main when main branch exists" {
  # setup_git_repo creates the initial commit on whatever the default branch is;
  # rename to 'main' to ensure it exists
  git -C "$TEST_REPO_DIR" checkout -b main 2>/dev/null || true
  cd "$TEST_REPO_DIR"

  run _aw_get_default_branch
  [ "$status" -eq 0 ]
  [ "$output" = "main" ]
}

@test "_aw_get_default_branch: detects master when master branch exists" {
  # Create a repo that has master but no main
  cd "$TEST_REPO_DIR"
  # Rename the current branch (whatever it is) to master
  git branch -m master 2>/dev/null || git checkout -b master 2>/dev/null || true

  run _aw_get_default_branch
  [ "$status" -eq 0 ]
  [ "$output" = "master" ]
}

@test "_aw_get_default_branch: returns non-empty string in a valid git repo" {
  cd "$TEST_REPO_DIR"
  run _aw_get_default_branch
  # Should succeed with some output (main or master depending on git config)
  [ -n "$output" ]
}

# ===== _aw_milestone_terminology =====

@test "_aw_milestone_terminology: github returns Milestone" {
  run _aw_milestone_terminology "github"
  [ "$status" -eq 0 ]
  [ "$output" = "Milestone" ]
}

@test "_aw_milestone_terminology: gitlab returns Milestone" {
  run _aw_milestone_terminology "gitlab"
  [ "$status" -eq 0 ]
  [ "$output" = "Milestone" ]
}

@test "_aw_milestone_terminology: jira returns Epic" {
  run _aw_milestone_terminology "jira"
  [ "$status" -eq 0 ]
  [ "$output" = "Epic" ]
}

@test "_aw_milestone_terminology: linear returns Project" {
  run _aw_milestone_terminology "linear"
  [ "$status" -eq 0 ]
  [ "$output" = "Project" ]
}

@test "_aw_milestone_terminology: unknown provider returns Milestone" {
  run _aw_milestone_terminology "unknown"
  [ "$status" -eq 0 ]
  [ "$output" = "Milestone" ]
}

# ===== _aw_format_labels =====

@test "_aw_format_labels: single label wrapped in brackets" {
  run _aw_format_labels "bug"
  [ "$status" -eq 0 ]
  [ "$output" = "[bug]" ]
}

@test "_aw_format_labels: comma-separated labels each wrapped in brackets" {
  run _aw_format_labels "bug,enhancement"
  [ "$status" -eq 0 ]
  [ "$output" = "[bug][enhancement]" ]
}

@test "_aw_format_labels: pipe-separated labels each wrapped in brackets" {
  run _aw_format_labels "bug|enhancement"
  [ "$status" -eq 0 ]
  [ "$output" = "[bug][enhancement]" ]
}

@test "_aw_format_labels: empty labels returns nothing" {
  run _aw_format_labels ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_aw_format_labels: labels with surrounding spaces are trimmed" {
  run _aw_format_labels " bug , enhancement "
  [ "$status" -eq 0 ]
  [ "$output" = "[bug][enhancement]" ]
}
