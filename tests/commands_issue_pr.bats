#!/usr/bin/env bats
# Tests for issue/PR selection and validation helpers
# Covers:
#   - _aw_extract_id_from_selection (with active-worktree ● prefix)
#   - _aw_validate_worktree_path (skips main git root and non-existent dirs)

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

load 'helpers/setup_git_repo'
load 'helpers/git_assertions'

setup() {
  setup_git_repo

  # Stub gum so sourced files don't require the binary.
  gum() { return 0; }
  export -f gum

  # Source dependencies
  # shellcheck source=../src/lib/utils.sh
  source "${REPO_ROOT}/src/lib/utils.sh"
  # shellcheck source=../src/providers/common.sh
  source "${REPO_ROOT}/src/providers/common.sh"
  # shellcheck source=../src/lib/worktree.sh
  source "${REPO_ROOT}/src/lib/worktree.sh"
  # shellcheck source=../src/lib/config.sh
  source "${REPO_ROOT}/src/lib/config.sh"

  # Point _AW_GIT_ROOT at the isolated test repo
  _AW_GIT_ROOT="$TEST_REPO_DIR"

  cd "$TEST_REPO_DIR"
}

teardown() {
  teardown_git_repo
}

# ============================================================================
# _aw_extract_id_from_selection — active-worktree (●) prefix variants
# ============================================================================

@test "_aw_extract_id_from_selection: strips ● prefix and # sigil from GitHub-style entry" {
  run _aw_extract_id_from_selection "● #123 | Fix login bug"
  [ "$status" -eq 0 ]
  [ "$output" = "123" ]
}

@test "_aw_extract_id_from_selection: strips ● prefix from Jira-style key" {
  run _aw_extract_id_from_selection "● KEY-456 | Implement feature"
  [ "$status" -eq 0 ]
  [ "$output" = "KEY-456" ]
}

@test "_aw_extract_id_from_selection: handles entry without ● prefix and with # sigil" {
  run _aw_extract_id_from_selection "#789 | Other issue"
  [ "$status" -eq 0 ]
  [ "$output" = "789" ]
}

@test "_aw_extract_id_from_selection: handles Linear-style key with ● prefix" {
  run _aw_extract_id_from_selection "● ENG-999 | Linear task"
  [ "$status" -eq 0 ]
  [ "$output" = "ENG-999" ]
}

# ============================================================================
# _aw_validate_worktree_path — main git root is rejected
# ============================================================================

@test "_aw_validate_worktree_path: returns 1 when path equals _AW_GIT_ROOT (main worktree)" {
  run _aw_validate_worktree_path "$_AW_GIT_ROOT"
  [ "$status" -eq 1 ]
}

# ============================================================================
# _aw_validate_worktree_path — non-existent directories are rejected
# ============================================================================

@test "_aw_validate_worktree_path: returns 1 for a path that does not exist on disk" {
  local missing_path="${TEST_REPO_DIR}-does-not-exist-$(date +%s)"
  run _aw_validate_worktree_path "$missing_path"
  [ "$status" -eq 1 ]
}

@test "_aw_validate_worktree_path: returns 0 for a real non-main worktree directory" {
  local wt_path="${TEST_REPO_DIR}-wt-issue-pr"
  git -C "$TEST_REPO_DIR" worktree add -b "issue-pr-branch" "$wt_path"

  run _aw_validate_worktree_path "$wt_path"
  [ "$status" -eq 0 ]

  # Cleanup
  git -C "$TEST_REPO_DIR" worktree remove --force "$wt_path" 2>/dev/null || true
  git -C "$TEST_REPO_DIR" branch -D "issue-pr-branch" 2>/dev/null || true
}
