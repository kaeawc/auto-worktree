#!/bin/bash

# ============================================================================
# Worktree creation and unpushed commit checking
# ============================================================================
_aw_has_unpushed_commits() {
  # Check if a worktree has unpushed commits
  # Returns 0 if there are unpushed commits, 1 if not
  # Sets _AW_UNPUSHED_COUNT to the number of unpushed commits
  local wt_path="$1"

  if [[ -z "$wt_path" ]] || [[ ! -d "$wt_path" ]]; then
    return 1
  fi

  # Get the current branch
  local branch=$(git -C "$wt_path" rev-parse --abbrev-ref HEAD 2>/dev/null)

  if [[ -z "$branch" ]] || [[ "$branch" == "HEAD" ]]; then
    # Detached HEAD state, no upstream to compare
    return 1
  fi

  # Get the upstream branch
  local upstream=$(git -C "$wt_path" rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)

  if [[ -z "$upstream" ]]; then
    # No upstream configured - check if there are any commits at all
    local commit_count=$(git -C "$wt_path" rev-list --count HEAD 2>/dev/null)
    if [[ "$commit_count" -gt 0 ]] 2>/dev/null; then
      _AW_UNPUSHED_COUNT=$commit_count
      return 0
    else
      return 1
    fi
  fi

  # Count commits ahead of upstream
  local ahead=$(git -C "$wt_path" rev-list --count @{u}..HEAD 2>/dev/null)

  if [[ "$ahead" -gt 0 ]] 2>/dev/null; then
    _AW_UNPUSHED_COUNT=$ahead
    return 0
  fi

  return 1
}

_aw_create_worktree() {
  local branch_name="$1"
  local initial_context="${2:-}"
  local worktree_name=$(_aw_sanitize_branch_name "$branch_name")
  local worktree_path="$_AW_WORKTREE_BASE/$worktree_name"

  mkdir -p "$_AW_WORKTREE_BASE"

  # Check if branch already exists
  local branch_exists=false
  if git show-ref --verify --quiet "refs/heads/${branch_name}"; then
    branch_exists=true
    local existing_worktree=$(git worktree list --porcelain | grep -A2 "^worktree " | grep -B1 "branch refs/heads/${branch_name}$" | head -1 | sed 's/^worktree //')
    if [[ -n "$existing_worktree" ]]; then
      gum style --foreground 1 "Error: Branch '${branch_name}' already has a worktree at:"
      echo "  $existing_worktree"
      return 1
    fi
    gum style --foreground 3 "Branch '${branch_name}' exists, creating worktree for it..."
  fi

  local base_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")

  echo ""
  gum style --border rounded --padding "0 1" --border-foreground 4 \
    "Creating worktree" \
    "  Path:   $worktree_path" \
    "  Branch: $branch_name" \
    $([[ "$branch_exists" == "false" ]] && echo "  Base:   $base_branch")

  local worktree_cmd_success=false
  if [[ "$branch_exists" == "true" ]]; then
    if gum spin --spinner dot --title "Creating worktree..." -- git worktree add "$worktree_path" "$branch_name"; then
      worktree_cmd_success=true
    fi
  else
    if gum spin --spinner dot --title "Creating worktree..." -- git worktree add -b "$branch_name" "$worktree_path" "$base_branch"; then
      worktree_cmd_success=true
    fi
  fi

  if [[ "$worktree_cmd_success" == "true" ]]; then
    # Set up the development environment
    _aw_setup_environment "$worktree_path"

    cd "$worktree_path" || return 1

    # Set terminal title to branch name
    printf '\033]0;%s\007' "$branch_name"

    _resolve_ai_command || return 1

    if [[ "${AI_CMD[1]}" != "skip" ]]; then
      gum style --foreground 2 "Starting $AI_CMD_NAME..."
      if [[ -n "$initial_context" ]]; then
        "${AI_CMD[@]}" "$initial_context"
      else
        "${AI_CMD[@]}"
      fi
    else
      gum style --foreground 3 "Skipping AI tool - worktree is ready for manual work"
    fi
  else
    gum style --foreground 1 "Failed to create worktree"
    return 1
  fi
}
