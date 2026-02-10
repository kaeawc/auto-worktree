#\!/bin/bash
# ============================================================================
# JIRA integration functions
# ============================================================================

_aw_jira_check_resolved() {
  # Check if a JIRA issue is resolved/done/closed
  # Returns 0 if resolved, 1 if not resolved or error
  local jira_key="$1"

  if [[ -z "$jira_key" ]]; then
    return 1
  fi

  # Get issue status using JIRA CLI
  local status=$(jira issue view "$jira_key" --plain --columns status 2>/dev/null | tail -1 | awk '{print $NF}')

  if [[ -z "$status" ]]; then
    return 1
  fi

  # Common resolved status names in JIRA
  # Note: Status names can vary by JIRA configuration, but these are common
  case "$status" in
    Done|Closed|Resolved|Complete|Completed)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

_aw_jira_list_issues() {
  # List JIRA issues using JQL
  # Returns formatted issue list similar to GitHub issues
  local project=$(_aw_get_jira_project)
  local jql="status != Done AND status != Closed AND status != Resolved"

  # If a default project is configured, filter by it
  if [[ -n "$project" ]]; then
    jql="project = $project AND ($jql)"
  fi

  # Use JIRA CLI to list issues
  # Output format: KEY | Summary | [Labels]
  jira issue list --jql "$jql" --plain --columns key,summary,labels --no-headers 2>/dev/null | \
    awk -F'\t' '{
      key = $1
      summary = $2
      labels = $3

      # Format similar to GitHub issue list
      printf "%s | %s", key, summary
      if (labels != "" && labels != "∅") {
        # Split labels and format them
        gsub(/,/, "][", labels)
        printf " | [%s]", labels
      }
      printf "\n"
    }'
}

_aw_jira_get_issue_details() {
  # Get JIRA issue details
  # Sets variables: title, body (description)
  local jira_key="$1"

  if [[ -z "$jira_key" ]]; then
    return 1
  fi

  # Get issue details in JSON format
  local issue_json=$(jira issue view "$jira_key" --plain --columns summary,description 2>/dev/null)

  if [[ -z "$issue_json" ]]; then
    return 1
  fi

  # Extract summary (title) and description (body)
  # The plain format outputs tab-separated values
  title=$(echo "$issue_json" | grep -A1 "Summary" | tail -1 | sed 's/^[[:space:]]*//')
  body=$(echo "$issue_json" | grep -A1 "Description" | tail -1 | sed 's/^[[:space:]]*//')

  # If description is empty or just "∅", set to empty string
  if [[ "$body" == "∅" ]] || [[ "$body" == "" ]]; then
    body=""
  fi

  return 0
}

_aw_jira_list_epics() {
  # List open JIRA epics
  # Output format: KEY | Summary | [Status]
  local project=$(_aw_get_jira_project)
  local jql="type = Epic AND statusCategory != Done"

  if [[ -n "$project" ]]; then
    jql="project = $project AND ($jql)"
  fi

  jira issue list --jql "$jql" --plain --columns key,summary,status --no-headers 2>/dev/null | \
    awk -F'\t' '{
      key = $1
      summary = $2
      status = $3

      printf "%s | %s", key, summary
      if (status != "" && status != "∅") {
        printf " | [%s]", status
      }
      printf "\n"
    }'
}

_aw_jira_list_issues_by_epic() {
  # List open issues linked to a specific epic
  # Args: $1 = epic key (e.g., PROJ-123)
  # Output format: KEY | Summary | [Labels]
  local epic_key="$1"
  local project=$(_aw_get_jira_project)

  if [[ -z "$epic_key" ]]; then
    return 1
  fi

  local jql="(\"Epic Link\" = $epic_key OR parent = $epic_key) AND statusCategory != Done"
  if [[ -n "$project" ]]; then
    jql="project = $project AND ($jql)"
  fi

  jira issue list --jql "$jql" --plain --columns key,summary,labels --no-headers 2>/dev/null | \
    awk -F'\t' '{
      key = $1
      summary = $2
      labels = $3

      printf "%s | %s", key, summary
      if (labels != "" && labels != "∅") {
        gsub(/,/, "][", labels)
        printf " | [%s]", labels
      }
      printf "\n"
    }'
}

# ============================================================================
# Linear integration functions
# ============================================================================

