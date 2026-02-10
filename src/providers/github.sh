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

