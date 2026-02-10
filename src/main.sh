#!/bin/bash

# Source this file from ~/.zshrc to load the shell function `auto-worktree`
#
# Usage:
#   auto-worktree                    # Interactive menu
#   auto-worktree new                # Create new worktree
#   auto-worktree resume             # Resume existing worktree
#   auto-worktree issue [id]         # Work on an issue (GitHub #123, GitLab #456, or JIRA PROJ-123)
#   auto-worktree milestone          # Work on a Milestone/Epic
#   auto-worktree pr [num]           # Review a GitHub PR or GitLab MR
#   auto-worktree list               # List existing worktrees
#   auto-worktree settings           # Configure per-repository settings
#
# Configuration (per-repository via git config):
#   git config auto-worktree.issue-provider github|gitlab|jira  # Set issue provider
#   git config auto-worktree.jira-server <URL>                  # Set JIRA server URL
#   git config auto-worktree.jira-project <KEY>                 # Set default JIRA project
#   git config auto-worktree.gitlab-server <URL>                # Set GitLab server URL (for self-hosted)
#   git config auto-worktree.gitlab-project <GROUP/PROJECT>     # Set default GitLab project path
#   git config auto-worktree.linear-team <TEAM>                 # Set default Linear team
#   git config auto-worktree.ai-tool <name>                     # claude|codex|gemini|jules|skip
#   git config auto-worktree.issue-autoselect <bool>            # true/false for AI auto-select
#   git config auto-worktree.pr-autoselect <bool>               # true/false for AI auto-select
#   git config auto-worktree.run-hooks <bool>                   # true/false to enable/disable git hooks (default: true)
#   git config auto-worktree.fail-on-hook-error <bool>          # true/false to fail on hook errors (default: false)
#   git config auto-worktree.custom-hooks "<hook1> <hook2>"     # Space or comma-separated list of custom hooks to run

# Determine the directory where this script is located
_AW_SRC_DIR="${BASH_SOURCE[0]:-${(%):-%x}}"
_AW_SRC_DIR="$(cd "$(dirname "$_AW_SRC_DIR")" && pwd)"

# Source all modules in dependency order
# shellcheck source=lib/words.sh
source "$_AW_SRC_DIR/lib/words.sh"
# shellcheck source=lib/deps.sh
source "$_AW_SRC_DIR/lib/deps.sh"
# shellcheck source=lib/utils.sh
source "$_AW_SRC_DIR/lib/utils.sh"
# shellcheck source=lib/config.sh
source "$_AW_SRC_DIR/lib/config.sh"
# shellcheck source=lib/hooks.sh
source "$_AW_SRC_DIR/lib/hooks.sh"
# shellcheck source=lib/environment.sh
source "$_AW_SRC_DIR/lib/environment.sh"
# shellcheck source=lib/ai.sh
source "$_AW_SRC_DIR/lib/ai.sh"
# shellcheck source=lib/settings.sh
source "$_AW_SRC_DIR/lib/settings.sh"
# shellcheck source=providers/common.sh
source "$_AW_SRC_DIR/providers/common.sh"
# shellcheck source=providers/gitlab.sh
source "$_AW_SRC_DIR/providers/gitlab.sh"
# shellcheck source=providers/jira.sh
source "$_AW_SRC_DIR/providers/jira.sh"
# shellcheck source=providers/linear.sh
source "$_AW_SRC_DIR/providers/linear.sh"
# shellcheck source=lib/worktree.sh
source "$_AW_SRC_DIR/lib/worktree.sh"
# shellcheck source=commands/list.sh
source "$_AW_SRC_DIR/commands/list.sh"
# shellcheck source=commands/new.sh
source "$_AW_SRC_DIR/commands/new.sh"
# shellcheck source=commands/issue.sh
source "$_AW_SRC_DIR/commands/issue.sh"
# shellcheck source=commands/create_issue.sh
source "$_AW_SRC_DIR/commands/create_issue.sh"
# shellcheck source=commands/pr.sh
source "$_AW_SRC_DIR/commands/pr.sh"
# shellcheck source=commands/resume.sh
source "$_AW_SRC_DIR/commands/resume.sh"
# shellcheck source=commands/cleanup.sh
source "$_AW_SRC_DIR/commands/cleanup.sh"
# shellcheck source=commands/milestone.sh
source "$_AW_SRC_DIR/commands/milestone.sh"
# shellcheck source=commands/menu.sh
source "$_AW_SRC_DIR/commands/menu.sh"

# ============================================================================
# Main entry point
# ============================================================================

auto-worktree() {
  _aw_check_deps || return 1

  case "${1:-}" in
    new)     shift; _aw_new "$@" ;;
    issue)      shift; _aw_issue "$@" ;;
    milestone)  shift; _aw_milestone "$@" ;;
    create)     shift; _aw_create_issue "$@" ;;
    pr)      shift; _aw_pr "$@" ;;
    resume)  shift; _aw_resume ;;
    list)    shift; _aw_list ;;
    cleanup) shift; _aw_cleanup_interactive ;;
    settings) shift; _aw_settings_menu ;;
    help|--help|-h)
      echo "Usage: auto-worktree [command] [args]"
      echo ""
      echo "Commands:"
      echo "  new             Create a new worktree"
      echo "  resume          Resume an existing worktree"
      echo "  issue [id]      Work on an issue (GitHub #123, GitLab #456, JIRA PROJ-123, or Linear TEAM-123)"
      echo "  milestone       Work on a Milestone/Epic (filter issues by milestone)"
      echo "  create          Create a new issue with optional template"
      echo "  pr [num]        Review a GitHub PR or GitLab MR"
      echo "  list            List existing worktrees"
      echo "  cleanup         Interactively clean up worktrees"
      echo "  settings        Configure per-repository settings"
      echo ""
      echo "Run without arguments for interactive menu."
      echo ""
      echo "Create Issue Flags:"
      echo "  --title TEXT       Issue title (required for non-interactive mode)"
      echo "  --body TEXT        Issue description/body"
      echo "  --template PATH    Path to template file to use"
      echo "  --no-template      Skip template selection"
      echo "  --no-worktree      Don't offer to create worktree after issue creation"
      echo ""
      echo "Configuration:"
      echo "  First time using issues? Run 'auto-worktree issue' to configure"
      echo "  your issue provider (GitHub, GitLab, JIRA, or Linear) for this repository."
      echo ""
      gum style --foreground 3 --bold "⚠️  SAFETY WARNING"
      echo ""
      echo "Worktrees are safe, but git is NOT designed for concurrent operations."
      echo "Running multiple git commands simultaneously (across different worktrees)"
      echo "can corrupt your repository."
      echo ""
      echo "Safe practices:"
      echo "  • Run only ONE AI agent per repository at a time"
      echo "  • Complete git operations (commit, rebase, push) sequentially"
      echo "  • Pause other agents before starting git operations"
      echo "  • Disable background git status in IDEs"
      echo ""
      echo "See docs/BEST_PRACTICES.md for detailed safety guidance."
      ;;
    "")    _aw_menu ;;
    *)
      gum style --foreground 1 "Unknown command: $1"
      echo "Run 'auto-worktree help' for usage"
      return 1
      ;;
  esac
}

# ============================================================================
# Shell Completion
# ============================================================================
#
# Load shell completion for auto-worktree and aw commands.
# Completion files are located in the completions/ directory relative to the
# project root (one level up from src/).

_AW_SCRIPT_DIR="$(cd "$_AW_SRC_DIR/.." && pwd)"

# Load the appropriate completion file based on the current shell
if [[ -n "$ZSH_VERSION" ]]; then
  # Zsh completion
  if [[ -f "$_AW_SCRIPT_DIR/completions/aw.zsh" ]]; then
    # shellcheck disable=SC1091
    source "$_AW_SCRIPT_DIR/completions/aw.zsh"
  fi
elif [[ -n "$BASH_VERSION" ]]; then
  # Bash completion
  if [[ -f "$_AW_SCRIPT_DIR/completions/aw.bash" ]]; then
    # shellcheck disable=SC1091
    source "$_AW_SCRIPT_DIR/completions/aw.bash"
  fi
fi

# Clean up temporary variables
unset _AW_SCRIPT_DIR
unset _AW_SRC_DIR

# ============================================================================
# Worktree-aware 'aw' wrapper
# ============================================================================
#
# This function provides a convenient 'aw' alias that is worktree-aware:
# - When in a git repository with a local aw.sh file, it sources that version
#   (useful when developing auto-worktree itself - your changes take effect immediately)
# - Otherwise, it uses the globally-sourced auto-worktree function
# - Provides a shorter command: 'aw' instead of 'auto-worktree'
#
aw() {
  # Check if we're in a git repository
  local git_root
  git_root=$(git rev-parse --show-toplevel 2>/dev/null)

  # If we're in a git repo and there's a local aw.sh, source it
  # This allows developers working on auto-worktree to use their local changes
  if [[ -n "$git_root" && -f "$git_root/aw.sh" ]]; then
    # Only source if it's different from the currently loaded version
    local local_aw_path="$git_root/aw.sh"
    local current_aw_path="${_AW_SOURCE_PATH:-}"

    if [[ "$local_aw_path" != "$current_aw_path" ]]; then
      # shellcheck disable=SC1090
      source "$local_aw_path"
      # Track which version we sourced for future comparisons
      export _AW_SOURCE_PATH="$local_aw_path"
    fi
  fi

  # Call auto-worktree with all provided arguments
  auto-worktree "$@"
}
