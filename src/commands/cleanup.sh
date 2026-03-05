#!/bin/bash

# ============================================================================
# Cleanup worktrees
# ============================================================================
_aw_cleanup_interactive() {
  _aw_ensure_git_repo || return 1
  _aw_get_repo_info

  local current_path=$(pwd)
  local provider
  provider=$(_aw_init_issue_provider) || return 1
  local worktree_list
  worktree_list=$(_aw_get_worktree_list)
  local worktree_count
  worktree_count=$(_aw_count_worktrees "$worktree_list")

  if [[ $worktree_count -le 1 ]]; then
    gum style --foreground 8 "No additional worktrees to clean up for $_AW_SOURCE_FOLDER"
    return 0
  fi

  # Build list of worktrees with their display information
  local -a wt_choices=()
  local -a wt_paths=()
  local -a wt_branches=()
  local -a wt_warnings=()
  local -a wt_dirty=()

  while IFS= read -r wt_path; do
    _aw_validate_worktree_path "$wt_path" || continue
    [[ "$wt_path" == "$current_path" ]] && continue

    local wt_branch=$(git -C "$wt_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    local commit_timestamp
    commit_timestamp=$(_aw_get_worktree_timestamp "$wt_path" "$wt_branch")

    # Check for dirty git state (unstaged or uncommitted changes)
    local dirty_files=$(git -C "$wt_path" status --porcelain 2>/dev/null)
    local is_dirty=false
    if [[ -n "$dirty_files" ]]; then
      is_dirty=true
    fi

    # Check merge/close status
    local issue_num
    issue_num=$(_aw_extract_issue_id_from_branch "$wt_branch" "$provider")
    local status_tag=""
    local warning_msg=""

    if [[ "$is_dirty" == "true" ]]; then
      local dirty_count=$(echo "$dirty_files" | grep -c . 2>/dev/null || echo 0)
      status_tag="[dirty: $dirty_count uncommitted file(s)]"
      warning_msg="⚠ HAS UNCOMMITTED CHANGES"
    elif [[ -n "$issue_num" ]] && _aw_check_issue_merged "$issue_num"; then
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
    local age_str
    age_str=$(_aw_format_worktree_age "$commit_timestamp")

    # Build display string
    local display_name="$(basename "$wt_path") ($wt_branch) $age_str"
    if [[ -n "$status_tag" ]]; then
      display_name="$display_name $status_tag"
    fi

    wt_choices+=("$display_name")
    wt_paths+=("$wt_path")
    wt_branches+=("$wt_branch")
    wt_warnings+=("$warning_msg")
    wt_dirty+=("$is_dirty")
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
    return $AW_EXIT_CANCELLED
  fi

  # Find indices of selected worktrees
  local -a selected_indices=()
  local i=1
  while IFS= read -r selected_item; do
    local j=0
    while [[ $j -lt ${#wt_choices[@]} ]]; do
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
  local has_dirty=false
  for idx in "${selected_indices[@]}"; do
    local display="${wt_choices[$idx]}"
    local warning="${wt_warnings[$idx]}"
    local dirty="${wt_dirty[$idx]}"

    if [[ "$dirty" == "true" ]]; then
      echo "  • $display"
      echo "    $(gum style --foreground 1 "$warning")"
      has_dirty=true
    elif [[ -n "$warning" ]]; then
      echo "  • $display"
      echo "    $(gum style --foreground 3 "$warning")"
      has_warnings=true
    else
      echo "  • $display"
    fi
  done

  echo ""
  if [[ "$has_dirty" == "true" ]]; then
    gum style --foreground 1 "✗ Cannot clean up worktrees with uncommitted changes. Commit or stash your changes first."
    echo ""
  fi
  if [[ "$has_warnings" == "true" ]]; then
    gum style --foreground 3 "⚠ Warning: Some worktrees have unpushed commits!"
    echo ""
  fi

  # Filter out dirty worktrees - build safe indices list
  local -a clean_indices=()
  for idx in "${selected_indices[@]}"; do
    if [[ "${wt_dirty[$idx]}" != "true" ]]; then
      clean_indices+=($idx)
    fi
  done

  if [[ ${#clean_indices[@]} -eq 0 ]]; then
    gum style --foreground 8 "No worktrees eligible for cleanup (dirty worktrees were skipped)"
    return 0
  fi

  if ! gum confirm "Delete these worktrees and their branches?"; then
    gum style --foreground 8 "Cleanup cancelled"
    return $AW_EXIT_CANCELLED
  fi

  # Perform cleanup (only clean worktrees)
  for idx in "${clean_indices[@]}"; do
    local c_path="${wt_paths[$idx]}"
    local c_branch="${wt_branches[$idx]}"

    _aw_remove_worktree_and_branch "$c_path" "$c_branch" || return 1
  done

  echo ""
  gum style --foreground 2 "Cleanup complete!"
}
