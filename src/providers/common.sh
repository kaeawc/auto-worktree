#!/bin/bash

# ============================================================================
# Issue extraction, merged/closed checks, default branch detection
# ============================================================================
#
# Canonical issue list output format:
# <ID> | <Title> [ | [label1][label2]]
# Where ID is: #123 (GitHub/GitLab), KEY-123 (JIRA/Linear)

_aw_format_labels() {
  local labels="$1"
  [[ -z "$labels" ]] && return 0
  # Split on comma or pipe, wrap each in brackets, join
  echo "$labels" | tr ',|' '\n' | sed 's/^ *//;s/ *$//' | grep -v '^$' | sed 's/^/[/;s/$/]/' | tr -d '\n'
  echo  # trailing newline
}

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
  echo "$branch" | grep -oE '[A-Z][A-Z0-9]*-[0-9]+' | head -1
}

_aw_extract_linear_key() {
  # Extract Linear key from branch name patterns like:
  # work/TEAM-123-description, TEAM-456-fix-something
  # Linear keys are typically TEAM-NUMBER format (similar to JIRA)
  local branch="$1"
  echo "$branch" | grep -oE '[A-Z][A-Z0-9]*-[0-9]+' | head -1
}

_aw_extract_issue_id_from_branch() {
  # Dispatch to the correct extractor based on provider
  local branch="$1"
  local provider="$2"

  if [[ "$provider" == "jira" ]]; then
    _aw_extract_jira_key "$branch"
  elif [[ "$provider" == "linear" ]]; then
    _aw_extract_linear_key "$branch"
  else
    _aw_extract_issue_number "$branch"
  fi
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
    elif [[ -z "$provider" ]]; then
      # No provider configured but branch matches JIRA/Linear pattern — warn and assume JIRA
      gum style --foreground 3 "Warning: branch '$branch' looks like a JIRA/Linear key but no issue provider is configured. Assuming JIRA. Set AW_ISSUE_PROVIDER to suppress this warning." >&2
      _AW_DETECTED_ISSUE_TYPE="jira"
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
  # Dispatches to the provider-specific implementation.
  local issue_id="$1"
  local provider="${2:-$(_aw_get_issue_provider)}"

  if [[ -z "$issue_id" ]]; then
    return 1
  fi

  case "$provider" in
    github)  _aw_github_check_issue_merged "$issue_id" ;;
    gitlab)  _aw_gitlab_check_closed "$issue_id" ;;
    jira)    _aw_jira_check_resolved "$issue_id" ;;
    linear)  _aw_linear_check_completed "$issue_id" ;;
    *)       return 1 ;;
  esac
}

_aw_check_issue_closed() {
  # Check if an issue is closed (regardless of merge/PR status)
  # Returns 0 if closed, 1 if open or error
  # Sets _AW_ISSUE_HAS_PR=true if there's an open PR for this issue (GitHub only)
  # Dispatches to the provider-specific implementation.
  local issue_id="$1"
  local provider="${2:-$(_aw_get_issue_provider)}"

  if [[ -z "$issue_id" ]]; then
    return 1
  fi

  case "$provider" in
    github)  _aw_github_check_closed "$issue_id" ;;
    gitlab)  _aw_gitlab_check_closed "$issue_id" ;;
    jira)    _aw_jira_check_resolved "$issue_id" ;;
    linear)  _aw_linear_check_completed "$issue_id" ;;
    *)       return 1 ;;
  esac
}

_aw_check_branch_pr_merged() {
  # Check if the branch itself has a merged PR (regardless of issue linkage)
  # Returns 0 if merged, 1 if not
  # For JIRA/Linear (issue trackers with no native PR concept), falls back to
  # checking whether the branch has been merged into the default branch via git.
  # Dispatches to the provider-specific implementation.
  local branch_name="$1"
  local provider="${2:-$(_aw_get_issue_provider)}"

  if [[ -z "$branch_name" ]]; then
    return 1
  fi

  case "$provider" in
    github)  _aw_github_check_branch_pr_merged "$branch_name" ;;
    gitlab)  _aw_gitlab_check_mr_merged "$branch_name" ;;
    jira|linear)
      # JIRA/Linear don't host PRs — check if the branch is merged into default via git
      local default_branch
      default_branch=$(_aw_get_default_branch)
      if [[ -z "$default_branch" ]]; then
        return 1
      fi
      # Returns 0 if branch_name is an ancestor of (i.e. merged into) default_branch
      git merge-base --is-ancestor "$branch_name" "$default_branch" 2>/dev/null
      ;;
    *)       return 1 ;;
  esac
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

_aw_milestone_terminology() {
  # Return the provider-specific term for milestones
  # GitHub/GitLab = "Milestone", JIRA = "Epic", Linear = "Project"
  local provider="$1"

  case "$provider" in
    jira)   echo "Epic" ;;
    linear) echo "Project" ;;
    *)      echo "Milestone" ;;
  esac
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
