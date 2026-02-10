#\!/bin/bash
# ============================================================================
# Linear integration functions
# ============================================================================

_aw_linear_check_completed() {
  # Check if a Linear issue is completed/done/canceled
  # Returns 0 if completed, 1 if not completed or error
  local issue_id="$1"

  if [[ -z "$issue_id" ]]; then
    return 1
  fi

  # Get issue details using Linear CLI
  # The 'linear issue view' command outputs markdown with issue details
  local issue_view=$(linear issue view "$issue_id" 2>/dev/null)

  if [[ -z "$issue_view" ]]; then
    return 1
  fi

  # Extract state from the output (looking for State: or Status: lines)
  local state=$(echo "$issue_view" | grep -i "State:" | sed 's/.*State:[[:space:]]*//i' | tr -d '\r\n')

  if [[ -z "$state" ]]; then
    # Try alternative format
    state=$(echo "$issue_view" | grep -i "Status:" | sed 's/.*Status:[[:space:]]*//i' | tr -d '\r\n')
  fi

  if [[ -z "$state" ]]; then
    return 1
  fi

  # Common completed status names in Linear
  case "$state" in
    Done|Completed|Canceled|Cancelled)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

_aw_linear_list_issues() {
  # List Linear issues
  # Returns formatted issue list similar to GitHub issues
  local team=$(_aw_get_linear_team)

  # List issues using Linear CLI
  # Default: lists unstarted issues assigned to you
  # Use -A to list all team's unstarted issues
  local linear_cmd="linear issue list"

  # If a team is configured, we'll use -A to get all team issues
  # Note: Linear CLI doesn't have direct team filtering in list command
  # but it respects the LINEAR_TEAM_ID config
  if [[ -n "$team" ]]; then
    linear_cmd="linear issue list -A"
  fi

  # Execute the command and parse output
  # Linear CLI outputs a table format, we need to parse it
  $linear_cmd 2>/dev/null | tail -n +2 | awk '{
    # Parse Linear CLI table output
    # Expected format: ID    Title    State    ...
    if (NF >= 3 && $1 ~ /^[A-Z]+-[0-9]+$/) {
      id = $1
      # Extract title (everything between ID and State columns)
      # This is a simplified parser - may need adjustment based on actual output
      title = ""
      for (i=2; i<NF; i++) {
        if (title != "") title = title " "
        title = title $i
      }

      # Format: TEAM-123 | Title
      printf "%s | %s\n", id, title
    }
  }'
}

_aw_linear_get_issue_details() {
  # Get Linear issue details
  # Sets variables: title, body (description)
  local issue_id="$1"

  if [[ -z "$issue_id" ]]; then
    return 1
  fi

  # Get issue details using Linear CLI
  local issue_view=$(linear issue view "$issue_id" 2>/dev/null)

  if [[ -z "$issue_view" ]]; then
    return 1
  fi

  # Extract title - Linear outputs markdown format
  # Title is typically in a heading or after "Title:" label
  title=$(linear issue title "$issue_id" 2>/dev/null)

  if [[ -z "$title" ]]; then
    # Fallback: parse from view output
    title=$(echo "$issue_view" | grep -i "^# " | head -1 | sed 's/^# //')
  fi

  # Extract description/body from the markdown output
  # The description is the content after the metadata section
  body=$(echo "$issue_view" | sed -n '/^## Description/,/^##/p' | grep -v "^##" | sed 's/^[[:space:]]*//')

  # If body is empty, try to get any content after the header
  if [[ -z "$body" ]]; then
    body=$(echo "$issue_view" | sed '1,/^---$/d' | sed '/^$/d' | head -20)
  fi

  return 0
}

_aw_linear_list_milestones() {
  # Linear does not support project/milestone listing via CLI
  gum style --foreground 1 "Linear does not support project/milestone listing via CLI"
  return 1
}

_aw_linear_list_issues_by_milestone() {
  # Linear does not support filtering issues by project via CLI
  gum style --foreground 1 "Linear does not support filtering issues by project via CLI"
  return 1
}

