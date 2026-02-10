#!/bin/bash

# ============================================================================
# Main interactive menu
# ============================================================================
_aw_menu() {
  _aw_ensure_git_repo || return 1
  _aw_get_repo_info

  # Show existing worktrees
  _aw_list

  echo ""

  local choice=$(gum choose \
    "New worktree" \
    "Resume worktree" \
    "Work on issue" \
    "Work on Milestone/Epic" \
    "Create issue" \
    "Review PR" \
    "Cleanup worktrees" \
    "Settings" \
    "Cancel")

  case "$choice" in
    "New worktree")              _aw_new true ;;
    "Resume worktree")           _aw_resume ;;
    "Work on issue")             _aw_issue ;;
    "Work on Milestone/Epic")    _aw_milestone ;;
    "Create issue")              _aw_create_issue ;;
    "Review PR")                 _aw_pr ;;
    "Cleanup worktrees")         _aw_cleanup_interactive ;;
    "Settings")                  _aw_settings_menu ;;
    *)                           return 0 ;;
  esac
}
