#!/bin/bash

# ============================================================================
# PR review integration
# ============================================================================

# Ensure worktree exists for a PR/MR, handling all states transparently
# Usage: _aw_ensure_pr_worktree "$provider" "$pr_num" "$head_ref" "$base_ref" "$worktree_path"
_aw_ensure_pr_worktree() {
  local provider="$1"
  local pr_num="$2"
  local head_ref="$3"
  local base_ref="$4"
  local worktree_path="$5"

  mkdir -p "$_AW_WORKTREE_BASE"

  # Fetch the PR/MR ref
  if [[ "$provider" == "gitlab" ]]; then
    gum spin --spinner dot --title "Fetching MR branch..." -- git fetch origin "merge-requests/${pr_num}/head" 2>/dev/null || \
      git fetch origin "${head_ref}" 2>/dev/null
  else
    gum spin --spinner dot --title "Fetching PR branch..." -- git fetch origin "pull/${pr_num}/head" 2>/dev/null || \
      git fetch origin "${head_ref}" 2>/dev/null
  fi

  # Capture fetched SHA immediately to avoid FETCH_HEAD race
  local fetched_sha
  fetched_sha=$(git rev-parse FETCH_HEAD 2>/dev/null)

  # Fetch base branch for comparison
  git fetch origin "$base_ref" 2>/dev/null

  # Determine current state and act accordingly
  local branch_exists=false
  local worktree_exists=false

  git show-ref --verify --quiet "refs/heads/${head_ref}" 2>/dev/null && branch_exists=true
  [[ -d "$worktree_path" ]] && worktree_exists=true

  if [[ "$worktree_exists" == "true" ]]; then
    # Worktree already exists — update in-place
    if [[ -n "$fetched_sha" ]]; then
      local local_sha
      local_sha=$(git -C "$worktree_path" rev-parse HEAD 2>/dev/null)
      if [[ "$local_sha" != "$fetched_sha" ]]; then
        # Check for uncommitted changes
        if ! git -C "$worktree_path" diff --quiet 2>/dev/null || ! git -C "$worktree_path" diff --cached --quiet 2>/dev/null; then
          gum style --foreground 3 "Warning: uncommitted changes in worktree will be discarded"
        fi
        gum spin --spinner dot --title "Updating worktree to latest..." -- git -C "$worktree_path" reset --hard "$fetched_sha"
      fi
    fi
    cd "$worktree_path" || return 1
  else
    # Need to create worktree
    if [[ "$branch_exists" == "true" ]]; then
      # Branch exists but no worktree — update branch to fetched SHA
      local branch_worktree
      branch_worktree=$(git worktree list --porcelain 2>/dev/null | grep -A2 "^worktree " | grep -B1 "branch refs/heads/${head_ref}$" | head -1 | sed 's/^worktree //')
      if [[ -z "$branch_worktree" ]]; then
        git branch -f "${head_ref}" "$fetched_sha" 2>/dev/null
      fi
    else
      # No branch — create from fetched SHA
      git branch "${head_ref}" "$fetched_sha" 2>/dev/null
    fi

    # Create worktree
    if ! gum spin --spinner dot --title "Creating worktree..." -- git worktree add "$worktree_path" "$head_ref" 2>/dev/null; then
      # Branch checked out elsewhere — fall back to detached worktree
      if [[ "$provider" == "gitlab" ]]; then
        gum style --foreground 6 "Branch already in use, creating detached worktree for MR..."
      else
        gum style --foreground 6 "Branch already in use, creating detached worktree for PR..."
      fi

      if ! gum spin --spinner dot --title "Creating worktree..." -- git worktree add --detach "$worktree_path" "$fetched_sha"; then
        gum style --foreground 1 "Failed to create worktree"
        return 1
      fi
    fi

    cd "$worktree_path" || return 1

    # Set up environment only on first creation
    _aw_setup_environment "$worktree_path"
  fi
}

# Show action menu for PR/MR workflow
# Returns: "continue", "fix", "review", or "" (cancelled)
_aw_pr_action_menu() {
  echo ""
  local choice
  choice=$(gum choose \
    "Continue work" \
    "Fix issues" \
    "Review & suggest fixes" \
    "Cancel")

  case "$choice" in
    "Continue work")          echo "continue" ;;
    "Fix issues")             echo "fix" ;;
    "Review & suggest fixes") echo "review" ;;
    *)                        echo "" ;;
  esac
}

# Build a targeted prompt for the AI agent based on the selected action
# Usage: _aw_pr_build_prompt "$action" "$provider" "$pr_num" "$title" "$author" "$head_ref" "$base_ref"
_aw_pr_build_prompt() {
  local action="$1"
  local provider="$2"
  local pr_num="$3"
  local title="$4"
  local author="$5"
  local head_ref="$6"
  local base_ref="$7"

  local pr_label="PR #${pr_num}"
  if [[ "$provider" == "gitlab" ]]; then
    pr_label="MR !${pr_num}"
  fi

  local metadata="You are working on ${pr_label}: \"${title}\" by @${author}. Branch: ${head_ref} -> ${base_ref}."

  case "$action" in
    continue)
      cat <<EOF
${metadata}

Review the diff against the base branch (git diff origin/${base_ref}...HEAD), read any open review comments and CI feedback, and check for TODOs, incomplete implementations, or failing tests. Then continue the implementation where it was left off. Commit and push when ready.
EOF
      ;;
    fix)
      cat <<EOF
${metadata}

Check the CI status and read any failing test output or build errors. Review change-request comments from reviewers. Look at the diff against the base branch (git diff origin/${base_ref}...HEAD). Run the test suite locally to reproduce failures. Fix identified issues — CI failures first, then reviewer feedback. Commit and push when ready.
EOF
      ;;
    review)
      cat <<EOF
${metadata}

This is a READ-ONLY code review — do NOT modify any code or create commits. Examine the diff against the base branch (git diff origin/${base_ref}...HEAD). Look for bugs, logic errors, security issues, and edge cases. Check code style consistency and test coverage. Present your findings as a structured review with:
- Summary of the changes
- Issues found by severity (critical / major / minor / nit)
- Specific suggestions with file paths and line numbers
- Overall assessment and recommendation (approve, request changes, or needs discussion)
EOF
      ;;
  esac
}

# Launch the AI agent with the appropriate mode
# Usage: _aw_pr_launch_ai "$action" "$prompt" "$provider" "$pr_num" "$title"
_aw_pr_launch_ai() {
  local action="$1"
  local prompt="$2"
  local provider="$3"
  local pr_num="$4"
  local title="$5"

  # Set terminal title
  if [[ "$provider" == "gitlab" ]]; then
    printf '\033]0;GitLab MR !%s - %s\007' "$pr_num" "$title"
  else
    printf '\033]0;GitHub PR #%s - %s\007' "$pr_num" "$title"
  fi

  _resolve_ai_command || return 1

  if [[ "${AI_CMD[1]}" == "skip" ]]; then
    gum style --foreground 3 "Skipping AI tool - worktree is ready for manual work"
    return 0
  fi

  echo ""

  # For "continue" mode, try to resume an existing AI conversation
  if [[ "$action" == "continue" ]] && [[ -d ".claude" ]]; then
    gum style --foreground 2 "Resuming $AI_CMD_NAME session..."
    "${AI_RESUME_CMD[@]}"
  else
    local mode_label
    case "$action" in
      continue) mode_label="continue work" ;;
      fix)      mode_label="fix issues" ;;
      review)   mode_label="review" ;;
    esac
    gum style --foreground 2 "Starting $AI_CMD_NAME ($mode_label)..."
    "${AI_CMD[@]}" "$prompt"
  fi
}

_aw_pr() {
  _aw_ensure_git_repo || return 1
  _aw_get_repo_info

  # Determine provider - check if GitLab is configured, otherwise assume GitHub
  local provider=$(_aw_get_issue_provider)
  if [[ -z "$provider" ]] || [[ "$provider" == "jira" ]]; then
    # Default to GitHub for PR workflow, or detect from remote
    provider="github"
  fi

  # Check for provider-specific dependencies
  _aw_check_issue_provider_deps "$provider" || return 1

  local pr_num="${1:-}"

  if [[ -z "$pr_num" ]]; then
    if [[ "$provider" == "gitlab" ]]; then
      gum spin --spinner dot --title "Fetching merge requests..." -- sleep 0.1
    else
      gum spin --spinner dot --title "Fetching pull requests..." -- sleep 0.1
    fi

    local prs=""
    if [[ "$provider" == "gitlab" ]]; then
      # List GitLab MRs
      local gitlab_server=$(_aw_get_gitlab_server)
      local glab_cmd="glab"
      if [[ -n "$gitlab_server" ]]; then
        glab_cmd="glab --host $gitlab_server"
      fi

      prs=$($glab_cmd mr list --state opened --per-page 100 2>/dev/null | \
        awk -F'\t' '{
          if ($1 ~ /^![0-9]+/) {
            number = substr($1, 2)  # Remove ! prefix
            title = $2
            branch = $3
            gsub(/[()]/, "", branch)  # Remove parentheses
            printf "#%s | ○ | %s | %s\n", number, title, branch
          }
        }')
    else
      # List GitHub PRs with detailed information for AI selection
      prs=$(gh pr list --limit 100 --state open --json number,title,author,headRefName,baseRefName,labels,statusCheckRollup,reviews,additions,deletions,reviewRequests 2>/dev/null | \
        jq -r '.[] | "#\(.number) | \(
          if (.statusCheckRollup | length == 0) then "○"
          elif (.statusCheckRollup | all(.state == "SUCCESS")) then "✓"
          elif (.statusCheckRollup | any(.state == "FAILURE" or .state == "ERROR")) then "✗"
          else "○"
          end
        ) | \(.title) | @\(.author.login)\(
          if (.labels | length > 0) then " |" + ([.labels[].name] | map(" [\(.)]") | join(""))
          else ""
          end
        ) | +\(.additions)/-\(.deletions) | \(
          if (.reviews | length) > 0 then "reviews:\(.reviews | length)"
          else "reviews:0"
          end
        )\(
          if (.reviewRequests | length) > 0 then " | requested:[" + ([.reviewRequests[].login] | join(",")) + "]"
          else ""
          end
        ) | \(.headRefName)"')
    fi

    if [[ -z "$prs" ]]; then
      if [[ "$provider" == "gitlab" ]]; then
        gum style --foreground 1 "No open MRs found or not in a GitLab repository"
      else
        gum style --foreground 1 "No open PRs found or not in a GitHub repository"
      fi
      return 1
    fi

    # Detect which PRs/MRs have active worktrees
    local active_prs=()
    local worktree_list=$(git worktree list --porcelain 2>/dev/null | grep "^worktree " | sed 's/^worktree //')
    if [[ -n "$worktree_list" ]]; then
      while IFS= read -r wt_path; do
        if [[ -d "$wt_path" ]]; then
          local wt_branch=$(git -C "$wt_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
          # Check if worktree path contains pr-{number} or mr-{number} pattern
          if [[ "$wt_path" =~ (pr|mr)-([0-9]+) ]]; then
            active_prs+=("${BASH_REMATCH[2]}")
          fi
          # Also check by branch name in case PR/MR uses the actual head branch
          if [[ -n "$wt_branch" ]]; then
            # Extract PR/MR number from branch in prs data
            local matching_pr=$(echo "$prs" | grep -E " \| ${wt_branch}\$" | sed 's/^#//' | cut -d'|' -f1 | tr -d ' ')
            if [[ -n "$matching_pr" ]]; then
              active_prs+=("$matching_pr")
            fi
          fi
        fi
      done <<< "$worktree_list"
    fi

    # Add highlighting for PRs with active worktrees
    local highlighted_prs=""
    while IFS= read -r pr_line; do
      if [[ -n "$pr_line" ]]; then
        # Extract PR number from the line
        local line_pr=$(echo "$pr_line" | sed 's/^#//' | cut -d'|' -f1 | tr -d ' ')
        # Check if this PR has an active worktree
        local is_active=false
        for active in "${active_prs[@]}"; do
          if [[ "$active" == "$line_pr" ]]; then
            is_active=true
            break
          fi
        done
        # Add indicator if active, and remove the headRefName we added temporarily
        local display_line=$(echo "$pr_line" | sed 's/ | [^|]*$//')
        if [[ "$is_active" == "true" ]]; then
          highlighted_prs+="$(echo "$display_line" | sed 's/^#/● #/')"$'\n'
        else
          highlighted_prs+="$display_line"$'\n'
        fi
      fi
    done <<< "$prs"

    # Build the selection list with auto-select options (GitHub only)
    local selection_list=""
    if [[ "$provider" == "github" ]]; then
      if ! _is_pr_autoselect_disabled; then
        # Auto-select is enabled - show auto-select options at the top
        selection_list="⚡ Auto select"$'\n'
        selection_list+="🚫 Do not show me auto select again"$'\n'
        selection_list+="$highlighted_prs"
      else
        # Auto-select is disabled - add re-enable option at the end
        selection_list="$highlighted_prs"
        selection_list+="⚡ Auto select next PR"$'\n'
      fi
    else
      # GitLab - no auto-select
      selection_list="$highlighted_prs"
    fi

    if [[ "$provider" == "gitlab" ]]; then
      local selection=$(echo "$selection_list" | gum filter --placeholder "Type to filter MRs... (● = active worktree, ○=pending)")
    else
      local selection=$(echo "$selection_list" | gum filter --placeholder "Type to filter PRs... (● = active worktree, ✓=passing ✗=failing ○=pending)")
    fi

    if [[ -z "$selection" ]]; then
      gum style --foreground 3 "Cancelled"
      return 0
    fi

    # Handle special auto-select options (GitHub only)
    if [[ "$provider" == "github" ]] && [[ "$selection" == "⚡ Auto select" ]]; then
      gum spin --spinner dot --title "AI is selecting best PRs..." -- sleep 0.5

      # Get current GitHub user
      local current_user=$(gh api user -q .login 2>/dev/null || echo "unknown")

      local filtered_prs=$(_ai_select_prs "$prs" "$highlighted_prs" "$current_user" "${REPO_OWNER}/${REPO_NAME}")

      if [[ -z "$filtered_prs" ]]; then
        gum style --foreground 1 "AI selection failed, showing all PRs"
        filtered_prs="$highlighted_prs"
      else
        echo ""
        gum style --foreground 2 "✓ AI selected top 5 PRs in priority order"
        echo ""
      fi

      # Show the filtered list
      selection=$(echo "$filtered_prs" | gum filter --placeholder "Select a PR from AI recommendations")

      if [[ -z "$selection" ]]; then
        gum style --foreground 3 "Cancelled"
        return 0
      fi

      pr_num=$(echo "$selection" | sed 's/^● *//' | sed 's/^#//' | cut -d'|' -f1 | tr -d ' ')

    elif [[ "$provider" == "github" ]] && [[ "$selection" == "🚫 Do not show me auto select again" ]]; then
      _disable_pr_autoselect
      gum style --foreground 3 "Auto-select disabled. You can re-enable it from the bottom of the PR list."
      # Recursively call to show the updated list
      _aw_pr
      return $?

    elif [[ "$provider" == "github" ]] && [[ "$selection" == "⚡ Auto select next PR" ]]; then
      _enable_pr_autoselect
      gum style --foreground 2 "Auto-select re-enabled!"
      # Recursively call to show the updated list
      _aw_pr
      return $?

    else
      pr_num=$(echo "$selection" | sed 's/^● *//' | sed 's/^#//' | cut -d'|' -f1 | tr -d ' ')
    fi
  fi

  # Get PR/MR details
  local title=""
  local head_ref=""
  local base_ref=""
  local author=""

  if [[ "$provider" == "gitlab" ]]; then
    local gitlab_server=$(_aw_get_gitlab_server)
    local glab_cmd="glab"
    if [[ -n "$gitlab_server" ]]; then
      glab_cmd="glab --host $gitlab_server"
    fi

    local mr_data=$($glab_cmd mr view "$pr_num" --json title,sourceBranch,targetBranch,author 2>/dev/null)

    if [[ -z "$mr_data" ]]; then
      gum style --foreground 1 "Could not fetch MR !$pr_num"
      return 1
    fi

    title=$(echo "$mr_data" | jq -r '.title')
    head_ref=$(echo "$mr_data" | jq -r '.sourceBranch')
    base_ref=$(echo "$mr_data" | jq -r '.targetBranch')
    author=$(echo "$mr_data" | jq -r '.author.username // .author.login // ""')
  else
    local pr_data=$(gh pr view "$pr_num" --json number,title,headRefName,baseRefName,author 2>/dev/null)

    if [[ -z "$pr_data" ]]; then
      gum style --foreground 1 "Could not fetch PR #$pr_num"
      return 1
    fi

    title=$(echo "$pr_data" | jq -r '.title')
    head_ref=$(echo "$pr_data" | jq -r '.headRefName')
    base_ref=$(echo "$pr_data" | jq -r '.baseRefName')
    author=$(echo "$pr_data" | jq -r '.author.login')
  fi

  # Compute worktree path
  local worktree_prefix="pr"
  if [[ "$provider" == "gitlab" ]]; then
    worktree_prefix="mr"
  fi
  local worktree_name="${worktree_prefix}-${pr_num}"
  local worktree_path="$_AW_WORKTREE_BASE/$worktree_name"

  # Display PR info
  echo ""
  if [[ "$provider" == "gitlab" ]]; then
    gum style --border rounded --padding "0 1" --border-foreground 5 -- \
      "MR !${pr_num} by @${author}" \
      "$title" \
      "" \
      "$head_ref -> $base_ref"
  else
    gum style --border rounded --padding "0 1" --border-foreground 5 -- \
      "PR #${pr_num} by @${author}" \
      "$title" \
      "" \
      "$head_ref -> $base_ref"
  fi

  # Ensure worktree exists (fetch, create/update, cd)
  _aw_ensure_pr_worktree "$provider" "$pr_num" "$head_ref" "$base_ref" "$worktree_path" || return 1

  # Show diff stats
  echo ""
  gum style --border rounded --padding "0 1" --border-foreground 6 \
    "Changes vs $base_ref"
  git --no-pager diff --stat "origin/${base_ref}...HEAD" 2>/dev/null || git --no-pager diff --stat HEAD~5...HEAD 2>/dev/null

  # Action menu
  local action
  action=$(_aw_pr_action_menu)
  if [[ -z "$action" ]]; then
    gum style --foreground 3 "Cancelled"
    return 0
  fi

  # Build prompt and launch AI
  local prompt
  prompt=$(_aw_pr_build_prompt "$action" "$provider" "$pr_num" "$title" "$author" "$head_ref" "$base_ref")

  _aw_pr_launch_ai "$action" "$prompt" "$provider" "$pr_num" "$title"
}
