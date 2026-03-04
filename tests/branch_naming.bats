#!/usr/bin/env bats
# Tests for branch naming conventions
#
# Enforces that branch names for GitHub issues preserve the issue number so that:
# 1. _aw_extract_issue_number can find it for display/cleanup
# 2. gh issue develop can be called to register the branch-issue link on GitHub

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

setup() {
  # Stub external-tool functions before sourcing so common.sh can load cleanly
  _aw_get_issue_provider() { echo "github"; }

  # Source only the pure utility functions under test
  # shellcheck source=../src/lib/utils.sh
  source "${REPO_ROOT}/src/lib/utils.sh"
  # shellcheck source=../src/providers/common.sh
  source "${REPO_ROOT}/src/providers/common.sh"
}

# ===== _aw_sanitize_branch_name =====

@test "_aw_sanitize_branch_name: spaces become hyphens" {
  run _aw_sanitize_branch_name "hello world"
  [ "$status" -eq 0 ]
  [ "$output" = "hello-world" ]
}

@test "_aw_sanitize_branch_name: uppercase becomes lowercase" {
  run _aw_sanitize_branch_name "Fix Login Bug"
  [ "$status" -eq 0 ]
  [ "$output" = "fix-login-bug" ]
}

@test "_aw_sanitize_branch_name: special chars become hyphens" {
  run _aw_sanitize_branch_name "fix: auth & session (critical)"
  [ "$status" -eq 0 ]
  [ "$output" = "fix-auth-session-critical" ]
}

@test "_aw_sanitize_branch_name: consecutive hyphens are collapsed" {
  run _aw_sanitize_branch_name "fix--double  space"
  [ "$status" -eq 0 ]
  [ "$output" = "fix-double-space" ]
}

@test "_aw_sanitize_branch_name: leading and trailing hyphens are stripped" {
  run _aw_sanitize_branch_name "-fix-me-"
  [ "$status" -eq 0 ]
  [ "$output" = "fix-me" ]
}

@test "_aw_sanitize_branch_name: produces valid git branch name characters" {
  run _aw_sanitize_branch_name "Feature/Add OAuth2 Support (v2.0)"
  [ "$status" -eq 0 ]
  # Output should only contain lowercase alphanumeric and hyphens
  [[ "$output" =~ ^[a-z0-9-]+$ ]]
}

# ===== _aw_extract_issue_number =====

@test "_aw_extract_issue_number: extracts from work/N-description format" {
  run _aw_extract_issue_number "work/123-fix-login-bug"
  [ "$status" -eq 0 ]
  [ "$output" = "123" ]
}

@test "_aw_extract_issue_number: extracts from plain N-description format" {
  run _aw_extract_issue_number "456-add-feature"
  [ "$status" -eq 0 ]
  [ "$output" = "456" ]
}

@test "_aw_extract_issue_number: handles multi-digit issue numbers" {
  run _aw_extract_issue_number "work/9999-big-issue"
  [ "$status" -eq 0 ]
  [ "$output" = "9999" ]
}

@test "_aw_extract_issue_number: handles single-digit issue numbers" {
  run _aw_extract_issue_number "work/7-tiny-fix"
  [ "$status" -eq 0 ]
  [ "$output" = "7" ]
}

# ===== GitHub issue branch naming invariant =====
# The default suggested branch name (work/${issue_id}-${sanitized}) must preserve
# the issue number so PRs can be auto-associated via gh issue develop

@test "GitHub issue branch name preserves issue number" {
  local issue_id="123"
  local title="Fix the login bug"
  local sanitized
  sanitized=$(_aw_sanitize_branch_name "$title" | cut -c1-40)
  local branch_name="work/${issue_id}-${sanitized}"

  run _aw_extract_issue_number "$branch_name"
  [ "$status" -eq 0 ]
  [ "$output" = "$issue_id" ]
}

@test "GitHub issue branch name preserves issue number with special chars in title" {
  local issue_id="456"
  local title="Fix: auth & session management (critical)"
  local sanitized
  sanitized=$(_aw_sanitize_branch_name "$title" | cut -c1-40)
  local branch_name="work/${issue_id}-${sanitized}"

  run _aw_extract_issue_number "$branch_name"
  [ "$status" -eq 0 ]
  [ "$output" = "$issue_id" ]
}

@test "GitHub issue branch name preserves issue number with long title truncated to 40 chars" {
  local issue_id="789"
  local title="This is a very long issue title that exceeds the forty character limit we set for branch names"
  local sanitized
  sanitized=$(_aw_sanitize_branch_name "$title" | cut -c1-40)
  local branch_name="work/${issue_id}-${sanitized}"

  run _aw_extract_issue_number "$branch_name"
  [ "$status" -eq 0 ]
  [ "$output" = "$issue_id" ]
}

@test "GitHub issue branch name format matches work/N-description pattern" {
  local issue_id="42"
  local title="Implement dark mode"
  local sanitized
  sanitized=$(_aw_sanitize_branch_name "$title" | cut -c1-40)
  local branch_name="work/${issue_id}-${sanitized}"

  # Branch must start with work/ prefix
  [[ "$branch_name" =~ ^work/ ]]
  # Branch must contain the issue number immediately after work/
  [[ "$branch_name" =~ ^work/[0-9]+ ]]
  # _aw_extract_issue_number must recover the original issue id
  run _aw_extract_issue_number "$branch_name"
  [ "$output" = "$issue_id" ]
}
