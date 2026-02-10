#\!/bin/bash
# ============================================================================
# GitLab integration functions
# ============================================================================

_aw_gitlab_check_closed() {
  # Check if a GitLab issue or MR is closed/merged
  # Returns 0 if closed/merged, 1 if open or error
  local id="$1"
  local type="${2:-issue}"  # 'issue' or 'mr'

  if [[ -z "$id" ]]; then
    return 1
  fi

  # Build glab command with server option if configured
  local glab_cmd="glab"
  local server=$(_aw_get_gitlab_server)
  if [[ -n "$server" ]]; then
    glab_cmd="glab --host $server"
  fi

  # Get state using glab CLI
  local state
  if [[ "$type" == "mr" ]]; then
    state=$($glab_cmd mr view "$id" --json state --jq '.state' 2>/dev/null)
  else
    state=$($glab_cmd issue view "$id" --json state --jq '.state' 2>/dev/null)
  fi

  if [[ -z "$state" ]]; then
    return 1
  fi

  # GitLab states: "opened", "closed", "merged" (for MRs)
  case "$state" in
    closed|merged)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

_aw_gitlab_list_issues() {
  # List GitLab issues
  # Returns formatted issue list similar to GitHub issues
  local project=$(_aw_get_gitlab_project)

  # Build glab command with server option if configured
  local glab_cmd="glab"
  local server=$(_aw_get_gitlab_server)
  if [[ -n "$server" ]]; then
    glab_cmd="glab --host $server"
  fi

  # Add project filter if configured
  local project_args=""
  if [[ -n "$project" ]]; then
    project_args="--repo $project"
  fi

  # List open issues with glab
  $glab_cmd issue list --state opened --per-page 100 $project_args 2>/dev/null | \
    awk -F'\t' '{
      # glab output format: #NUMBER  TITLE  (LABELS)  (TIME)
      # Extract issue number, title, and labels
      if ($1 ~ /^#[0-9]+/) {
        number = $1
        title = $2
        labels = $3

        # Format: #123 | Title | [label1][label2]
        printf "%s | %s", number, title
        if (labels != "" && labels != "()") {
          # Clean up labels format
          gsub(/[()]/, "", labels)
          gsub(/, /, "][", labels)
          printf " | [%s]", labels
        }
        printf "\n"
      }
    }'
}

_aw_gitlab_get_issue_details() {
  # Get GitLab issue details
  # Sets variables: title, body (description)
  local issue_id="$1"

  if [[ -z "$issue_id" ]]; then
    return 1
  fi

  # Build glab command with server option if configured
  local glab_cmd="glab"
  local server=$(_aw_get_gitlab_server)
  if [[ -n "$server" ]]; then
    glab_cmd="glab --host $server"
  fi

  # Get issue details in JSON format
  local issue_json=$($glab_cmd issue view "$issue_id" --json title,description 2>/dev/null)

  if [[ -z "$issue_json" ]]; then
    return 1
  fi

  # Extract title and description using jq
  title=$(echo "$issue_json" | jq -r '.title // ""')
  body=$(echo "$issue_json" | jq -r '.description // ""')

  return 0
}

_aw_gitlab_list_mrs() {
  # List GitLab merge requests
  # Returns formatted MR list similar to GitHub PRs
  local project=$(_aw_get_gitlab_project)

  # Build glab command with server option if configured
  local glab_cmd="glab"
  local server=$(_aw_get_gitlab_server)
  if [[ -n "$server" ]]; then
    glab_cmd="glab --host $server"
  fi

  # Add project filter if configured
  local project_args=""
  if [[ -n "$project" ]]; then
    project_args="--repo $project"
  fi

  # List open MRs with glab
  $glab_cmd mr list --state opened --per-page 100 $project_args 2>/dev/null | \
    awk -F'\t' '{
      # glab output format: !NUMBER  TITLE  (BRANCH)  (TIME)
      # Extract MR number, title, and branch
      if ($1 ~ /^![0-9]+/) {
        number = $1
        title = $2
        branch = $3

        # Format: !123 | Title | (branch-name)
        printf "%s | %s", number, title
        if (branch != "") {
          printf " | %s", branch
        }
        printf "\n"
      }
    }'
}

_aw_gitlab_get_mr_details() {
  # Get GitLab MR details
  # Sets variables: title, body (description), source_branch, target_branch
  local mr_id="$1"

  if [[ -z "$mr_id" ]]; then
    return 1
  fi

  # Build glab command with server option if configured
  local glab_cmd="glab"
  local server=$(_aw_get_gitlab_server)
  if [[ -n "$server" ]]; then
    glab_cmd="glab --host $server"
  fi

  # Get MR details in JSON format
  local mr_json=$($glab_cmd mr view "$mr_id" --json title,description,sourceBranch,targetBranch 2>/dev/null)

  if [[ -z "$mr_json" ]]; then
    return 1
  fi

  # Extract details using jq
  title=$(echo "$mr_json" | jq -r '.title // ""')
  body=$(echo "$mr_json" | jq -r '.description // ""')
  source_branch=$(echo "$mr_json" | jq -r '.sourceBranch // ""')
  target_branch=$(echo "$mr_json" | jq -r '.targetBranch // ""')

  return 0
}

_aw_gitlab_check_mr_merged() {
  # Check if a GitLab MR is merged for a given branch
  # Returns 0 if merged, 1 if not merged or error
  local branch_name="$1"

  if [[ -z "$branch_name" ]]; then
    return 1
  fi

  # Build glab command with server option if configured
  local glab_cmd="glab"
  local server=$(_aw_get_gitlab_server)
  if [[ -n "$server" ]]; then
    glab_cmd="glab --host $server"
  fi

  # Check if there's a merged MR for this branch
  local mr_state=$($glab_cmd mr view "$branch_name" --json state 2>/dev/null | jq -r '.state')

  if [[ "$mr_state" == "merged" ]]; then
    return 0
  fi

  return 1
}

