#!/bin/bash

# ============================================================================
# Issue extraction, merged/closed checks, default branch detection
# ============================================================================
_aw_extract_issue_number() {
  # Extract issue number from branch name patterns like:
  # work/123-description, issue-123, 123-fix-something
  local branch="$1"
  echo "$branch" | grep -oE '(^|[^0-9])([0-9]+)' | head -1 | grep -oE '[0-9]+' | head -1
}

_aw_extract_jira_key() {
  # Extract JIRA key from branch name patterns like:
  # work/PROJ-123-description, PROJ-456-fix-something
  # JIRA keys are typically PROJECT-NUMBER format
  local branch="$1"
  echo "$branch" | grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | head -1
}

_aw_extract_linear_key() {
  # Extract Linear key from branch name patterns like:
  # work/TEAM-123-description, TEAM-456-fix-something
  # Linear keys are typically TEAM-NUMBER format (similar to JIRA)
  local branch="$1"
  echo "$branch" | grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | head -1
}

_aw_extract_issue_id() {
  # Extract either GitHub/GitLab issue number, JIRA key, or Linear key from branch name
  # Returns the ID and sets _AW_DETECTED_ISSUE_TYPE to "github", "gitlab", "jira", or "linear"
  local branch="$1"

  # Check configured provider first to disambiguate JIRA vs Linear
  # Both use the same pattern: TEAM-123
  local provider=$(_aw_get_issue_provider)

  # Try JIRA/Linear key first (more specific pattern)
  local key=$(_aw_extract_jira_key "$branch")
  if [[ -n "$key" ]]; then
    if [[ "$provider" == "linear" ]]; then
      _AW_DETECTED_ISSUE_TYPE="linear"
    else
      # Default to jira if pattern matches (for backwards compatibility)
      _AW_DETECTED_ISSUE_TYPE="jira"
    fi
    echo "$key"
    return 0
  fi

  # Try GitHub/GitLab issue number
  # Both use numeric IDs, so we rely on configured provider to distinguish
  local issue_num=$(_aw_extract_issue_number "$branch")
  if [[ -n "$issue_num" ]]; then
    # Check configured provider to determine type
    if [[ "$provider" == "gitlab" ]]; then
      _AW_DETECTED_ISSUE_TYPE="gitlab"
    else
      _AW_DETECTED_ISSUE_TYPE="github"
    fi
    echo "$issue_num"
    return 0
  fi

  _AW_DETECTED_ISSUE_TYPE=""
  return 1
}

_aw_check_issue_merged() {
  # Check if an issue or its linked PR was merged into main
  # Returns 0 if merged, 1 if not merged or error
  local issue_num="$1"

  if [[ -z "$issue_num" ]]; then
    return 1
  fi

  # First check if issue is closed
  local issue_state=$(gh issue view "$issue_num" --json state --jq '.state' 2>/dev/null)

  if [[ "$issue_state" != "CLOSED" ]]; then
    return 1
  fi

  # Check if there's a linked PR that was merged
  # GitHub's stateReason can tell us if it was completed (often means PR merged)
  local state_reason=$(gh issue view "$issue_num" --json stateReason --jq '.stateReason' 2>/dev/null)

  if [[ "$state_reason" == "COMPLETED" ]]; then
    return 0
  fi

  # Also check for PRs that reference this issue and are merged
  local merged_prs=$(gh pr list --state merged --search "closes #$issue_num OR fixes #$issue_num OR resolves #$issue_num" --json number --jq 'length' 2>/dev/null)

  if [[ "$merged_prs" -gt 0 ]] 2>/dev/null; then
    return 0
  fi

  return 1
}

_aw_check_issue_closed() {
  # Check if an issue is closed (regardless of merge/PR status)
  # Returns 0 if closed, 1 if open or error
  # Sets _AW_ISSUE_HAS_PR=true if there's an open PR for this issue
  local issue_num="$1"

  if [[ -z "$issue_num" ]]; then
    return 1
  fi

  # Check if issue is closed
  local issue_state=$(gh issue view "$issue_num" --json state --jq '.state' 2>/dev/null)

  if [[ "$issue_state" != "CLOSED" ]]; then
    return 1
  fi

  # Check if there's an open PR that references this issue
  local open_prs=$(gh pr list --state open --search "closes #$issue_num OR fixes #$issue_num OR resolves #$issue_num" --json number --jq 'length' 2>/dev/null)

  if [[ "$open_prs" -gt 0 ]] 2>/dev/null; then
    _AW_ISSUE_HAS_PR=true
  else
    _AW_ISSUE_HAS_PR=false
  fi

  return 0
}

_aw_check_branch_pr_merged() {
  # Check if the branch itself has a merged PR (regardless of issue linkage)
  # Returns 0 if merged, 1 if not
  local branch_name="$1"

  if [[ -z "$branch_name" ]]; then
    return 1
  fi

  # Check if there's a merged PR for this branch
  local pr_state=$(gh pr view "$branch_name" --json state,mergedAt --jq '.state' 2>/dev/null)

  if [[ "$pr_state" == "MERGED" ]]; then
    return 0
  fi

  return 1
}

_aw_get_default_branch() {
  # Detect the default branch (main or master)
  # Returns the branch name or empty string if not found

  # First try to get from remote
  local default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')

  if [[ -n "$default_branch" ]]; then
    echo "$default_branch"
    return 0
  fi

  # Fallback: check if main or master exists locally
  if git show-ref --verify --quiet refs/heads/main 2>/dev/null; then
    echo "main"
    return 0
  elif git show-ref --verify --quiet refs/heads/master 2>/dev/null; then
    echo "master"
    return 0
  fi

  # Last resort: try to get from remote branches
  if git show-ref --verify --quiet refs/remotes/origin/main 2>/dev/null; then
    echo "main"
    return 0
  elif git show-ref --verify --quiet refs/remotes/origin/master 2>/dev/null; then
    echo "master"
    return 0
  fi

  return 1
}

_aw_check_no_changes_from_default() {
  # Check if a worktree has no changes from the default branch HEAD
  # Returns 0 if no changes, 1 otherwise
  # Sets _AW_DEFAULT_BRANCH_NAME global variable
  local wt_path="$1"

  if [[ -z "$wt_path" ]] || [[ ! -d "$wt_path" ]]; then
    return 1
  fi

  # Get default branch name
  _AW_DEFAULT_BRANCH_NAME=$(_aw_get_default_branch)

  if [[ -z "$_AW_DEFAULT_BRANCH_NAME" ]]; then
    return 1
  fi

  # Get the current branch of the worktree
  local wt_branch=$(git -C "$wt_path" rev-parse --abbrev-ref HEAD 2>/dev/null)

  # Don't check if this IS the default branch
  if [[ "$wt_branch" == "$_AW_DEFAULT_BRANCH_NAME" ]]; then
    return 1
  fi

  # Get the commit hash of the worktree HEAD
  local wt_head=$(git -C "$wt_path" rev-parse HEAD 2>/dev/null)

  # Get the commit hash of the default branch HEAD
  local default_head=$(git rev-parse "$_AW_DEFAULT_BRANCH_NAME" 2>/dev/null)

  if [[ -z "$wt_head" ]] || [[ -z "$default_head" ]]; then
    return 1
  fi

  # Check if they're the same
  if [[ "$wt_head" == "$default_head" ]]; then
    return 0
  fi

  return 1
}
