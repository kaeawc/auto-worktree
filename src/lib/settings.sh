#!/bin/bash

# ============================================================================
# Settings menu, display, warnings, labels
# ============================================================================
_aw_issue_provider_label() {
  local provider="$1"
  case "$provider" in
    github) echo "GitHub Issues" ;;
    gitlab) echo "GitLab Issues" ;;
    jira) echo "JIRA" ;;
    linear) echo "Linear Issues" ;;
    *) echo "not set" ;;
  esac
}

_aw_ai_preference_label() {
  local pref="$1"
  case "$pref" in
    claude) echo "Claude Code" ;;
    codex) echo "Codex CLI" ;;
    gemini) echo "Gemini CLI" ;;
    jules) echo "Google Jules CLI" ;;
    skip) echo "skip AI tool" ;;
    *) echo "auto (prompt when needed)" ;;
  esac
}

_aw_bool_label() {
  local value="$1"
  if [[ "$value" == "true" ]]; then
    echo "enabled"
  else
    echo "disabled"
  fi
}

_aw_clear_issue_provider_settings() {
  git config --unset auto-worktree.issue-provider 2>/dev/null
  git config --unset auto-worktree.jira-server 2>/dev/null
  git config --unset auto-worktree.jira-project 2>/dev/null
  git config --unset auto-worktree.gitlab-server 2>/dev/null
  git config --unset auto-worktree.gitlab-project 2>/dev/null
  git config --unset auto-worktree.linear-team 2>/dev/null
  gum style --foreground 2 "✓ Issue provider settings cleared"
}

_aw_show_settings_summary() {
  local provider=$(_aw_get_issue_provider)
  local provider_label=$(_aw_issue_provider_label "$provider")
  local jira_server=$(_aw_get_jira_server)
  local jira_project=$(_aw_get_jira_project)
  local gitlab_server=$(_aw_get_gitlab_server)
  local gitlab_project=$(_aw_get_gitlab_project)
  local linear_team=$(_aw_get_linear_team)
  local ai_pref=$(_load_ai_preference)
  local ai_label=$(_aw_ai_preference_label "$ai_pref")
  local issue_autoselect=$(_aw_get_issue_autoselect)
  local pr_autoselect=$(_aw_get_pr_autoselect)

  gum style --border rounded --padding "0 1" --border-foreground 4 \
    "Settings Summary" \
    "Issue provider: $provider_label" \
    "JIRA server: ${jira_server:-(unset)}" \
    "JIRA project: ${jira_project:-(unset)}" \
    "GitLab server: ${gitlab_server:-(unset)}" \
    "GitLab project: ${gitlab_project:-(unset)}" \
    "Linear team: ${linear_team:-(unset)}" \
    "AI tool preference: $ai_label" \
    "Issue auto-select: $(_aw_bool_label "$issue_autoselect")" \
    "PR auto-select: $(_aw_bool_label "$pr_autoselect")"
}

_aw_show_settings_warnings() {
  local provider=$(_aw_get_issue_provider)
  local warnings=()

  if [[ -z "$provider" ]]; then
    warnings+=("Issue provider not configured for this repository.")
  fi

  if [[ -d ".github/ISSUE_TEMPLATE" ]] || [[ -f ".github/ISSUE_TEMPLATE.md" ]]; then
    if [[ "$provider" != "github" ]]; then
      warnings+=("GitHub issue templates detected, but issue provider is not set to GitHub.")
    fi
  fi

  if [[ -n "$provider" ]]; then
    case "$provider" in
      github)
        if ! command -v gh &> /dev/null; then
          warnings+=("GitHub CLI (gh) not found. GitHub issue workflow will fail.")
        fi
        ;;
      gitlab)
        if ! command -v glab &> /dev/null; then
          warnings+=("GitLab CLI (glab) not found. GitLab issue workflow will fail.")
        fi
        ;;
      jira)
        if ! command -v jira &> /dev/null; then
          warnings+=("JIRA CLI (jira) not found. JIRA issue workflow will fail.")
        fi
        ;;
      linear)
        if ! command -v linear &> /dev/null; then
          warnings+=("Linear CLI (linear) not found. Linear issue workflow will fail.")
        fi
        ;;
    esac
  fi

  local ai_pref=$(_load_ai_preference)
  if [[ -n "$ai_pref" ]] && [[ "$ai_pref" != "skip" ]]; then
    case "$ai_pref" in
      claude)
        command -v claude &> /dev/null || warnings+=("AI preference set to Claude Code, but it is not installed.")
        ;;
      codex)
        command -v codex &> /dev/null || warnings+=("AI preference set to Codex CLI, but it is not installed.")
        ;;
      gemini)
        command -v gemini &> /dev/null || warnings+=("AI preference set to Gemini CLI, but it is not installed.")
        ;;
      jules)
        command -v jules &> /dev/null || warnings+=("AI preference set to Google Jules CLI, but it is not installed.")
        ;;
    esac
  fi

  if [[ ${#warnings[@]} -gt 0 ]]; then
    echo ""
    gum style --border rounded --padding "0 1" --border-foreground 3 \
      "Warnings / Suggestions" \
      "${warnings[@]}"
  fi
}

_aw_settings_issue_provider() {
  while true; do
    echo ""
    _aw_show_settings_summary

    local choice=$(gum choose \
      "Set issue provider" \
      "Configure JIRA" \
      "Configure GitLab" \
      "Configure Linear" \
      "Clear issue provider settings" \
      "Back")

    case "$choice" in
      "Set issue provider")
        local provider_choice=$(gum choose --header "Select issue provider" \
          "GitHub Issues" \
          "GitLab Issues" \
          "JIRA" \
          "Linear Issues" \
          "Unset" \
          "Back")

        case "$provider_choice" in
          "GitHub Issues") _aw_set_issue_provider "github" ;;
          "GitLab Issues") _aw_set_issue_provider "gitlab" ;;
          "JIRA") _aw_set_issue_provider "jira" ;;
          "Linear Issues") _aw_set_issue_provider "linear" ;;
          "Unset")
            git config --unset auto-worktree.issue-provider 2>/dev/null
            gum style --foreground 2 "✓ Issue provider unset"
            ;;
          *) ;;
        esac
        ;;
      "Configure JIRA") _aw_configure_jira ;;
      "Configure GitLab") _aw_configure_gitlab ;;
      "Configure Linear") _aw_configure_linear ;;
      "Clear issue provider settings") _aw_clear_issue_provider_settings ;;
      *) return 0 ;;
    esac
  done
}

_aw_settings_ai_tool() {
  while true; do
    local current_pref=$(_load_ai_preference)
    local current_label=$(_aw_ai_preference_label "$current_pref")

    local choice=$(gum choose --header "AI tool preference (current: $current_label)" \
      "Auto (prompt when needed)" \
      "Claude Code" \
      "Codex CLI" \
      "Gemini CLI" \
      "Google Jules CLI" \
      "Skip AI tool" \
      "Back")

    case "$choice" in
      "Auto (prompt when needed)")
        _save_ai_preference ""
        gum style --foreground 2 "✓ AI tool preference reset to auto"
        ;;
      "Claude Code")
        _save_ai_preference "claude"
        gum style --foreground 2 "✓ AI tool preference set to Claude Code"
        ;;
      "Codex CLI")
        _save_ai_preference "codex"
        gum style --foreground 2 "✓ AI tool preference set to Codex CLI"
        ;;
      "Gemini CLI")
        _save_ai_preference "gemini"
        gum style --foreground 2 "✓ AI tool preference set to Gemini CLI"
        ;;
      "Google Jules CLI")
        _save_ai_preference "jules"
        gum style --foreground 2 "✓ AI tool preference set to Google Jules CLI"
        ;;
      "Skip AI tool")
        _save_ai_preference "skip"
        gum style --foreground 2 "✓ AI tool preference set to skip"
        ;;
      *) return 0 ;;
    esac
  done
}

_aw_settings_autoselect() {
  while true; do
    local issue_autoselect=$(_aw_get_issue_autoselect)
    local pr_autoselect=$(_aw_get_pr_autoselect)
    local issue_label=$(_aw_bool_label "$issue_autoselect")
    local pr_label=$(_aw_bool_label "$pr_autoselect")

    local choice=$(gum choose --header "Auto-select settings (issues: $issue_label, PRs: $pr_label)" \
      "Toggle issue auto-select" \
      "Toggle PR auto-select" \
      "Reset auto-select to defaults" \
      "Back")

    case "$choice" in
      "Toggle issue auto-select")
        if [[ "$issue_autoselect" == "true" ]]; then
          _disable_autoselect
          gum style --foreground 2 "✓ Issue auto-select disabled"
        else
          _enable_autoselect
          gum style --foreground 2 "✓ Issue auto-select enabled"
        fi
        ;;
      "Toggle PR auto-select")
        if [[ "$pr_autoselect" == "true" ]]; then
          _disable_pr_autoselect
          gum style --foreground 2 "✓ PR auto-select disabled"
        else
          _enable_pr_autoselect
          gum style --foreground 2 "✓ PR auto-select enabled"
        fi
        ;;
      "Reset auto-select to defaults")
        git config --unset auto-worktree.issue-autoselect 2>/dev/null
        git config --unset auto-worktree.pr-autoselect 2>/dev/null
        gum style --foreground 2 "✓ Auto-select settings reset to defaults"
        ;;
      *) return 0 ;;
    esac
  done
}

_aw_settings_reset() {
  if ! gum confirm "Reset all auto-worktree settings for this repository?"; then
    gum style --foreground 3 "Cancelled"
    return 0
  fi

  _aw_clear_issue_provider_settings
  git config --unset auto-worktree.ai-tool 2>/dev/null
  git config --unset auto-worktree.issue-autoselect 2>/dev/null
  git config --unset auto-worktree.pr-autoselect 2>/dev/null
  gum style --foreground 2 "✓ All settings reset"
}

_aw_settings_menu() {
  _aw_ensure_git_repo || return 1
  _aw_get_repo_info

  while true; do
    echo ""
    _aw_show_settings_summary
    _aw_show_settings_warnings

    local choice=$(gum choose \
      "Issue provider settings" \
      "AI tool preference" \
      "Auto-select settings" \
      "Reset settings" \
      "Back")

    case "$choice" in
      "Issue provider settings") _aw_settings_issue_provider ;;
      "AI tool preference") _aw_settings_ai_tool ;;
      "Auto-select settings") _aw_settings_autoselect ;;
      "Reset settings") _aw_settings_reset ;;
      *) return 0 ;;
    esac
  done
}

_aw_prompt_issue_provider() {
  # Prompt user to choose issue provider if not configured
  echo ""
  gum style --foreground 6 "Issue provider not configured for this repository"
  echo ""

  local choice=$(gum choose \
    "GitHub Issues" \
    "GitLab Issues" \
    "JIRA" \
    "Linear Issues" \
    "Cancel")

  case "$choice" in
    "GitHub Issues")
      _aw_set_issue_provider "github"
      ;;
    "GitLab Issues")
      _aw_set_issue_provider "gitlab"
      _aw_configure_gitlab
      ;;
    "JIRA")
      _aw_set_issue_provider "jira"
      _aw_configure_jira
      ;;
    "Linear Issues")
      _aw_set_issue_provider "linear"
      _aw_configure_linear
      ;;
    *)
      gum style --foreground 3 "Cancelled"
      return 1
      ;;
  esac
}
