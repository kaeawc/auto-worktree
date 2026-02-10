#!/bin/bash

# ============================================================================
# List worktrees
# ============================================================================
_aw_list() {
  _aw_ensure_git_repo || return 1
  _aw_get_repo_info
  _aw_prune_worktrees

  local worktree_list=$(git worktree list --porcelain 2>/dev/null | grep "^worktree " | sed 's/^worktree //')
  local worktree_count=$(echo "$worktree_list" | grep -c . 2>/dev/null || echo 0)

  if [[ $worktree_count -le 1 ]]; then
    gum style --foreground 8 "No additional worktrees for $_AW_SOURCE_FOLDER"
    return 0
  fi

  local now=$(date +%s)
  local one_day=$((24 * 60 * 60))
  local four_days=$((4 * 24 * 60 * 60))

  local oldest_wt_path=""
  local oldest_wt_branch=""
  local oldest_age=0

  # Track merged worktrees for cleanup prompt
  local -a merged_wt_paths=()
  local -a merged_wt_branches=()
  local -a merged_wt_issues=()

  local output=""

  while IFS= read -r wt_path; do
    [[ "$wt_path" == "$_AW_GIT_ROOT" ]] && continue
    [[ ! -d "$wt_path" ]] && continue

    local wt_branch=$(git -C "$wt_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    local commit_timestamp=$(git -C "$wt_path" log -1 --format=%ct 2>/dev/null)

    if [[ -z "$commit_timestamp" ]] || ! [[ "$commit_timestamp" =~ ^[0-9]+$ ]]; then
      commit_timestamp=$(find "$wt_path" -maxdepth 3 -type f -not -path '*/.git/*' -print0 2>/dev/null | while IFS= read -r -d '' file; do _aw_get_file_mtime "$file"; done | sort -rn | head -1)
    fi

    # Check if this worktree is linked to a merged/resolved issue or has a merged PR
    # Try to detect both GitHub issues and JIRA keys
    local issue_id=$(_aw_extract_issue_id "$wt_branch")
    local is_merged=false
    local merged_indicator=""
    local merge_reason=""

    # _AW_DETECTED_ISSUE_TYPE is set by _aw_extract_issue_id
    if [[ -n "$issue_id" ]]; then
      if [[ "$_AW_DETECTED_ISSUE_TYPE" == "jira" ]]; then
        # Check if JIRA issue is resolved
        if _aw_jira_check_resolved "$issue_id"; then
          is_merged=true
          merge_reason="JIRA $issue_id"
          merged_indicator=" $(gum style --foreground 5 "[resolved $issue_id]")"
        fi
      elif [[ "$_AW_DETECTED_ISSUE_TYPE" == "gitlab" ]]; then
        # Check if GitLab issue is closed
        if _aw_gitlab_check_closed "$issue_id" "issue"; then
          # Check for unpushed commits
          if _aw_has_unpushed_commits "$wt_path"; then
            # Has unpushed work - mark as closed but with warning
            is_merged=true
            merge_reason="issue #$issue_id closed (⚠ $_AW_UNPUSHED_COUNT unpushed)"
            merged_indicator=" $(gum style --foreground 3 "[closed #$issue_id ⚠]")"
          else
            # No unpushed work - safe to clean up
            is_merged=true
            merge_reason="issue #$issue_id closed"
            merged_indicator=" $(gum style --foreground 5 "[closed #$issue_id]")"
          fi
        fi
      elif [[ "$_AW_DETECTED_ISSUE_TYPE" == "linear" ]]; then
        # Check if Linear issue is completed
        if _aw_linear_check_completed "$issue_id"; then
          is_merged=true
          merge_reason="Linear $issue_id"
          merged_indicator=" $(gum style --foreground 5 "[completed $issue_id]")"
        fi
      elif [[ "$_AW_DETECTED_ISSUE_TYPE" == "github" ]]; then
        # Check if GitHub issue is merged
        if _aw_check_issue_merged "$issue_id"; then
          is_merged=true
          merge_reason="issue #$issue_id"
          merged_indicator=" $(gum style --foreground 5 "[merged #$issue_id]")"
        elif _aw_check_issue_closed "$issue_id"; then
          # Issue is closed but no PR (either open or merged)
          if [[ "$_AW_ISSUE_HAS_PR" == "false" ]]; then
            # Check for unpushed commits
            if _aw_has_unpushed_commits "$wt_path"; then
              # Has unpushed work - mark as closed but with warning
              is_merged=true
              merge_reason="issue #$issue_id closed (⚠ $_AW_UNPUSHED_COUNT unpushed)"
              merged_indicator=" $(gum style --foreground 3 "[closed #$issue_id ⚠]")"
            else
              # No unpushed work - safe to clean up
              is_merged=true
              merge_reason="issue #$issue_id closed"
              merged_indicator=" $(gum style --foreground 5 "[closed #$issue_id]")"
            fi
          fi
        fi
      fi
    fi

    # Also check for merged PRs/MRs if no issue was detected
    if [[ "$is_merged" == "false" ]]; then
      # Check for GitLab MRs (mr-{number} pattern in path)
      if [[ "$wt_path" =~ mr-([0-9]+) ]]; then
        local mr_num="${BASH_REMATCH[1]}"
        if _aw_gitlab_check_closed "$mr_num" "mr"; then
          is_merged=true
          merge_reason="MR"
          merged_indicator=" $(gum style --foreground 5 "[MR merged]")"
        fi
      # Check for GitHub PRs
      elif _aw_check_branch_pr_merged "$wt_branch"; then
        is_merged=true
        merge_reason="PR"
        merged_indicator=" $(gum style --foreground 5 "[PR merged]")"
      fi
    fi

    # Check for worktrees with no changes from default branch (only if not already flagged as merged/closed)
    if [[ "$is_merged" == "false" ]] && ! _aw_has_unpushed_commits "$wt_path" && _aw_check_no_changes_from_default "$wt_path"; then
      is_merged=true
      merge_reason="no changes from $_AW_DEFAULT_BRANCH_NAME"
      merged_indicator=" $(gum style --foreground 8 "[no changes]")"
    fi

    if [[ "$is_merged" == "true" ]]; then
      merged_wt_paths+=("$wt_path")
      merged_wt_branches+=("$wt_branch")
      merged_wt_issues+=("$merge_reason")
    fi

    if [[ -z "$commit_timestamp" ]] || ! [[ "$commit_timestamp" =~ ^[0-9]+$ ]]; then
      output+="  $(gum style --foreground 8 "$(basename "$wt_path")") ($wt_branch) [unknown]${merged_indicator}\n"
      continue
    fi

    local age=$((now - commit_timestamp))
    local age_days=$((age / one_day))
    local age_hours=$((age / 3600))

    # Build age string and color inline to avoid zsh variable assignment echo bug
    if [[ $age -lt $one_day ]]; then
      output+="  $(basename "$wt_path") ($wt_branch) $(gum style --foreground 2 "[${age_hours}h ago]")${merged_indicator}\n"
    elif [[ $age -lt $four_days ]]; then
      output+="  $(basename "$wt_path") ($wt_branch) $(gum style --foreground 3 "[${age_days}d ago]")${merged_indicator}\n"
    else
      output+="  $(basename "$wt_path") ($wt_branch) $(gum style --foreground 1 "[${age_days}d ago]")${merged_indicator}\n"
      # Only track as stale if not already marked as merged
      if [[ "$is_merged" == "false" ]] && [[ $age -gt $oldest_age ]]; then
        oldest_age=$age
        oldest_wt_path="$wt_path"
        oldest_wt_branch="$wt_branch"
      fi
    fi
  done <<< "$worktree_list"

  if [[ -n "$output" ]]; then
    gum style --border rounded --padding "0 1" --border-foreground 4 \
      "Worktrees for $_AW_SOURCE_FOLDER"
    echo -e "$output"
  fi

  # Collect all worktrees to clean up (merged + stale)
  local -a cleanup_wt_paths=()
  local -a cleanup_wt_branches=()
  local -a cleanup_wt_reasons=()

  # Add merged worktrees
  if [[ ${#merged_wt_paths} -gt 0 ]]; then
    local i=1
    while [[ $i -le ${#merged_wt_paths} ]]; do
      cleanup_wt_paths+=("${merged_wt_paths[$i]}")
      cleanup_wt_branches+=("${merged_wt_branches[$i]}")
      cleanup_wt_reasons+=("merged (${merged_wt_issues[$i]})")
      ((i++))
    done
  fi

  # Add stale worktree
  if [[ -n "$oldest_wt_path" ]]; then
    local days=$((oldest_age / one_day))
    cleanup_wt_paths+=("$oldest_wt_path")
    cleanup_wt_branches+=("$oldest_wt_branch")
    cleanup_wt_reasons+=("stale (${days}d old)")
  fi

  # Prompt for batch cleanup
  if [[ ${#cleanup_wt_paths} -gt 0 ]]; then
    echo ""
    gum style --foreground 5 "Worktrees that can be cleaned up:"
    echo ""

    local i=1
    while [[ $i -le ${#cleanup_wt_paths} ]]; do
      local c_path="${cleanup_wt_paths[$i]}"
      local c_branch="${cleanup_wt_branches[$i]}"
      local c_reason="${cleanup_wt_reasons[$i]}"
      echo "  • $(basename "$c_path") ($c_branch) - $c_reason"
      ((i++))
    done

    echo ""
    if gum confirm "Clean up all these worktrees and delete their branches?"; then
      local i=1
      while [[ $i -le ${#cleanup_wt_paths} ]]; do
        local c_path="${cleanup_wt_paths[$i]}"
        local c_branch="${cleanup_wt_branches[$i]}"

        echo ""
        gum spin --spinner dot --title "Removing $(basename "$c_path")..." -- git worktree remove --force "$c_path"
        gum style --foreground 2 "Worktree removed."

        if git show-ref --verify --quiet "refs/heads/${c_branch}"; then
          git branch -D "$c_branch" 2>/dev/null
          gum style --foreground 2 "Branch deleted."
        fi

        ((i++))
      done
    fi
  fi
}
