#!/bin/bash

# ============================================================================
# GitHub integration
# ============================================================================

_aw_github_list_milestones() {
  # List open GitHub milestones
  # Output format: ID | Title | [N open] [N closed] [due: DATE]
  local owner repo
  owner=$(gh repo view --json owner --jq '.owner.login' 2>/dev/null)
  repo=$(gh repo view --json name --jq '.name' 2>/dev/null)

  if [[ -z "$owner" ]] || [[ -z "$repo" ]]; then
    return 1
  fi

  gh api "repos/$owner/$repo/milestones" --jq '.[] | select(.state == "open")' 2>/dev/null | \
    jq -r '[.number, .title, .open_issues, .closed_issues, .due_on // ""] | @tsv' | \
    while IFS=$'\t' read -r number title open_count closed_count due_on; do
      local labels=""
      if [[ "$open_count" -gt 0 ]] || [[ "$closed_count" -gt 0 ]]; then
        labels=" | [${open_count} open] [${closed_count} closed]"
      fi
      if [[ -n "$due_on" ]]; then
        labels="${labels} [due: ${due_on%%T*}]"
      fi
      echo "${number} | ${title}${labels}"
    done
}

_aw_github_list_issues() {
  # List open GitHub issues
  # Output format: #NUMBER | Title | [label1][label2]
  local project="${1:-}"

  gh issue list --limit 100 --state open --json number,title,labels \
    --template '{{range .}}#{{.number}} | {{.title}}{{if .labels}} |{{range .labels}} [{{.name}}]{{end}}{{end}}{{"\n"}}{{end}}' 2>/dev/null || true
}

_aw_github_get_issue_details() {
  # Get GitHub issue details
  # Sets variables: title, body (description)
  local issue_id="$1"

  if [[ -z "$issue_id" ]]; then
    return 1
  fi

  # Strip leading # if present
  local number="${issue_id#\#}"

  # Get issue details in JSON format
  local issue_json
  issue_json=$(gh issue view "$number" --json number,title,body,state,labels 2>/dev/null)

  if [[ -z "$issue_json" ]]; then
    return 1
  fi

  # Extract title and body using jq
  title=$(echo "$issue_json" | jq -r '.title // ""')
  body=$(echo "$issue_json" | jq -r '.body // ""')

  return 0
}

_aw_github_check_closed() {
  # Check if a GitHub issue is closed (regardless of merge/PR status)
  # Returns 0 if closed, 1 if open or error
  # Sets _AW_ISSUE_HAS_PR=true if there's an open PR for this issue
  local issue_num="$1"

  if [[ -z "$issue_num" ]]; then
    return 1
  fi

  # Strip leading # if present
  local number="${issue_num#\#}"

  local issue_state
  issue_state=$(gh issue view "$number" --json state --jq '.state' 2>/dev/null)

  if [[ "$issue_state" != "CLOSED" ]]; then
    return 1
  fi

  # Check if there's an open PR that references this issue
  local open_prs
  open_prs=$(gh pr list --state open --search "closes #$number OR fixes #$number OR resolves #$number" --json number --jq 'length' 2>/dev/null)

  if [[ "$open_prs" -gt 0 ]] 2>/dev/null; then
    _AW_ISSUE_HAS_PR=true
  else
    _AW_ISSUE_HAS_PR=false
  fi

  return 0
}

_aw_github_check_issue_merged() {
  # Check if a GitHub issue or its linked PR was merged into main
  # Returns 0 if merged, 1 if not merged or error
  local issue_num="$1"

  if [[ -z "$issue_num" ]]; then
    return 1
  fi

  # Strip leading # if present
  local number="${issue_num#\#}"

  # First check if issue is closed
  local issue_state
  issue_state=$(gh issue view "$number" --json state --jq '.state' 2>/dev/null)

  if [[ "$issue_state" != "CLOSED" ]]; then
    return 1
  fi

  # Check if there's a linked PR that was merged
  # GitHub's stateReason can tell us if it was completed (often means PR merged)
  local state_reason
  state_reason=$(gh issue view "$number" --json stateReason --jq '.stateReason' 2>/dev/null)

  if [[ "$state_reason" == "COMPLETED" ]]; then
    return 0
  fi

  # Also check for PRs that reference this issue and are merged
  local merged_prs
  merged_prs=$(gh pr list --state merged --search "closes #$number OR fixes #$number OR resolves #$number" --json number --jq 'length' 2>/dev/null)

  if [[ "$merged_prs" -gt 0 ]] 2>/dev/null; then
    return 0
  fi

  return 1
}

_aw_github_check_branch_pr_merged() {
  # Check if the branch itself has a merged PR (GitHub)
  # Returns 0 if merged, 1 if not
  local branch_name="$1"

  if [[ -z "$branch_name" ]]; then
    return 1
  fi

  local pr_state
  pr_state=$(gh pr view "$branch_name" --json state --jq '.state' 2>/dev/null)

  if [[ "$pr_state" == "MERGED" ]]; then
    return 0
  fi

  return 1
}

_aw_github_list_issues_by_milestone() {
  # List open issues for a specific milestone
  # Args: $1 = milestone title
  # Output format: #NUMBER | Title | [label1] [label2]
  local milestone_title="$1"

  if [[ -z "$milestone_title" ]]; then
    return 1
  fi

  gh issue list --milestone "$milestone_title" --limit 100 --state open --json number,title,labels \
    --template '{{range .}}#{{.number}} | {{.title}}{{if .labels}} |{{range .labels}} [{{.name}}]{{end}}{{end}}{{"\n"}}{{end}}' 2>/dev/null
}

