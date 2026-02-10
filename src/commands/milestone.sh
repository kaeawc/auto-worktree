#!/bin/bash

# ============================================================================
# Milestone / Epic integration
# ============================================================================
_aw_milestone() {
  _aw_ensure_git_repo || return 1
  _aw_get_repo_info

  # Determine issue provider
  local provider=$(_aw_get_issue_provider)

  # If not configured, prompt user to choose
  if [[ -z "$provider" ]]; then
    _aw_prompt_issue_provider || return 1
    provider=$(_aw_get_issue_provider)
  fi

  # Check for provider-specific dependencies
  _aw_check_issue_provider_deps "$provider" || return 1

  local terminology=$(_aw_milestone_terminology "$provider")
  local term_lower=$(echo "$terminology" | tr '[:upper:]' '[:lower:]')

  gum style --foreground 6 "Provider: $(echo "$provider" | tr '[:lower:]' '[:upper:]')"
  echo "Selecting ${terminology}..."
  echo ""

  # Outer loop: milestone selection
  while true; do
    local milestone_id=""
    local milestone_title=""

    _aw_select_milestone "$provider" "$terminology" || return 0

    # milestone_id and milestone_title are set by _aw_select_milestone

    if [[ -z "$milestone_id" ]]; then
      return 0
    fi

    # Inner loop: issue selection within milestone
    while true; do
      local issue_id=""

      _aw_select_issue_by_milestone "$provider" "$milestone_id" "$milestone_title" "$terminology"
      local select_rc=$?

      if [[ $select_rc -ne 0 ]]; then
        # User cancelled - return to milestone selection
        echo ""
        gum style --foreground 3 "Returning to ${term_lower} selection..."
        echo ""
        break
      fi

      if [[ -z "$issue_id" ]]; then
        echo ""
        gum style --foreground 3 "Returning to ${term_lower} selection..."
        echo ""
        break
      fi

      # Work on the selected issue (reuse existing issue flow)
      _aw_issue "$issue_id"
      return $?
    done
  done
}

_aw_select_milestone() {
  # Interactive milestone/epic selector
  # Args: $1 = provider, $2 = terminology
  # Sets: milestone_id, milestone_title (in caller scope)
  local provider="$1"
  local terminology="$2"
  local term_lower=$(echo "$terminology" | tr '[:upper:]' '[:lower:]')

  # Fetch milestones
  local milestones=""
  gum spin --spinner dot --title "Fetching ${term_lower}s..." -- sleep 0.1

  case "$provider" in
    github) milestones=$(_aw_github_list_milestones) ;;
    gitlab) milestones=$(_aw_gitlab_list_milestones) ;;
    jira)   milestones=$(_aw_jira_list_epics) ;;
    linear) milestones=$(_aw_linear_list_milestones) ;;
  esac

  if [[ -z "$milestones" ]]; then
    gum style --foreground 1 "No open ${term_lower}s found"
    return 1
  fi

  # Show filterable list
  local selection
  selection=$(echo "$milestones" | gum filter --placeholder "Type to filter ${term_lower}s...")

  if [[ -z "$selection" ]]; then
    gum style --foreground 3 "Cancelled"
    return 1
  fi

  # Extract milestone ID and title from selection
  # Format: "ID | Title | [labels...]" or "KEY | Title | [labels...]"
  milestone_id=$(echo "$selection" | cut -d'|' -f1 | tr -d ' ')
  milestone_title=$(echo "$selection" | cut -d'|' -f2 | sed 's/^ *//;s/ *$//')

  return 0
}

_aw_select_issue_by_milestone() {
  # Interactive issue selector filtered by milestone
  # Args: $1 = provider, $2 = milestone_id, $3 = milestone_title, $4 = terminology
  # Sets: issue_id (in caller scope)
  local provider="$1"
  local ms_id="$2"
  local ms_title="$3"
  local terminology="$4"
  local term_lower=$(echo "$terminology" | tr '[:upper:]' '[:lower:]')

  # Fetch issues for this milestone
  local issues=""
  gum spin --spinner dot --title "Fetching issues for ${term_lower} \"${ms_title}\"..." -- sleep 0.1

  case "$provider" in
    github) issues=$(_aw_github_list_issues_by_milestone "$ms_title") ;;
    gitlab) issues=$(_aw_gitlab_list_issues_by_milestone "$ms_title") ;;
    jira)   issues=$(_aw_jira_list_issues_by_epic "$ms_id") ;;
    linear)
      gum style --foreground 1 "Linear does not support filtering issues by project via CLI"
      return 1
      ;;
  esac

  if [[ -z "$issues" ]]; then
    gum style --foreground 1 "No open issues found in ${term_lower} \"${ms_title}\""
    return 1
  fi

  # Show filterable list
  local selection
  selection=$(echo "$issues" | gum filter --placeholder "Select an issue from ${term_lower} \"${ms_title}\"")

  if [[ -z "$selection" ]]; then
    return 1
  fi

  # Extract issue ID from selection
  # GitHub/GitLab format: "#123 | Title..." -> extract number
  # JIRA format: "PROJ-123 | Title..." -> extract key
  issue_id=$(echo "$selection" | sed 's/^#//' | cut -d'|' -f1 | tr -d ' ')

  return 0
}
