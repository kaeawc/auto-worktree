#!/bin/bash

# ============================================================================
# Resume worktree
# ============================================================================
_aw_resume() {
  _aw_ensure_git_repo || return 1
  _aw_get_repo_info
  _aw_prune_worktrees

  local worktree_list=$(_aw_get_worktree_list)
  local worktree_count=$(echo "$worktree_list" | grep -c . 2>/dev/null || echo 0)

  if [[ $worktree_count -le 1 ]]; then
    gum style --foreground 8 "No additional worktrees for $_AW_SOURCE_FOLDER"
    return 0
  fi

  # Build selection list with formatted display
  local -a worktree_paths=()
  local -a worktree_displays=()

  while IFS= read -r wt_path; do
    [[ "$wt_path" == "$_AW_GIT_ROOT" ]] && continue
    [[ ! -d "$wt_path" ]] && continue

    local wt_branch=$(git -C "$wt_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    local commit_timestamp=$(_aw_get_worktree_timestamp "$wt_path" "$wt_branch")

    # Build display string
    local age_str=$(_aw_format_worktree_age "$commit_timestamp")
    local display="$(basename "$wt_path") ($wt_branch) $age_str"

    worktree_paths+=("$wt_path")
    worktree_displays+=("$display")
  done <<< "$worktree_list"

  if [[ ${#worktree_paths[@]} -eq 0 ]]; then
    gum style --foreground 8 "No additional worktrees for $_AW_SOURCE_FOLDER"
    return 0
  fi

  echo ""
  gum style --border rounded --padding "0 1" --border-foreground 4 \
    "Resume a worktree for $_AW_SOURCE_FOLDER"
  echo ""

  # Create selection string from displays
  local selection_list=""
  local i=1
  while [[ $i -le ${#worktree_displays[@]} ]]; do
    selection_list+="${worktree_displays[$i]}"
    if [[ $i -lt ${#worktree_displays[@]} ]]; then
      selection_list+=$'\n'
    fi
    ((i++))
  done

  local selected=$(echo "$selection_list" | gum filter --placeholder "Select worktree to resume...")

  if [[ -z "$selected" ]]; then
    gum style --foreground 3 "Cancelled"
    return $AW_EXIT_CANCELLED
  fi

  # Find the corresponding path
  local selected_path=""
  local i=1
  while [[ $i -le ${#worktree_displays[@]} ]]; do
    if [[ "${worktree_displays[$i]}" == "$selected" ]]; then
      selected_path="${worktree_paths[$i]}"
      break
    fi
    ((i++))
  done

  if [[ -z "$selected_path" ]]; then
    gum style --foreground 1 "Error: Could not find selected worktree"
    return 1
  fi

  echo ""
  gum style --foreground 2 "Resuming session in:"
  echo "  $selected_path"
  echo ""

  cd "$selected_path" || return 1

  # Set terminal title to the branch name
  local branch_name=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  printf '\033]0;%s\007' "$branch_name"

  _resolve_ai_command || return 1

  if [[ "${AI_CMD[1]}" != "skip" ]]; then
    # Check if a conversation exists to resume
    # Claude Code stores conversation history in .claude directory
    if [[ -d ".claude" ]] || [[ -f ".claude.json" ]]; then
      # Conversation exists, try to resume
      "${AI_RESUME_CMD[@]}"
    else
      # No conversation found, start a fresh session
      gum style --foreground 3 "No conversation found to continue"
      gum style --foreground 6 "Starting fresh session in worktree..."
      echo ""
      "${AI_CMD[@]}"
    fi
  else
    gum style --foreground 3 "Skipping AI tool - worktree is ready for manual work"
  fi
}
