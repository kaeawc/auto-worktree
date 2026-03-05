#!/usr/bin/env bats
# Tests for helper functions in src/lib/worktree.sh

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

load 'helpers/setup_git_repo'
load 'helpers/git_assertions'

setup() {
  setup_git_repo

  # Stub gum so worktree.sh functions don't require the binary.
  # gum spin --title ... -- <cmd>  must actually execute <cmd>.
  gum() {
    case "$1" in
      spin)
        # Parse: gum spin [flags] -- cmd [args...]
        # Find the '--' separator and execute everything after it.
        local found_sep=0
        shift  # drop "spin"
        while [[ $# -gt 0 ]]; do
          if [[ "$1" == "--" ]]; then
            found_sep=1
            shift
            break
          fi
          shift
        done
        if [[ "$found_sep" -eq 1 ]] && [[ $# -gt 0 ]]; then
          "$@"
          return $?
        fi
        return 0
        ;;
      style)
        # Print remaining args to stdout (so callers can inspect output)
        shift
        # Strip flag pairs (--foreground N, --border X, etc.)
        while [[ $# -gt 0 ]]; do
          case "$1" in
            --foreground|--border|--padding|--border-foreground)
              shift 2
              ;;
            --*)
              shift
              ;;
            *)
              echo "$1"
              shift
              ;;
          esac
        done
        ;;
      *)
        return 0
        ;;
    esac
  }
  export -f gum

  # Source dependencies that worktree.sh relies on (extraction helpers, mtime).
  # shellcheck source=../src/lib/utils.sh
  source "${REPO_ROOT}/src/lib/utils.sh"
  # shellcheck source=../src/providers/common.sh
  source "${REPO_ROOT}/src/providers/common.sh"
  # shellcheck source=../src/lib/worktree.sh
  source "${REPO_ROOT}/src/lib/worktree.sh"
}

teardown() {
  teardown_git_repo
}

# ============================================================================
# _aw_get_worktree_list
# ============================================================================

@test "_aw_get_worktree_list: lists main worktree path" {
  run _aw_get_worktree_list
  [ "$status" -eq 0 ]
  # The main worktree (TEST_REPO_DIR) must appear in the list.
  echo "$output" | grep -qF "$TEST_REPO_DIR"
}

@test "_aw_get_worktree_list: returns additional worktree paths when they exist" {
  local wt_path="${TEST_REPO_DIR}-wt-extra"
  git -C "$TEST_REPO_DIR" worktree add -b extra-branch "$wt_path"

  run _aw_get_worktree_list
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "$wt_path"

  # Cleanup
  git -C "$TEST_REPO_DIR" worktree remove --force "$wt_path" 2>/dev/null || true
  git -C "$TEST_REPO_DIR" branch -D extra-branch 2>/dev/null || true
}

@test "_aw_get_worktree_list: returns one path per line" {
  local wt_path="${TEST_REPO_DIR}-wt-multiline"
  git -C "$TEST_REPO_DIR" worktree add -b multiline-branch "$wt_path"

  run _aw_get_worktree_list
  [ "$status" -eq 0 ]
  # Each line should look like an absolute path (no leading spaces, no extra fields).
  while IFS= read -r line; do
    [[ "$line" = /* ]] || fail "Expected absolute path, got: $line"
  done <<< "$output"

  # Cleanup
  git -C "$TEST_REPO_DIR" worktree remove --force "$wt_path" 2>/dev/null || true
  git -C "$TEST_REPO_DIR" branch -D multiline-branch 2>/dev/null || true
}

# ============================================================================
# _aw_get_worktree_timestamp
# ============================================================================

@test "_aw_get_worktree_timestamp: returns a non-empty integer for a repo with commits" {
  # TEST_REPO_DIR already has an initial commit from setup_git_repo.
  local branch
  branch=$(git -C "$TEST_REPO_DIR" rev-parse --abbrev-ref HEAD)

  run _aw_get_worktree_timestamp "$TEST_REPO_DIR" "$branch"
  [ "$status" -eq 0 ]
  [[ -n "$output" ]] || fail "Expected non-empty timestamp"
  [[ "$output" =~ ^[0-9]+$ ]] || fail "Expected numeric timestamp, got: $output"
}

@test "_aw_get_worktree_timestamp: returns a positive integer greater than zero" {
  local branch
  branch=$(git -C "$TEST_REPO_DIR" rev-parse --abbrev-ref HEAD)

  run _aw_get_worktree_timestamp "$TEST_REPO_DIR" "$branch"
  [ "$status" -eq 0 ]
  [[ "$output" -gt 0 ]] || fail "Expected timestamp > 0, got: $output"
}

@test "_aw_get_worktree_timestamp: falls back gracefully when git log has no commits (new orphan branch)" {
  # Create a worktree on a new orphan branch so git log returns nothing.
  local wt_path="${TEST_REPO_DIR}-wt-orphan"
  git -C "$TEST_REPO_DIR" worktree add --orphan -b orphan-branch "$wt_path"

  # Run the function — it should not crash; output may be empty or a number.
  run _aw_get_worktree_timestamp "$wt_path" "orphan-branch"
  # Status 0 is expected (function always echoes something or nothing silently).
  [ "$status" -eq 0 ]

  # Cleanup
  git -C "$TEST_REPO_DIR" worktree remove --force "$wt_path" 2>/dev/null || true
  git -C "$TEST_REPO_DIR" branch -D orphan-branch 2>/dev/null || true
}

# ============================================================================
# _aw_format_worktree_age
# ============================================================================

@test "_aw_format_worktree_age: returns [Xh ago] for a timestamp less than 24h ago" {
  local now
  now=$(date +%s)
  local two_hours_ago=$(( now - 7200 ))

  run _aw_format_worktree_age "$two_hours_ago"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^\[[0-9]+h\ ago\]$ ]] || fail "Expected [Xh ago] format, got: $output"
}

@test "_aw_format_worktree_age: returns [Xd ago] for a timestamp more than 24h ago" {
  local now
  now=$(date +%s)
  local three_days_ago=$(( now - 259200 ))  # 3 * 24 * 3600

  run _aw_format_worktree_age "$three_days_ago"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^\[[0-9]+d\ ago\]$ ]] || fail "Expected [Xd ago] format, got: $output"
}

@test "_aw_format_worktree_age: returns [unknown] for empty input" {
  run _aw_format_worktree_age ""
  [ "$status" -eq 0 ]
  [ "$output" = "[unknown]" ]
}

@test "_aw_format_worktree_age: returns [unknown] for non-numeric input" {
  run _aw_format_worktree_age "not-a-timestamp"
  [ "$status" -eq 0 ]
  [ "$output" = "[unknown]" ]
}

@test "_aw_format_worktree_age: hour count matches expected value" {
  local now
  now=$(date +%s)
  local five_hours_ago=$(( now - 18000 ))  # 5 * 3600

  run _aw_format_worktree_age "$five_hours_ago"
  [ "$status" -eq 0 ]
  [ "$output" = "[5h ago]" ]
}

@test "_aw_format_worktree_age: day count matches expected value" {
  local now
  now=$(date +%s)
  local seven_days_ago=$(( now - 604800 ))  # 7 * 24 * 3600

  run _aw_format_worktree_age "$seven_days_ago"
  [ "$status" -eq 0 ]
  [ "$output" = "[7d ago]" ]
}

# ============================================================================
# _aw_find_worktree_for_issue
# ============================================================================

@test "_aw_find_worktree_for_issue: finds a worktree whose branch contains the issue number" {
  local wt_path="${TEST_REPO_DIR}-wt-123"
  git -C "$TEST_REPO_DIR" worktree add -b "work/123-fix-bug" "$wt_path"

  run _aw_find_worktree_for_issue "123" "github"
  [ "$status" -eq 0 ]
  [ "$output" = "$wt_path" ]

  # Cleanup
  git -C "$TEST_REPO_DIR" worktree remove --force "$wt_path" 2>/dev/null || true
  git -C "$TEST_REPO_DIR" branch -D "work/123-fix-bug" 2>/dev/null || true
}

@test "_aw_find_worktree_for_issue: returns 1 with no output when no matching worktree exists" {
  run _aw_find_worktree_for_issue "9999" "github"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "_aw_find_worktree_for_issue: works for jira provider with KEY-123 format" {
  local wt_path="${TEST_REPO_DIR}-wt-jira"
  git -C "$TEST_REPO_DIR" worktree add -b "work/PROJ-42-implement-feature" "$wt_path"

  run _aw_find_worktree_for_issue "PROJ-42" "jira"
  [ "$status" -eq 0 ]
  [ "$output" = "$wt_path" ]

  # Cleanup
  git -C "$TEST_REPO_DIR" worktree remove --force "$wt_path" 2>/dev/null || true
  git -C "$TEST_REPO_DIR" branch -D "work/PROJ-42-implement-feature" 2>/dev/null || true
}

@test "_aw_find_worktree_for_issue: does not match a different issue number" {
  local wt_path="${TEST_REPO_DIR}-wt-456"
  git -C "$TEST_REPO_DIR" worktree add -b "work/456-other-issue" "$wt_path"

  run _aw_find_worktree_for_issue "789" "github"
  [ "$status" -eq 1 ]
  [ -z "$output" ]

  # Cleanup
  git -C "$TEST_REPO_DIR" worktree remove --force "$wt_path" 2>/dev/null || true
  git -C "$TEST_REPO_DIR" branch -D "work/456-other-issue" 2>/dev/null || true
}

# ============================================================================
# _aw_remove_worktree_and_branch
# ============================================================================

@test "_aw_remove_worktree_and_branch: successfully removes a real worktree and branch" {
  local wt_path="${TEST_REPO_DIR}-wt-remove-me"
  git -C "$TEST_REPO_DIR" worktree add -b "remove-me-branch" "$wt_path"

  assert_worktree_exists "$wt_path"
  assert_branch_exists "remove-me-branch"

  run _aw_remove_worktree_and_branch "$wt_path" "remove-me-branch"
  [ "$status" -eq 0 ]

  assert_no_worktree "$wt_path"
  assert_branch_not_exists "remove-me-branch"
}

@test "_aw_remove_worktree_and_branch: returns 1 when worktree path does not exist" {
  local fake_path="${TEST_REPO_DIR}-wt-nonexistent"

  run _aw_remove_worktree_and_branch "$fake_path" "some-branch"
  [ "$status" -eq 1 ]
}

@test "_aw_remove_worktree_and_branch: does not print success message when removal fails" {
  local fake_path="${TEST_REPO_DIR}-wt-no-such-path"

  run _aw_remove_worktree_and_branch "$fake_path" "no-such-branch"
  [ "$status" -eq 1 ]
  # The worktree-removed success line should NOT appear in output.
  echo "$output" | grep -qv "Worktree removed" || true
  # Specifically: output must NOT contain the success checkmark message.
  [[ "$output" != *"Worktree removed"* ]] || fail "Success message should not appear on failure"
}

@test "_aw_remove_worktree_and_branch: removes worktree but skips branch deletion when branch name is empty" {
  local wt_path="${TEST_REPO_DIR}-wt-no-branch-arg"
  git -C "$TEST_REPO_DIR" worktree add -b "keep-this-branch" "$wt_path"

  run _aw_remove_worktree_and_branch "$wt_path" ""
  [ "$status" -eq 0 ]

  assert_no_worktree "$wt_path"
  # Branch should still exist since we passed an empty branch name.
  assert_branch_exists "keep-this-branch"

  # Cleanup the branch we intentionally kept.
  git -C "$TEST_REPO_DIR" branch -D "keep-this-branch" 2>/dev/null || true
}
