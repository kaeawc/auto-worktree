#!/bin/bash

# ============================================================================
# Project configuration (git config based)
# ============================================================================
_aw_get_issue_provider() {
  # Get the configured issue provider
  # Returns: github, gitlab, jira, linear, or empty string if not configured
  git config --get auto-worktree.issue-provider 2>/dev/null || echo ""
}

_aw_set_issue_provider() {
  # Set the issue provider for this repository
  local provider="$1"

  if [[ "$provider" != "github" ]] && [[ "$provider" != "jira" ]] && [[ "$provider" != "gitlab" ]] && [[ "$provider" != "linear" ]]; then
    gum style --foreground 1 "Error: Invalid provider. Must be 'github', 'gitlab', 'jira', or 'linear'"
    return 1
  fi

  git config auto-worktree.issue-provider "$provider"
  gum style --foreground 2 "✓ Issue provider set to: $provider"
}

_aw_get_jira_server() {
  # Get the configured JIRA server URL
  git config --get auto-worktree.jira-server 2>/dev/null || echo ""
}

_aw_set_jira_server() {
  # Set the JIRA server URL for this repository
  local server="$1"
  git config auto-worktree.jira-server "$server"
  gum style --foreground 2 "✓ JIRA server set to: $server"
}

_aw_get_jira_project() {
  # Get the configured default JIRA project key
  git config --get auto-worktree.jira-project 2>/dev/null || echo ""
}

_aw_set_jira_project() {
  # Set the default JIRA project key for this repository
  local project="$1"
  git config auto-worktree.jira-project "$project"
  gum style --foreground 2 "✓ JIRA project set to: $project"
}

_aw_get_gitlab_server() {
  # Get the configured GitLab server URL
  git config --get auto-worktree.gitlab-server 2>/dev/null || echo ""
}

_aw_set_gitlab_server() {
  # Set the GitLab server URL for this repository
  local server="$1"
  git config auto-worktree.gitlab-server "$server"
  gum style --foreground 2 "✓ GitLab server set to: $server"
}

_aw_get_gitlab_project() {
  # Get the configured default GitLab project path
  git config --get auto-worktree.gitlab-project 2>/dev/null || echo ""
}

_aw_set_gitlab_project() {
  # Set the default GitLab project path for this repository
  local project="$1"
  git config auto-worktree.gitlab-project "$project"
  gum style --foreground 2 "✓ GitLab project set to: $project"
}

_aw_get_issue_templates_dir() {
  # Get the configured issue templates directory for current provider
  git config --get auto-worktree.issue-templates-dir 2>/dev/null || echo ""
}

_aw_set_issue_templates_dir() {
  # Set the issue templates directory for this repository
  local dir="$1"
  git config auto-worktree.issue-templates-dir "$dir"
  gum style --foreground 2 "✓ Issue templates directory set to: $dir"
}

_aw_get_issue_templates_disabled() {
  # Check if user has disabled issue templates
  # Returns: "true" or "" (empty string means enabled)
  git config --get auto-worktree.issue-templates-disabled 2>/dev/null || echo ""
}

_aw_set_issue_templates_disabled() {
  # Disable issue templates for this repository
  local disabled="$1"  # "true" or "false"
  git config auto-worktree.issue-templates-disabled "$disabled"
}

_aw_get_issue_templates_prompt_disabled() {
  # Check if user wants to skip template prompts in future
  # Returns: "true" or "" (empty string means should prompt)
  git config --get auto-worktree.issue-templates-no-prompt 2>/dev/null || echo ""
}

_aw_set_issue_templates_prompt_disabled() {
  # Set whether to prompt for templates in future
  local disabled="$1"  # "true" or "false"
  git config auto-worktree.issue-templates-no-prompt "$disabled"
}

_aw_get_issue_templates_detected_flag() {
  # Check if we've already notified user about detected templates
  git config --get auto-worktree.issue-templates-detected 2>/dev/null || echo ""
}

_aw_set_issue_templates_detected_flag() {
  # Set flag that we've notified user about templates
  git config auto-worktree.issue-templates-detected "true"
}

_aw_detect_issue_templates() {
  # Auto-detect issue templates for the current provider
  # Args: $1 = provider (github, gitlab, jira, linear)
  # Returns: List of template files (one per line), or empty if none found
  local provider="$1"
  local templates_dir=""

  # Check if user has a custom templates directory configured
  local custom_dir=$(_aw_get_issue_templates_dir)
  if [[ -n "$custom_dir" ]] && [[ -d "$custom_dir" ]]; then
    templates_dir="$custom_dir"
  else
    # Use conventional directories based on provider
    case "$provider" in
      github)
        if [[ -d ".github/ISSUE_TEMPLATE" ]]; then
          templates_dir=".github/ISSUE_TEMPLATE"
        fi
        ;;
      gitlab)
        if [[ -d ".gitlab/issue_templates" ]]; then
          templates_dir=".gitlab/issue_templates"
        fi
        ;;
      jira)
        if [[ -d ".jira/issue_templates" ]]; then
          templates_dir=".jira/issue_templates"
        fi
        ;;
      linear)
        if [[ -d ".linear/issue_templates" ]]; then
          templates_dir=".linear/issue_templates"
        fi
        ;;
    esac
  fi

  # Find all .md files in the templates directory
  if [[ -n "$templates_dir" ]] && [[ -d "$templates_dir" ]]; then
    find "$templates_dir" -maxdepth 1 -name "*.md" -type f 2>/dev/null | sort
  fi
}

_aw_get_template_default_dir() {
  # Get the default template directory for a provider
  # Args: $1 = provider (github, gitlab, jira, linear)
  # Returns: Default directory path
  local provider="$1"

  case "$provider" in
    github)
      echo ".github/ISSUE_TEMPLATE"
      ;;
    gitlab)
      echo ".gitlab/issue_templates"
      ;;
    jira)
      echo ".jira/issue_templates"
      ;;
    linear)
      echo ".linear/issue_templates"
      ;;
  esac
}

_aw_configure_issue_templates() {
  # Interactive configuration for issue templates
  # Args: $1 = provider (github, gitlab, jira, linear)
  # Returns: 0 if templates configured/enabled, 1 if user opts out
  local provider="$1"

  echo ""
  gum style --foreground 6 "Configure Issue Templates"
  echo ""

  # Try to auto-detect templates
  local detected_templates=$(_aw_detect_issue_templates "$provider")
  local default_dir=$(_aw_get_template_default_dir "$provider")

  if [[ -n "$detected_templates" ]]; then
    local template_count=$(echo "$detected_templates" | wc -l | tr -d ' ')
    gum style --foreground 2 "✓ Found $template_count template(s) in $default_dir"
    echo ""

    if gum confirm "Use these templates for issue creation?"; then
      _aw_set_issue_templates_disabled "false"
      return 0
    fi
  else
    gum style --foreground 3 "No templates found in $default_dir"
    echo ""
  fi

  # Ask if user wants to specify custom directory
  if gum confirm "Specify a custom templates directory?"; then
    echo ""
    gum style --foreground 6 "Templates directory path:"
    local custom_dir=$(gum input --placeholder "$default_dir")

    if [[ -n "$custom_dir" ]]; then
      if [[ -d "$custom_dir" ]]; then
        _aw_set_issue_templates_dir "$custom_dir"
        _aw_set_issue_templates_disabled "false"
        return 0
      else
        gum style --foreground 1 "Error: Directory does not exist: $custom_dir"
      fi
    fi
  fi

  # User doesn't want templates - ask about future prompts
  echo ""
  gum style --foreground 3 "Templates will not be used."
  echo ""

  if gum confirm "Skip template prompts for future issue creation?"; then
    _aw_set_issue_templates_prompt_disabled "true"
    gum style --foreground 4 "To re-enable templates later, run:"
    echo "  git config auto-worktree.issue-templates-no-prompt false"
  else
    _aw_set_issue_templates_prompt_disabled "false"
  fi

  _aw_set_issue_templates_disabled "true"
  return 1
}

_aw_configure_jira() {
  # Interactive configuration for JIRA
  echo ""
  gum style --foreground 6 "Configure JIRA for this repository"
  echo ""

  # Get JIRA server URL
  local current_server=$(_aw_get_jira_server)
  gum style --foreground 6 "JIRA Server URL:"
  local server=$(gum input --placeholder "https://your-company.atlassian.net" \
    --value "$current_server")

  if [[ -z "$server" ]]; then
    gum style --foreground 3 "Cancelled"
    return 1
  fi

  _aw_set_jira_server "$server"

  # Get default JIRA project key
  local current_project=$(_aw_get_jira_project)
  echo ""
  gum style --foreground 6 "Default JIRA Project Key (optional, can filter issues):"
  local project=$(gum input --placeholder "PROJ" \
    --value "$current_project")

  if [[ -n "$project" ]]; then
    _aw_set_jira_project "$project"
  fi

  echo ""
  gum style --foreground 2 "JIRA configuration complete!"
  echo ""
  echo "Note: Make sure you've configured the JIRA CLI:"
  echo "  jira init"
  echo ""
}

_aw_configure_gitlab() {
  # Interactive configuration for GitLab
  echo ""
  gum style --foreground 6 "Configure GitLab for this repository"
  echo ""

  # Get GitLab server URL
  local current_server=$(_aw_get_gitlab_server)
  local server=$(gum input --placeholder "https://gitlab.com (or https://gitlab.example.com for self-hosted)" \
    --value "$current_server" \
    --header "GitLab Server URL (leave empty for gitlab.com default):")

  if [[ -n "$server" ]]; then
    _aw_set_gitlab_server "$server"
  fi

  # Get default GitLab project path
  local current_project=$(_aw_get_gitlab_project)
  local project=$(gum input --placeholder "group/project" \
    --value "$current_project" \
    --header "Default GitLab Project Path (optional, can filter issues/MRs):")

  if [[ -n "$project" ]]; then
    _aw_set_gitlab_project "$project"
  fi

  echo ""
  gum style --foreground 2 "GitLab configuration complete!"
  echo ""
  echo "Note: Make sure you've authenticated with the GitLab CLI:"
  echo "  glab auth login"
  echo ""
}

_aw_get_linear_team() {
  # Get the configured default Linear team key
  git config --get auto-worktree.linear-team 2>/dev/null || echo ""
}

_aw_set_linear_team() {
  # Set the default Linear team key for this repository
  local team="$1"
  git config auto-worktree.linear-team "$team"
  gum style --foreground 2 "✓ Linear team set to: $team"
}

_aw_configure_linear() {
  # Interactive configuration for Linear
  echo ""
  gum style --foreground 6 "Configure Linear for this repository"
  echo ""

  # Get default Linear team key
  local current_team=$(_aw_get_linear_team)
  local team=$(gum input --placeholder "TEAM" \
    --value "$current_team" \
    --header "Default Linear Team Key (optional, can filter issues):")

  if [[ -n "$team" ]]; then
    _aw_set_linear_team "$team"
  fi

  echo ""
  gum style --foreground 2 "Linear configuration complete!"
  echo ""
  echo "Note: Make sure you've configured the Linear CLI:"
  echo "  1. Create an API key at https://linear.app/settings/account/security"
  echo "  2. Set environment variable: export LINEAR_API_KEY=your_key_here"
  echo ""
}

