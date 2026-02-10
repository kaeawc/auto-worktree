#!/bin/bash

# ============================================================================
# New worktree
# ============================================================================
_aw_new() {
  local skip_list="${1:-false}"

  _aw_ensure_git_repo || return 1
  _aw_get_repo_info
  _aw_prune_worktrees

  # Show existing worktrees (unless called from menu which already showed them)
  if [[ "$skip_list" == "false" ]]; then
    _aw_list
  fi

  echo ""

  local branch_input=$(gum input --placeholder "Branch name (leave blank for random)")

  local branch_name=""
  local worktree_name=""

  if [[ -z "$branch_input" ]]; then
    # Generate a unique random name
    local attempts=0
    local max_attempts=50
    while [[ $attempts -lt $max_attempts ]]; do
      worktree_name="$(_aw_generate_random_name)"
      branch_name="work/${worktree_name}"

      # Check if branch already exists
      if ! git show-ref --verify --quiet "refs/heads/${branch_name}" 2>/dev/null; then
        break  # Branch doesn't exist, we can use this name
      fi
      ((attempts++))
    done

    if [[ $attempts -ge $max_attempts ]]; then
      gum style --foreground 1 "Failed to generate unique branch name after $max_attempts attempts"
      gum style --foreground 3 "Try specifying a branch name manually"
      return 1
    fi

    gum style --foreground 6 "Generated: $branch_name"
  else
    branch_name="$branch_input"
  fi

  _aw_create_worktree "$branch_name"
}
