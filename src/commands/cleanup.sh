#!/bin/bash

# ============================================================================
# Cleanup worktrees
# ============================================================================
_aw_cleanup_interactive() {
  _aw_ensure_git_repo || return 1
  _aw_get_repo_info

  local current_path=$(pwd)
  local worktree_list=$(git worktree list --porcelain 2>/dev/null | grep "^worktree " | sed 's/^worktree //')
  local worktree_count=$(echo "$worktree_list" | grep -c . 2>/dev/null || echo 0)

  if [[ $worktree_count -le 1 ]]; then
    gum style --foreground 8 "No additional worktrees to clean up for $_AW_SOURCE_FOLDER"
    return 0
  fi

  local now=$(date +%s)
  local one_day=$((24 * 60 * 60))
  local four_days=$((4 * 24 * 60 * 60))

  # Build list of worktrees with their display information
  local -a wt_choices=()
  local -a wt_paths=()
  local -a wt_branches=()
  local -a wt_warnings=()

  while IFS= read -r wt_path; do
    [[ "$wt_path" == "$_AW_GIT_ROOT" ]] && continue
    [[ "$wt_path" == "$current_path" ]] && continue
    [[ ! -d "$wt_path" ]] && continue

    local wt_branch=$(git -C "$wt_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    local commit_timestamp=$(git -C "$wt_path" log -1 --format=%ct 2>/dev/null)

    if [[ -z "$commit_timestamp" ]] || ! [[ "$commit_timestamp" =~ ^[0-9]+$ ]]; then
      commit_timestamp=$(find "$wt_path" -maxdepth 3 -type f -not -path '*/.git/*' -print0 2>/dev/null | while IFS= read -r -d '' file; do _aw_get_file_mtime "$file"; done | sort -rn | head -1)
    fi

    # Check merge/close status
    local issue_num=$(_aw_extract_issue_number "$wt_branch")
    local status_tag=""
    local warning_msg=""

    if [[ -n "$issue_num" ]] && _aw_check_issue_merged "$issue_num"; then
      status_tag="[merged #$issue_num]"
    elif _aw_check_branch_pr_merged "$wt_branch"; then
      status_tag="[PR merged]"
    elif [[ -n "$issue_num" ]] && _aw_check_issue_closed "$issue_num"; then
      if [[ "$_AW_ISSUE_HAS_PR" == "false" ]]; then
        if _aw_has_unpushed_commits "$wt_path"; then
          status_tag="[closed #$issue_num ⚠ $_AW_UNPUSHED_COUNT unpushed]"
          warning_msg="⚠ HAS UNPUSHED COMMITS"
        else
          status_tag="[closed #$issue_num]"
        fi
      fi
    elif ! _aw_has_unpushed_commits "$wt_path" && _aw_check_no_changes_from_default "$wt_path"; then
      status_tag="[no changes]"
    fi

    # Build age string
    local age_str=""
    if [[ -n "$commit_timestamp" ]] && [[ "$commit_timestamp" =~ ^[0-9]+$ ]]; then
      local age=$((now - commit_timestamp))
      local age_days=$((age / one_day))
      local age_hours=$((age / 3600))

      if [[ $age -lt $one_day ]]; then
        age_str="[${age_hours}h ago]"
      else
        age_str="[${age_days}d ago]"
      fi
    else
      age_str="[unknown]"
    fi

    # Build display string
    local display_name="$(basename "$wt_path") ($wt_branch) $age_str"
    if [[ -n "$status_tag" ]]; then
      display_name="$display_name $status_tag"
    fi

    wt_choices+=("$display_name")
    wt_paths+=("$wt_path")
    wt_branches+=("$wt_branch")
    wt_warnings+=("$warning_msg")
  done <<< "$worktree_list"

  if [[ ${#wt_choices[@]} -eq 0 ]]; then
    gum style --foreground 8 "No worktrees available to clean up (excluding current worktree)"
    return 0
  fi

  # Show selection UI
  gum style --border rounded --padding "0 1" --border-foreground 4 \
    "Select worktrees to clean up (space to select, enter to confirm)"
  echo ""

  local selected=$(printf '%s\n' "${wt_choices[@]}" | gum choose --no-limit --height 15)

  if [[ -z "$selected" ]]; then
    gum style --foreground 8 "No worktrees selected for cleanup"
    return 0
  fi

  # Find indices of selected worktrees
  local -a selected_indices=()
  local i=1
  while IFS= read -r selected_item; do
    local j=1
    while [[ $j -le ${#wt_choices[@]} ]]; do
      if [[ "${wt_choices[$j]}" == "$selected_item" ]]; then
        selected_indices+=($j)
        break
      fi
      ((j++))
    done
    ((i++))
  done <<< "$selected"

  # Show what will be deleted and confirm
  echo ""
  gum style --foreground 5 "Worktrees selected for cleanup:"
  echo ""

  local has_warnings=false
  for idx in "${selected_indices[@]}"; do
    local display="${wt_choices[$idx]}"
    local warning="${wt_warnings[$idx]}"

    if [[ -n "$warning" ]]; then
      echo "  • $display"
      echo "    $(gum style --foreground 1 "$warning")"
      has_warnings=true
    else
      echo "  • $display"
    fi
  done

  echo ""
  if [[ "$has_warnings" == "true" ]]; then
    gum style --foreground 3 "⚠ Warning: Some worktrees have unpushed commits!"
    echo ""
  fi

  if ! gum confirm "Delete these worktrees and their branches?"; then
    gum style --foreground 8 "Cleanup cancelled"
    return 0
  fi

  # Perform cleanup
  for idx in "${selected_indices[@]}"; do
    local c_path="${wt_paths[$idx]}"
    local c_branch="${wt_branches[$idx]}"

    echo ""
    gum spin --spinner dot --title "Removing $(basename "$c_path")..." -- git worktree remove --force "$c_path"
    gum style --foreground 2 "✓ Worktree removed: $(basename "$c_path")"

    if git show-ref --verify --quiet "refs/heads/${c_branch}"; then
      git branch -D "$c_branch" 2>/dev/null
      gum style --foreground 2 "✓ Branch deleted: $c_branch"
    fi
  done

  echo ""
  gum style --foreground 2 "Cleanup complete!"
}
