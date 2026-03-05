#!/bin/bash

# ============================================================================
# Issue integration
# ============================================================================
_aw_issue() {
  _aw_ensure_git_repo || return 1
  _aw_get_repo_info

  # Determine issue provider
  local provider
  provider=$(_aw_init_issue_provider) || return 1

  # Detect if argument is GitHub/GitLab issue number or JIRA key
  local issue_id="${1:-}"
  local issue_type=""

  if [[ -n "$issue_id" ]]; then
    # Auto-detect issue type from input
    if [[ "$issue_id" =~ ^[A-Z][A-Z0-9]+-[0-9]+$ ]]; then
      issue_type="jira"
    elif [[ "$issue_id" =~ ^[0-9]+$ ]]; then
      # Both GitHub and GitLab use numbers, so use the configured provider
      issue_type="$provider"
    else
      gum style --foreground 1 "Invalid issue format. Expected: issue number (e.g., 123) or JIRA key (e.g., PROJ-123)"
      return 1
    fi

    # Validate issue type matches provider (only warn for JIRA mismatch)
    if [[ "$issue_type" == "jira" ]] && [[ "$provider" != "jira" ]]; then
      gum style --foreground 3 "Warning: This repository is configured for $provider, but you provided a JIRA issue ID"
      if ! gum confirm "Continue anyway?"; then
        return 0
      fi
      provider="jira"
    fi
  fi

  if [[ -z "$issue_id" ]]; then
    gum spin --spinner dot --title "Fetching issues..." -- sleep 0.1

    local issues=""
    if [[ "$provider" == "jira" ]]; then
      issues=$(_aw_jira_list_issues)
    elif [[ "$provider" == "gitlab" ]]; then
      issues=$(_aw_gitlab_list_issues)
    elif [[ "$provider" == "linear" ]]; then
      issues=$(_aw_linear_list_issues)
    else
      issues=$(gh issue list --limit 100 --state open --json number,title,labels \
        --template '{{range .}}#{{.number}} | {{.title}}{{if .labels}} |{{range .labels}} [{{.name}}]{{end}}{{end}}{{"\n"}}{{end}}' 2>/dev/null)
    fi

    if [[ -z "$issues" ]]; then
      if [[ "$provider" == "jira" ]]; then
        gum style --foreground 1 "No open JIRA issues found"
      elif [[ "$provider" == "gitlab" ]]; then
        gum style --foreground 1 "No open GitLab issues found"
      elif [[ "$provider" == "linear" ]]; then
        gum style --foreground 1 "No open Linear issues found"
      else
        gum style --foreground 1 "No open GitHub issues found"
      fi
      return 1
    fi

    # Detect which issues have active worktrees
    local active_issues=()
    local worktree_list
    worktree_list=$(_aw_get_worktree_list)
    if [[ -n "$worktree_list" ]]; then
      while IFS= read -r wt_path; do
        if [[ -d "$wt_path" ]]; then
          local wt_branch=$(git -C "$wt_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
          if [[ -n "$wt_branch" ]]; then
            local wt_issue=$(_aw_extract_issue_id_from_branch "$wt_branch" "$provider")
            if [[ -n "$wt_issue" ]]; then
              active_issues+=("$wt_issue")
            fi
          fi
        fi
      done <<< "$worktree_list"
    fi

    # Add highlighting for issues with active worktrees
    local highlighted_issues=""
    while IFS= read -r issue_line; do
      if [[ -n "$issue_line" ]]; then
        # Extract issue ID from the line
        local line_issue=$(echo "$issue_line" | sed 's/^● *//' | sed 's/^#//' | cut -d'|' -f1 | tr -d ' ')
        # Check if this issue has an active worktree
        local is_active=false
        for active in "${active_issues[@]}"; do
          if [[ "$active" == "$line_issue" ]]; then
            is_active=true
            break
          fi
        done
        # Add indicator if active
        if [[ "$is_active" == "true" ]]; then
          if [[ "$provider" == "jira" ]] || [[ "$provider" == "linear" ]]; then
            highlighted_issues+="● $issue_line"$'\n'
          else
            highlighted_issues+="$(echo "$issue_line" | sed 's/^#/● #/')"$'\n'
          fi
        else
          highlighted_issues+="$issue_line"$'\n'
        fi
      fi
    done <<< "$issues"

    # Build the selection list with auto-select options
    local selection_list=""
    if ! _is_autoselect_disabled; then
      # Auto-select is enabled - show auto-select options at the top
      selection_list="⚡ Auto select"$'\n'
      selection_list+="🚫 Do not show me auto select again"$'\n'
      selection_list+="$highlighted_issues"
    else
      # Auto-select is disabled - add re-enable option at the end
      selection_list="$highlighted_issues"
      selection_list+="⚡ Auto select next issue"$'\n'
    fi

    local selection=$(echo "$selection_list" | gum filter --placeholder "Type to filter issues... (● = active worktree)")

    if [[ -z "$selection" ]]; then
      gum style --foreground 3 "Cancelled"
      return $AW_EXIT_CANCELLED
    fi

    # Handle special auto-select options (GitHub and Linear)
    if [[ ("$provider" == "github" || "$provider" == "linear") ]] && [[ "$selection" == "⚡ Auto select" ]]; then
      gum spin --spinner dot --title "AI is selecting best issues..." -- sleep 0.5

      local filtered_issues=""
      if [[ "$provider" == "github" ]]; then
        filtered_issues=$(_ai_select_issues "$issues" "$highlighted_issues" "${REPO_OWNER}/${REPO_NAME}")
      elif [[ "$provider" == "linear" ]]; then
        filtered_issues=$(_ai_select_linear_issues "$issues" "$highlighted_issues")
      fi

      if [[ -z "$filtered_issues" ]]; then
        gum style --foreground 1 "AI selection failed, showing all issues"
        filtered_issues="$highlighted_issues"
      else
        echo ""
        gum style --foreground 2 "✓ AI selected top 5 issues in priority order"
        echo ""
      fi

      # Show the filtered list
      selection=$(echo "$filtered_issues" | gum filter --placeholder "Select an issue from AI recommendations")

      if [[ -z "$selection" ]]; then
        gum style --foreground 3 "Cancelled"
        return $AW_EXIT_CANCELLED
      fi

      issue_id=$(echo "$selection" | sed 's/^● *//' | sed 's/^#//' | cut -d'|' -f1 | tr -d ' ')

    elif [[ ("$provider" == "github" || "$provider" == "linear") ]] && [[ "$selection" == "🚫 Do not show me auto select again" ]]; then
      _disable_autoselect
      gum style --foreground 3 "Auto-select disabled. You can re-enable it from the bottom of the issue list."
      # Recursively call to show the updated list
      _aw_issue "$@"
      return $?

    elif [[ "$provider" == "github" ]] && [[ "$selection" == "⚡ Auto select next issue" ]]; then
      _enable_autoselect
      gum style --foreground 2 "Auto-select re-enabled!"
      # Recursively call to show the updated list
      _aw_issue "$@"
      return $?

    else
      # Normal issue selection (works for both GitHub and JIRA)
      issue_id=$(echo "$selection" | sed 's/^● *//' | sed 's/^#//' | cut -d'|' -f1 | tr -d ' ')
    fi
  fi

  # Fetch issue details including body
  local title=""
  local body=""

  if [[ "$provider" == "jira" ]]; then
    _aw_jira_get_issue_details "$issue_id" || {
      gum style --foreground 1 "Could not fetch JIRA issue $issue_id"
      return 1
    }
  elif [[ "$provider" == "gitlab" ]]; then
    _aw_gitlab_get_issue_details "$issue_id" || {
      gum style --foreground 1 "Could not fetch GitLab issue #$issue_id"
      return 1
    }
  elif [[ "$provider" == "linear" ]]; then
    _aw_linear_get_issue_details "$issue_id" || {
      gum style --foreground 1 "Could not fetch Linear issue $issue_id"
      return 1
    }
  else
    title=$(gh issue view "$issue_id" --json title --jq '.title' 2>/dev/null)
    body=$(gh issue view "$issue_id" --json body --jq '.body // ""' 2>/dev/null)

    if [[ -z "$title" ]]; then
      gum style --foreground 1 "Could not fetch GitHub issue #$issue_id"
      return 1
    fi
  fi

  # Check if a worktree already exists for this issue
  local existing_worktree
  existing_worktree=$(_aw_find_worktree_for_issue "$issue_id" "$provider")

  # If an active worktree exists for this issue, offer to resume it
  if [[ -n "$existing_worktree" ]]; then
    echo ""
    if [[ "$provider" == "jira" ]]; then
      gum style --foreground 3 "Active worktree found for JIRA issue $issue_id:"
    else
      gum style --foreground 3 "Active worktree found for GitHub issue #$issue_id:"
    fi
    echo "  $existing_worktree"
    echo ""

    if gum confirm "Resume existing worktree?"; then
      cd "$existing_worktree" || return 1

      # Set terminal title
      if [[ "$provider" == "jira" ]]; then
        printf '\033]0;JIRA %s - %s\007' "$issue_id" "$title"
      else
        printf '\033]0;GitHub Issue #%s - %s\007' "$issue_id" "$title"
      fi

      _resolve_ai_command || return 1

      if [[ "${AI_CMD[1]}" != "skip" ]]; then
        gum style --foreground 2 "Starting $AI_CMD_NAME..."
        "${AI_CMD[@]}"
      else
        gum style --foreground 3 "Skipping AI tool - worktree is ready for manual work"
      fi
      return 0
    else
      echo ""
      gum style --foreground 3 "Continuing to create new worktree..."
      echo ""
    fi
  fi

  # Generate suggested branch name
  local sanitized=$(_aw_sanitize_branch_name "$title" | cut -c1-40)
  local suggested=""

  if [[ "$provider" == "jira" ]]; then
    suggested="work/${issue_id}-${sanitized}"
  else
    suggested="work/${issue_id}-${sanitized}"
  fi

  echo ""
  if [[ "$provider" == "jira" ]]; then
    gum style --border rounded --padding "0 1" --border-foreground 5 -- \
      "JIRA ${issue_id}" \
      "$title"
  else
    gum style --border rounded --padding "0 1" --border-foreground 5 -- \
      "Issue #${issue_id}" \
      "$title"
  fi

  echo ""
  gum style --foreground 6 "Confirm branch name:"
  local branch_name=$(gum input --value "$suggested" --placeholder "Branch name")

  if [[ -z "$branch_name" ]]; then
    gum style --foreground 3 "Cancelled"
    return $AW_EXIT_CANCELLED
  fi

  # Prepare context to pass to AI tool
  local ai_context=""
  if [[ "$provider" == "jira" ]]; then
    ai_context="I'm working on JIRA issue ${issue_id}.

Title: ${title}

${body}

Ask clarifying questions about the intended work if you can think of any."
  else
    ai_context="I'm working on GitHub issue #${issue_id}.

Title: ${title}

${body}

Ask clarifying questions about the intended work if you can think of any."
  fi

  # Set terminal title
  if [[ "$provider" == "jira" ]]; then
    printf '\033]0;JIRA %s - %s\007' "$issue_id" "$title"
  else
    printf '\033]0;GitHub Issue #%s - %s\007' "$issue_id" "$title"
  fi

  # For GitHub: register branch-issue link so PRs created from this branch
  # automatically associate with the issue in the Development section
  if [[ "$provider" == "github" ]]; then
    local base_branch
    base_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")
    if gh issue develop "$issue_id" --name "$branch_name" --base "$base_branch" >/dev/null 2>&1; then
      gum style --foreground 2 "Branch linked to issue #${issue_id}"
    fi
  fi

  _aw_create_worktree "$branch_name" "$ai_context"
}

