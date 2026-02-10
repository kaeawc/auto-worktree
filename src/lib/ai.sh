#!/bin/bash

# ============================================================================
# AI Command Resolution
# ============================================================================

# Check whether the active AI tool has a resumable session in the current directory
_ai_has_resumable_session() {
  case "$AI_CMD_NAME" in
    "Claude Code")        [[ -d ".claude" ]] ;;
    "Codex")              [[ -d ".codex" ]] ;;
    "Gemini CLI")         [[ -d ".gemini" ]] ;;
    *)                    return 1 ;;
  esac
}

_load_ai_preference() {
  git config --get auto-worktree.ai-tool 2>/dev/null || echo ""
}

# Save AI tool preference (per-repository git config)
_save_ai_preference() {
  local tool="$1"
  if [[ -z "$tool" ]]; then
    git config --unset auto-worktree.ai-tool 2>/dev/null
  else
    git config auto-worktree.ai-tool "$tool"
  fi
}

_aw_get_issue_autoselect() {
  local value
  value=$(git config --get --bool auto-worktree.issue-autoselect 2>/dev/null || echo "")
  if [[ -z "$value" ]]; then
    echo "true"
  else
    echo "$value"
  fi
}

_aw_get_pr_autoselect() {
  local value
  value=$(git config --get --bool auto-worktree.pr-autoselect 2>/dev/null || echo "")
  if [[ -z "$value" ]]; then
    echo "true"
  else
    echo "$value"
  fi
}

# Check if auto-select is disabled
_is_autoselect_disabled() {
  [[ "$(_aw_get_issue_autoselect)" == "false" ]]
}

# Disable auto-select
_disable_autoselect() {
  git config auto-worktree.issue-autoselect false
}

# Enable auto-select
_enable_autoselect() {
  git config auto-worktree.issue-autoselect true
}

# Check if PR auto-select is disabled
_is_pr_autoselect_disabled() {
  [[ "$(_aw_get_pr_autoselect)" == "false" ]]
}

# Disable PR auto-select
_disable_pr_autoselect() {
  git config auto-worktree.pr-autoselect false
}

# Enable PR auto-select
_enable_pr_autoselect() {
  git config auto-worktree.pr-autoselect true
}

# AI-powered issue selection - filters to top 5 issues in priority order
_ai_select_issues() {
  local issues="$1"
  local highlighted_issues="$2"
  local repo_info="$3"

  # Create a temporary file with the issue list
  local temp_issues=$(mktemp)
  echo "$issues" > "$temp_issues"

  # Prepare the prompt for AI
  local prompt="Analyze the following GitHub issues and select the top 5 issues that would be best to work on next. Consider:
- Priority labels (high priority, urgent, etc.)
- Issue type (bug fixes are often higher priority than features)
- Labels like 'good first issue' or 'help wanted'
- Issue complexity and impact
- Any context from the repository: $repo_info

Return ONLY the top 5 issue numbers in priority order (one per line), formatted as just the numbers (e.g., '42').

Issues:
$(cat "$temp_issues")

Return only the 5 issue numbers, one per line, nothing else."

  # Use the configured AI tool to select issues
  _resolve_ai_command || {
    rm -f "$temp_issues"
    return 1
  }

  if [[ "${AI_CMD[1]}" == "skip" ]]; then
    rm -f "$temp_issues"
    return 1
  fi

  # Run AI command with the prompt
  local selected_numbers
  selected_numbers=$(echo "$prompt" | "${AI_CMD[@]}" --no-tty 2>/dev/null | grep -E '^[0-9]+$' | head -5)

  rm -f "$temp_issues"

  if [[ -z "$selected_numbers" ]]; then
    return 1
  fi

  # Filter highlighted issues to only include selected ones, in priority order
  local filtered=""
  while IFS= read -r num; do
    local matching_issue=$(echo "$highlighted_issues" | grep -E "^(● )?#${num} \|" | head -1)
    if [[ -n "$matching_issue" ]]; then
      filtered+="${matching_issue}"$'\n'
    fi
  done <<< "$selected_numbers"

  echo "$filtered"
}

# AI-powered Linear issue selection - filters to top 5 issues in priority order
_ai_select_linear_issues() {
  local issues="$1"
  local highlighted_issues="$2"

  # Create a temporary file with the issue list
  local temp_issues=$(mktemp)
  echo "$issues" > "$temp_issues"

  # Prepare the prompt for AI
  local prompt="Analyze the following Linear issues and select the top 5 issues that would be best to work on next. Consider:
- Priority and status
- Issue complexity and impact
- Dependencies between issues
- Team capacity and workflow

Return ONLY the top 5 issue IDs in priority order (one per line), formatted as issue IDs (e.g., 'TEAM-42').

Issues:
$(cat "$temp_issues")

Return only the 5 issue IDs, one per line, nothing else."

  # Use the configured AI tool to select issues
  _resolve_ai_command || {
    rm -f "$temp_issues"
    return 1
  }

  if [[ "${AI_CMD[1]}" == "skip" ]]; then
    rm -f "$temp_issues"
    return 1
  fi

  # Run AI command with the prompt
  local selected_ids
  selected_ids=$(echo "$prompt" | "${AI_CMD[@]}" --no-tty 2>/dev/null | grep -E '^[A-Z][A-Z0-9]+-[0-9]+$' | head -5)

  rm -f "$temp_issues"

  if [[ -z "$selected_ids" ]]; then
    return 1
  fi

  # Filter highlighted issues to only include selected ones, in priority order
  local filtered=""
  while IFS= read -r id; do
    local matching_issue=$(echo "$highlighted_issues" | grep -E "^(● )?${id} \|" | head -1)
    if [[ -n "$matching_issue" ]]; then
      filtered+="${matching_issue}"$'\n'
    fi
  done <<< "$selected_ids"

  echo "$filtered"
}

# AI-powered PR selection - filters to top 5 PRs in priority order
_ai_select_prs() {
  local prs="$1"
  local highlighted_prs="$2"
  local current_user="$3"
  local repo_info="$4"

  # Create a temporary file with the PR list
  local temp_prs=$(mktemp)
  echo "$prs" > "$temp_prs"

  # Prepare the prompt for AI
  local prompt="Analyze the following GitHub Pull Requests and select the top 5 PRs that would be best to review next. Consider the following criteria in priority order:

1. PRs where the current user ($current_user) was requested as a reviewer (highest priority)
2. PRs with no reviews yet (need attention)
3. Smaller PRs with fewer changes (easier to review, faster feedback)
4. PRs with 100% passing checks (✓ status) - prefer these over failing (✗) or pending (○)
5. Author reputation: prefer maintainers/core contributors over occasional contributors

Return ONLY the top 5 PR numbers in priority order (one per line), formatted as just the numbers (e.g., '42').

Repository: $repo_info
Current user: $current_user

Pull Requests:
$(cat "$temp_prs")

Return only the 5 PR numbers, one per line, nothing else."

  # Use the configured AI tool to select PRs
  _resolve_ai_command || {
    rm -f "$temp_prs"
    return 1
  }

  if [[ "${AI_CMD[1]}" == "skip" ]]; then
    rm -f "$temp_prs"
    return 1
  fi

  # Run AI command with the prompt
  local selected_numbers
  selected_numbers=$(echo "$prompt" | "${AI_CMD[@]}" --no-tty 2>/dev/null | grep -E '^[0-9]+$' | head -5)

  rm -f "$temp_prs"

  if [[ -z "$selected_numbers" ]]; then
    return 1
  fi

  # Filter highlighted PRs to only include selected ones, in priority order
  local filtered=""
  while IFS= read -r num; do
    local matching_pr=$(echo "$highlighted_prs" | grep -E "^(● )?#${num} \|" | head -1)
    if [[ -n "$matching_pr" ]]; then
      filtered+="${matching_pr}"$'\n'
    fi
  done <<< "$selected_numbers"

  echo "$filtered"
}

# Install AI tool via interactive menu
_install_ai_tool() {
  echo ""
  gum style --foreground 3 "No AI coding assistant found."
  echo ""

  local choice=$(gum choose \
    "Install Claude Code (Anthropic)" \
    "Install Codex CLI (OpenAI)" \
    "Install Gemini CLI (Google)" \
    "Install Google Jules CLI (Google)" \
    "Skip - don't use an AI tool" \
    "Cancel")

  case "$choice" in
    "Install Claude Code (Anthropic)")
      echo ""
      gum style --foreground 6 "Install Claude Code with one of the following methods:"
      echo "  • macOS:   brew install claude"
      echo "  • npm:     npm install -g @anthropic-ai/claude-code"
      echo ""
      echo "For more information, visit: https://github.com/anthropics/claude-code"
      echo ""
      return 1
      ;;
    "Install Codex CLI (OpenAI)")
      echo ""
      gum style --foreground 6 "Install Codex CLI with:"
      echo "  • npm:     npm install -g @openai/codex-cli"
      echo ""
      echo "For more information, visit: https://github.com/openai/codex"
      echo ""
      return 1
      ;;
    "Install Gemini CLI (Google)")
      echo ""
      gum style --foreground 6 "Install Gemini CLI with:"
      echo "  • npm:     npm install -g @google/gemini-cli"
      echo ""
      echo "For more information, visit: https://github.com/google-gemini/gemini-cli"
      echo ""
      return 1
      ;;
    "Install Google Jules CLI (Google)")
      echo ""
      gum style --foreground 6 "Install Google Jules CLI with:"
      echo "  • npm:     npm install -g @google/jules"
      echo ""
      echo "For more information, visit: https://jules.google/docs"
      echo ""
      return 1
      ;;
    "Skip - don't use an AI tool")
      AI_CMD=(skip)
      AI_CMD_NAME="none"
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

_resolve_ai_command() {
  local claude_available=false
  local codex_available=false
  local gemini_available=false
  local jules_available=false
  local claude_path=""
  local codex_path=""
  local gemini_path=""
  local jules_path=""

  # Check which tools are available and get their full paths
  claude_path=$(command -v claude 2>/dev/null)
  [[ -n "$claude_path" ]] && claude_available=true

  codex_path=$(command -v codex 2>/dev/null)
  [[ -n "$codex_path" ]] && codex_available=true

  gemini_path=$(command -v gemini 2>/dev/null)
  [[ -n "$gemini_path" ]] && gemini_available=true

  jules_path=$(command -v jules 2>/dev/null)
  [[ -n "$jules_path" ]] && jules_available=true

  # Check for saved preference first
  local saved_pref=$(_load_ai_preference)

  if [[ -n "$saved_pref" ]]; then
    case "$saved_pref" in
      claude)
        if [[ "$claude_available" == true ]]; then
          AI_CMD=("$claude_path" --dangerously-skip-permissions)
          AI_CMD_NAME="Claude Code"
          AI_RESUME_CMD=("$claude_path" --dangerously-skip-permissions --continue)
          return 0
        fi
        ;;
      codex)
        if [[ "$codex_available" == true ]]; then
          AI_CMD=("$codex_path" --yolo)
          AI_CMD_NAME="Codex"
          AI_RESUME_CMD=("$codex_path" resume --last)
          return 0
        fi
        ;;
      gemini)
        if [[ "$gemini_available" == true ]]; then
          AI_CMD=("$gemini_path" --yolo)
          AI_CMD_NAME="Gemini CLI"
          AI_RESUME_CMD=("$gemini_path" --resume)
          return 0
        fi
        ;;
      jules)
        if [[ "$jules_available" == true ]]; then
          AI_CMD=("$jules_path")
          AI_CMD_NAME="Google Jules CLI"
          AI_RESUME_CMD=("$jules_path")
          return 0
        fi
        ;;
      skip)
        AI_CMD=(skip)
        AI_CMD_NAME="none"
        return 0
        ;;
    esac
    # If we get here, saved preference is no longer valid (tool uninstalled)
    # Fall through to normal selection
  fi

  # Count available tools
  local available_count=0
  [[ "$claude_available" == true ]] && ((available_count++))
  [[ "$codex_available" == true ]] && ((available_count++))
  [[ "$gemini_available" == true ]] && ((available_count++))
  [[ "$jules_available" == true ]] && ((available_count++))

  # If multiple tools are available, let user choose
  if [[ $available_count -gt 1 ]]; then
    echo ""
    gum style --foreground 6 "Multiple AI coding assistants detected!"
    echo ""

    # Build menu options dynamically
    local options=()
    [[ "$claude_available" == true ]] && options+=("Claude Code (Anthropic)")
    [[ "$codex_available" == true ]] && options+=("Codex CLI (OpenAI)")
    [[ "$gemini_available" == true ]] && options+=("Gemini CLI (Google)")
    [[ "$jules_available" == true ]] && options+=("Google Jules CLI (Google)")
    options+=("Skip - don't use an AI tool")

    local choice=$(gum choose "${options[@]}")

    case "$choice" in
      "Claude Code (Anthropic)")
        AI_CMD=("$claude_path" --dangerously-skip-permissions)
        AI_CMD_NAME="Claude Code"
        AI_RESUME_CMD=("$claude_path" --dangerously-skip-permissions --continue)
        ;;
      "Codex CLI (OpenAI)")
        AI_CMD=("$codex_path" --yolo)
        AI_CMD_NAME="Codex"
        AI_RESUME_CMD=("$codex_path" resume --last)
        ;;
      "Gemini CLI (Google)")
        AI_CMD=("$gemini_path" --yolo)
        AI_CMD_NAME="Gemini CLI"
        AI_RESUME_CMD=("$gemini_path" --resume)
        ;;
      "Google Jules CLI (Google)")
        AI_CMD=("$jules_path")
        AI_CMD_NAME="Google Jules CLI"
        AI_RESUME_CMD=("$jules_path")
        ;;
      "Skip - don't use an AI tool")
        AI_CMD=(skip)
        AI_CMD_NAME="none"
        return 0
        ;;
      *)
        return 1
        ;;
    esac

    # Ask if this choice should be saved
    echo ""
    if gum confirm "Save this as your default choice?"; then
      case "$choice" in
        "Claude Code (Anthropic)")
          _save_ai_preference "claude"
          gum style --foreground 2 "Saved Claude Code as default"
          ;;
        "Codex CLI (OpenAI)")
          _save_ai_preference "codex"
          gum style --foreground 2 "Saved Codex as default"
          ;;
        "Gemini CLI (Google)")
          _save_ai_preference "gemini"
          gum style --foreground 2 "Saved Gemini CLI as default"
          ;;
        "Google Jules CLI (Google)")
          _save_ai_preference "jules"
          gum style --foreground 2 "Saved Google Jules CLI as default"
          ;;
        "Skip - don't use an AI tool")
          _save_ai_preference "skip"
          gum style --foreground 2 "Saved preference to skip AI tool"
          ;;
      esac
      echo ""
    fi

    return 0
  fi

  # Only one tool available - use it
  if [[ "$claude_available" == true ]]; then
    AI_CMD=("$claude_path" --dangerously-skip-permissions)
    AI_CMD_NAME="Claude Code"
    AI_RESUME_CMD=("$claude_path" --dangerously-skip-permissions --continue)
    return 0
  fi

  if [[ "$codex_available" == true ]]; then
    AI_CMD=("$codex_path" --yolo)
    AI_CMD_NAME="Codex"
    AI_RESUME_CMD=("$codex_path" resume --last)
    return 0
  fi

  if [[ "$gemini_available" == true ]]; then
    AI_CMD=("$gemini_path" --yolo)
    AI_CMD_NAME="Gemini CLI"
    AI_RESUME_CMD=("$gemini_path" --resume)
    return 0
  fi

  if [[ "$jules_available" == true ]]; then
    AI_CMD=("$jules_path")
    AI_CMD_NAME="Google Jules CLI"
    AI_RESUME_CMD=("$jules_path")
    return 0
  fi

  # No tools available - show installation menu
  _install_ai_tool
  return $?
}
