#!/bin/bash

# ============================================================================
# Helper functions
# ============================================================================

# Global variables for AI tool selection
# Note: AI_CMD and AI_RESUME_CMD are arrays to properly handle arguments in zsh
AI_CMD=()
AI_CMD_NAME=""
AI_RESUME_CMD=()

_aw_ensure_git_repo() {
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    gum style --foreground 1 "Error: Not in a git repository"
    return 1
  fi
  return 0
}

_aw_get_repo_info() {
  _AW_GIT_ROOT=$(git rev-parse --show-toplevel)
  _AW_SOURCE_FOLDER=$(basename "$_AW_GIT_ROOT")
  _AW_WORKTREE_BASE="$HOME/worktrees/$_AW_SOURCE_FOLDER"
}

_aw_prune_worktrees() {
  local count_before=$(git worktree list --porcelain 2>/dev/null | grep -c "^worktree " || echo 0)
  git worktree prune 2>/dev/null
  local count_after=$(git worktree list --porcelain 2>/dev/null | grep -c "^worktree " || echo 0)
  local pruned=$((count_before - count_after))
  if [[ $pruned -gt 0 ]]; then
    gum style --foreground 3 "Pruned $pruned orphaned worktree(s)"
    echo ""
  fi
}

_aw_generate_random_name() {
  # In zsh, arrays are 1-indexed, so we need to add 1 to the result of modulo
  local color_idx=$(( ($RANDOM % ${#_WORKTREE_COLORS[@]}) + 1 ))
  local word1_idx=$(( ($RANDOM % ${#_WORKTREE_WORDS[@]}) + 1 ))
  local word2_idx=$(( ($RANDOM % ${#_WORKTREE_WORDS[@]}) + 1 ))

  local color=${_WORKTREE_COLORS[$color_idx]}
  local word1=${_WORKTREE_WORDS[$word1_idx]}
  local word2=${_WORKTREE_WORDS[$word2_idx]}
  echo "${color}-${word1}-${word2}"
}

_aw_sanitize_branch_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\+/-/g' | sed 's/^-//;s/-$//'
}

_aw_get_file_mtime() {
  # Get file modification time in Unix timestamp format
  # Works on both macOS/BSD and Linux
  # Returns: Unix timestamp (seconds since epoch)
  local file_path="$1"

  if [[ "$(uname)" == "Darwin" ]] || [[ "$(uname)" == *"BSD"* ]]; then
    # macOS/BSD syntax
    stat -f %m "$file_path" 2>/dev/null
  else
    # Linux syntax
    stat -c %Y "$file_path" 2>/dev/null
  fi
}
