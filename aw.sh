#!/bin/bash

# Source this file from ~/.zshrc to load the shell function `auto-worktree`
#
# This is a thin wrapper that loads the modular source from src/main.sh.
# For a standalone single-file distribution, use dist/aw.sh (built via ci/build.sh).
#
# Usage:
#   auto-worktree                    # Interactive menu
#   auto-worktree new                # Create new worktree
#   auto-worktree resume             # Resume existing worktree
#   auto-worktree issue [id]         # Work on an issue (GitHub #123, GitLab #456, or JIRA PROJ-123)
#   auto-worktree pr [num]           # Review a GitHub PR or GitLab MR
#   auto-worktree list               # List existing worktrees
#   auto-worktree settings           # Configure per-repository settings

# Determine the directory where this script is located
_AW_ROOT_DIR="${BASH_SOURCE[0]:-${(%):-%x}}"
_AW_ROOT_DIR="$(cd "$(dirname "$_AW_ROOT_DIR")" && pwd)"

# Source the modular main entry point
# shellcheck disable=SC1091
source "$_AW_ROOT_DIR/src/main.sh"

# Clean up
unset _AW_ROOT_DIR
