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

# ============================================================================
# Shared worktree helper utilities
# ============================================================================

_aw_get_worktree_list() {
  # Echo all worktree paths (one per line) from git worktree list
  git worktree list --porcelain 2>/dev/null | grep "^worktree " | sed 's/^worktree //'
}

_aw_get_worktree_timestamp() {
  # Echo a unix timestamp integer for the given worktree path.
  # Fallback chain: git log → git reflog → file mtime
  local wt_path="$1"
  local wt_branch="$2"

  local commit_timestamp
  commit_timestamp=$(git -C "$wt_path" log -1 --format=%ct 2>/dev/null)

  if [[ -z "$commit_timestamp" ]] || ! [[ "$commit_timestamp" =~ ^[0-9]+$ ]]; then
    # Try branch creation date from reflog (when the branch was first checked out/created)
    commit_timestamp=$(git -C "$wt_path" reflog show --format=%ct "$wt_branch" 2>/dev/null | tail -1)
  fi

  if [[ -z "$commit_timestamp" ]] || ! [[ "$commit_timestamp" =~ ^[0-9]+$ ]]; then
    commit_timestamp=$(find "$wt_path" -maxdepth 3 -type f -not -path '*/.git/*' -print0 2>/dev/null | while IFS= read -r -d '' file; do _aw_get_file_mtime "$file"; done | sort -rn | head -1)
  fi

  echo "$commit_timestamp"
}

_aw_format_worktree_age() {
  # Takes a unix timestamp, returns a human-readable age string like "[3d ago]" or "[14h ago]"
  # If timestamp is empty or non-numeric, returns "[unknown]"
  local timestamp="$1"
  local now
  now=$(date +%s)
  local one_day=$((24 * 60 * 60))

  if [[ -z "$timestamp" ]] || ! [[ "$timestamp" =~ ^[0-9]+$ ]]; then
    echo "[unknown]"
    return
  fi

  local age=$((now - timestamp))
  local age_days=$((age / one_day))
  local age_hours=$((age / 3600))

  if [[ $age -lt $one_day ]]; then
    echo "[${age_hours}h ago]"
  else
    echo "[${age_days}d ago]"
  fi
}

_aw_find_worktree_for_issue() {
  # Search all worktrees for one matching the given issue ID and provider.
  # Echoes the matching worktree path, or returns 1 if not found.
  # Usage: _aw_find_worktree_for_issue issue_id provider
  local issue_id="$1"
  local provider="$2"

  local worktree_list
  worktree_list=$(_aw_get_worktree_list)

  if [[ -z "$worktree_list" ]]; then
    return 1
  fi

  while IFS= read -r wt_path; do
    if [[ -d "$wt_path" ]]; then
      local wt_branch
      wt_branch=$(git -C "$wt_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
      if [[ -n "$wt_branch" ]]; then
        local wt_issue=""
        if [[ "$provider" == "jira" ]]; then
          wt_issue=$(_aw_extract_jira_key "$wt_branch")
        elif [[ "$provider" == "linear" ]]; then
          wt_issue=$(_aw_extract_linear_key "$wt_branch")
        else
          wt_issue=$(_aw_extract_issue_number "$wt_branch")
        fi
        if [[ "$wt_issue" == "$issue_id" ]]; then
          echo "$wt_path"
          return 0
        fi
      fi
    fi
  done <<< "$worktree_list"

  return 1
}

_aw_remove_worktree_and_branch() {
  # Remove a worktree and optionally delete its branch.
  # Usage: _aw_remove_worktree_and_branch worktree_path branch_name
  # Returns 1 if the worktree removal fails.
  local worktree_path="$1"
  local branch_name="${2:-}"

  echo ""
  if ! gum spin --spinner dot --title "Removing $(basename "$worktree_path")..." -- git worktree remove --force "$worktree_path"; then
    gum style --foreground 1 "Error: Failed to remove worktree: $worktree_path"
    return 1
  fi

  gum style --foreground 2 "✓ Worktree removed: $(basename "$worktree_path")"

  if [[ -n "$branch_name" ]] && git show-ref --verify --quiet "refs/heads/${branch_name}"; then
    git branch -D "$branch_name" 2>/dev/null
    gum style --foreground 2 "✓ Branch deleted: $branch_name"
  fi
}
