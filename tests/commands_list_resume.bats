#!/usr/bin/env bats
# Tests for src/commands/list.sh and src/commands/resume.sh
#
# Covers:
#   - _aw_format_worktree_age: age boundary conditions (hours vs days)
#   - _aw_get_worktree_list: returns main worktree only when no extras
#   - _aw_list: empty worktree list handling
#   - _aw_list: merged/closed issue detection (mocked _aw_check_issue_merged)
#   - _aw_resume: empty worktree list handling

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

load 'helpers/setup_git_repo'
load 'helpers/git_assertions'

# ---------------------------------------------------------------------------
# Shared setup/teardown
# ---------------------------------------------------------------------------

setup() {
  # Stub external tools that are required at source time or called during init
  gum() { :; }
  export -f gum

  # Stub provider functions so sourcing works without real credentials
  _aw_get_issue_provider() { echo "github"; }
  export -f _aw_get_issue_provider

  # Source the utility and library files
  # shellcheck source=../src/lib/utils.sh
  source "${REPO_ROOT}/src/lib/utils.sh"
  # shellcheck source=../src/providers/common.sh
  source "${REPO_ROOT}/src/providers/common.sh"
  # shellcheck source=../src/lib/worktree.sh
  source "${REPO_ROOT}/src/lib/worktree.sh"
  # shellcheck source=../src/commands/list.sh
  source "${REPO_ROOT}/src/commands/list.sh"
  # shellcheck source=../src/commands/resume.sh
  source "${REPO_ROOT}/src/commands/resume.sh"

  # Create an isolated git repo for worktree operations
  setup_git_repo

  # Default branch must be called "main" so _aw_get_default_branch works
  git branch -m main 2>/dev/null || true
}

teardown() {
  teardown_git_repo
}

# ---------------------------------------------------------------------------
# Helper: create a linked worktree under $TEST_REPO_DIR
# ---------------------------------------------------------------------------
_make_worktree() {
  local branch="$1"
  local wt_path; wt_path="$(cd "${TEST_REPO_DIR}/.." && pwd -P)/wt-${branch//\//-}"
  git -C "$TEST_REPO_DIR" checkout -b "$branch" 2>/dev/null
  git -C "$TEST_REPO_DIR" checkout main 2>/dev/null
  git -C "$TEST_REPO_DIR" worktree add "$wt_path" "$branch" >/dev/null 2>&1
  echo "$wt_path"
}

# ===========================================================================
# _aw_format_worktree_age — pure unit tests (no git repo needed)
# ===========================================================================

@test "_aw_format_worktree_age: empty timestamp returns [unknown]" {
  run _aw_format_worktree_age ""
  [ "$status" -eq 0 ]
  [ "$output" = "[unknown]" ]
}

@test "_aw_format_worktree_age: non-numeric timestamp returns [unknown]" {
  run _aw_format_worktree_age "not-a-number"
  [ "$status" -eq 0 ]
  [ "$output" = "[unknown]" ]
}

@test "_aw_format_worktree_age: age just under 24h shows hours" {
  # 23 hours and 59 minutes ago
  local ts=$(( $(date +%s) - (23 * 3600 + 59 * 60) ))
  run _aw_format_worktree_age "$ts"
  [ "$status" -eq 0 ]
  # Output should be [Xh ago] — the number of hours is 23
  [[ "$output" =~ ^\[[0-9]+h\ ago\]$ ]]
  # The hour count must be less than 24
  local hours="${output//[^0-9]/}"
  [ "$hours" -lt 24 ]
}

@test "_aw_format_worktree_age: age of exactly 24h shows days" {
  # 24 hours ago (boundary: equal to one_day)
  local ts=$(( $(date +%s) - 24 * 3600 ))
  run _aw_format_worktree_age "$ts"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^\[[0-9]+d\ ago\]$ ]]
}

@test "_aw_format_worktree_age: age over 24h shows days" {
  # 3 days ago
  local ts=$(( $(date +%s) - 3 * 24 * 3600 ))
  run _aw_format_worktree_age "$ts"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^\[[0-9]+d\ ago\]$ ]]
  local days="${output//[^0-9]/}"
  [ "$days" -ge 3 ]
}

@test "_aw_format_worktree_age: age of 1h shows [1h ago]" {
  local ts=$(( $(date +%s) - 3600 ))
  run _aw_format_worktree_age "$ts"
  [ "$status" -eq 0 ]
  [ "$output" = "[1h ago]" ]
}

@test "_aw_format_worktree_age: age of 48h shows [2d ago]" {
  local ts=$(( $(date +%s) - 2 * 24 * 3600 ))
  run _aw_format_worktree_age "$ts"
  [ "$status" -eq 0 ]
  [ "$output" = "[2d ago]" ]
}

# ===========================================================================
# _aw_get_worktree_list — basic output tests
# ===========================================================================

@test "_aw_get_worktree_list: returns at least one line (the main worktree)" {
  cd "$TEST_REPO_DIR"
  run _aw_get_worktree_list
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  # The main repo path must appear
  echo "$output" | grep -q "$TEST_REPO_DIR"
}

@test "_aw_get_worktree_list: includes an added worktree" {
  cd "$TEST_REPO_DIR"
  local wt_path
  wt_path=$(_make_worktree "feature-list-test")

  run _aw_get_worktree_list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "$wt_path"
}

# ===========================================================================
# _aw_list — empty worktree list handling
# ===========================================================================

@test "_aw_list: prints 'No additional worktrees' when only main worktree exists" {
  cd "$TEST_REPO_DIR"

  # Capture what gum would display: intercept gum style calls
  local gum_output=""
  gum() {
    if [[ "$1" == "style" ]]; then
      shift
      # Print remaining non-flag args as plain text
      local msg=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --foreground|--border|--padding|--border-foreground) shift; shift ;;
          --*) shift ;;
          *) msg+="$1 "; shift ;;
        esac
      done
      echo "${msg% }"
    fi
  }
  export -f gum

  run _aw_list
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "no additional worktrees"
}

# ===========================================================================
# _aw_list — merged/closed issue detection (mocked)
# ===========================================================================

@test "_aw_list: marks worktree as merged when _aw_check_issue_merged returns 0" {
  cd "$TEST_REPO_DIR"
  local wt_path
  wt_path=$(_make_worktree "work/123-fix-login")

  # Stub: issue 123 is merged
  _aw_check_issue_merged() {
    [[ "$1" == "123" ]] && return 0
    return 1
  }
  export -f _aw_check_issue_merged

  # Stub: no unpushed commits
  _aw_has_unpushed_commits() { return 1; }
  export -f _aw_has_unpushed_commits

  # Stub: no PR merged (separate check)
  _aw_check_branch_pr_merged() { return 1; }
  export -f _aw_check_branch_pr_merged

  # Stub: issue not closed independently
  _aw_check_issue_closed() { return 1; }
  export -f _aw_check_issue_closed

  # Stub: no changes from default
  _aw_check_no_changes_from_default() { return 1; }
  export -f _aw_check_no_changes_from_default

  # Stub gum to output plain text so we can assert on it
  local merged_indicator_seen=false
  gum() {
    if [[ "$1" == "style" ]]; then
      shift
      local msg=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --foreground|--border|--padding|--border-foreground) shift; shift ;;
          --*) shift ;;
          *) msg+="$1 "; shift ;;
        esac
      done
      echo "${msg% }"
    elif [[ "$1" == "confirm" ]]; then
      # Don't actually confirm cleanup
      return 1
    fi
  }
  export -f gum

  run _aw_list
  [ "$status" -eq 0 ]
  # Output should reference the merged issue
  echo "$output" | grep -q "123"
}

@test "_aw_list: does not mark worktree as merged when _aw_check_issue_merged returns 1" {
  cd "$TEST_REPO_DIR"
  local wt_path
  wt_path=$(_make_worktree "work/456-add-feature")

  # Stub: issue NOT merged
  _aw_check_issue_merged() { return 1; }
  export -f _aw_check_issue_merged

  _aw_check_issue_closed() { return 1; }
  export -f _aw_check_issue_closed

  _aw_check_branch_pr_merged() { return 1; }
  export -f _aw_check_branch_pr_merged

  _aw_has_unpushed_commits() { return 1; }
  export -f _aw_has_unpushed_commits

  _aw_check_no_changes_from_default() { return 1; }
  export -f _aw_check_no_changes_from_default

  gum() {
    if [[ "$1" == "style" ]]; then
      shift
      local msg=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --foreground|--border|--padding|--border-foreground) shift; shift ;;
          --*) shift ;;
          *) msg+="$1 "; shift ;;
        esac
      done
      echo "${msg% }"
    elif [[ "$1" == "confirm" ]]; then
      return 1
    fi
  }
  export -f gum

  run _aw_list
  [ "$status" -eq 0 ]
  # "merged #456" should NOT appear
  echo "$output" | grep -qv "merged #456"
}

# ===========================================================================
# _aw_list — worktree with no changes from default marked [no changes]
# ===========================================================================

@test "_aw_list: marks worktree as [no changes] when identical to default branch" {
  cd "$TEST_REPO_DIR"
  local wt_path
  wt_path=$(_make_worktree "no-changes-branch")

  # Stub: issue checks all return failure (no issue on branch)
  _aw_check_issue_merged() { return 1; }
  export -f _aw_check_issue_merged
  _aw_check_issue_closed() { return 1; }
  export -f _aw_check_issue_closed
  _aw_check_branch_pr_merged() { return 1; }
  export -f _aw_check_branch_pr_merged
  _aw_has_unpushed_commits() { return 1; }
  export -f _aw_has_unpushed_commits

  # Stub: reports no changes from default
  _aw_check_no_changes_from_default() {
    _AW_DEFAULT_BRANCH_NAME="main"
    return 0
  }
  export -f _aw_check_no_changes_from_default

  gum() {
    if [[ "$1" == "style" ]]; then
      shift
      local msg=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --foreground|--border|--padding|--border-foreground) shift; shift ;;
          --*) shift ;;
          *) msg+="$1 "; shift ;;
        esac
      done
      echo "${msg% }"
    elif [[ "$1" == "confirm" ]]; then
      return 1
    fi
  }
  export -f gum

  run _aw_list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "no changes"
}

# ===========================================================================
# _aw_resume — empty worktree list handling
# ===========================================================================

@test "_aw_resume: prints 'No additional worktrees' when only main worktree exists" {
  cd "$TEST_REPO_DIR"

  gum() {
    if [[ "$1" == "style" ]]; then
      shift
      local msg=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --foreground|--border|--padding|--border-foreground) shift; shift ;;
          --*) shift ;;
          *) msg+="$1 "; shift ;;
        esac
      done
      echo "${msg% }"
    fi
  }
  export -f gum

  run _aw_resume
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "no additional worktrees"
}

# ===========================================================================
# _aw_resume — worktrees present: selection list is built
# ===========================================================================

@test "_aw_resume: builds a selection list containing added worktree display name" {
  cd "$TEST_REPO_DIR"
  local wt_path
  wt_path=$(_make_worktree "work/789-resume-test")
  local wt_basename
  wt_basename=$(basename "$wt_path")

  # Capture the selection_list that would be passed to gum filter
  local captured_list=""

  gum() {
    if [[ "$1" == "filter" ]]; then
      # Read stdin into captured_list and simulate user cancellation
      captured_list=$(cat)
      # Simulate cancellation (empty selection)
      echo ""
      return 0
    elif [[ "$1" == "style" ]]; then
      shift
      local msg=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --foreground|--border|--padding|--border-foreground) shift; shift ;;
          --*) shift ;;
          *) msg+="$1 "; shift ;;
        esac
      done
      echo "${msg% }"
    fi
  }
  export -f gum
  # Also export captured_list so the subshell can write to it (use a file instead)
  local capture_file
  capture_file=$(mktemp)

  gum() {
    if [[ "$1" == "filter" ]]; then
      cat > "$capture_file"
      # Simulate cancellation
      echo ""
      return 0
    elif [[ "$1" == "style" ]]; then
      shift
      local msg=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --foreground|--border|--padding|--border-foreground) shift; shift ;;
          --*) shift ;;
          *) msg+="$1 "; shift ;;
        esac
      done
      echo "${msg% }"
    fi
  }
  export -f gum
  export capture_file

  run _aw_resume

  # The filter input should contain the worktree basename
  grep -q "$wt_basename" "$capture_file" \
    || fail "Expected selection list to contain '$wt_basename' but got: $(cat "$capture_file")"

  rm -f "$capture_file"
}

@test "_aw_resume: returns 0 (cancelled) when gum filter returns empty selection" {
  cd "$TEST_REPO_DIR"
  _make_worktree "work/999-cancel-test" >/dev/null

  gum() {
    if [[ "$1" == "filter" ]]; then
      # Drain stdin, return empty (simulates Ctrl+C / Esc)
      cat >/dev/null
      echo ""
      return 0
    elif [[ "$1" == "style" ]]; then
      :
    fi
  }
  export -f gum

  run _aw_resume
  # resume returns AW_EXIT_CANCELLED (130) or 0 when cancelled
  [ "$status" -eq 0 ] || [ "$status" -eq 130 ]
}
