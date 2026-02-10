#!/usr/bin/env bash
# Builds dist/aw.sh by concatenating all source modules
# Produces a single distributable file equivalent to the monolithic aw.sh
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$REPO_ROOT/dist"
SRC_DIR="$REPO_ROOT/src"
OUTPUT="$DIST_DIR/aw.sh"

mkdir -p "$DIST_DIR"

# Define source files in dependency order (matches src/main.sh sourcing order)
SOURCE_FILES=(
  "$SRC_DIR/lib/words.sh"
  "$SRC_DIR/lib/deps.sh"
  "$SRC_DIR/lib/utils.sh"
  "$SRC_DIR/lib/config.sh"
  "$SRC_DIR/lib/hooks.sh"
  "$SRC_DIR/lib/environment.sh"
  "$SRC_DIR/lib/ai.sh"
  "$SRC_DIR/lib/settings.sh"
  "$SRC_DIR/providers/common.sh"
  "$SRC_DIR/providers/github.sh"
  "$SRC_DIR/providers/gitlab.sh"
  "$SRC_DIR/providers/jira.sh"
  "$SRC_DIR/providers/linear.sh"
  "$SRC_DIR/lib/worktree.sh"
  "$SRC_DIR/commands/list.sh"
  "$SRC_DIR/commands/new.sh"
  "$SRC_DIR/commands/issue.sh"
  "$SRC_DIR/commands/create_issue.sh"
  "$SRC_DIR/commands/pr.sh"
  "$SRC_DIR/commands/resume.sh"
  "$SRC_DIR/commands/cleanup.sh"
  "$SRC_DIR/commands/menu.sh"
)

# Start with the shebang and header comment
cat > "$OUTPUT" << 'HEADER'
#!/bin/bash

# Source this file from ~/.zshrc to load the shell function `auto-worktree`
#
# Usage:
#   auto-worktree                    # Interactive menu
#   auto-worktree new                # Create new worktree
#   auto-worktree resume             # Resume existing worktree
#   auto-worktree issue [id]         # Work on an issue (GitHub #123, GitLab #456, or JIRA PROJ-123)
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
HEADER

# Concatenate each source module (stripping individual shebangs)
for src_file in "${SOURCE_FILES[@]}"; do
  if [[ ! -f "$src_file" ]]; then
    echo "Error: Source file not found: $src_file" >&2
    exit 1
  fi

  echo "" >> "$OUTPUT"
  # Strip the shebang line (#!/bin/bash) from each module
  sed '1{/^#!\/bin\/bash$/d;}' "$src_file" >> "$OUTPUT"
done

# Append the main entry point, shell completion, and aw() wrapper from main.sh
# Extract everything from the auto-worktree() function definition to the end,
# but skip the source directives and _AW_SRC_DIR setup, and adapt completion
# to use _AW_SCRIPT_DIR based on BASH_SOURCE (standalone single-file mode).
echo "" >> "$OUTPUT"

# Use awk: print from "# Main entry point" section to end of file,
# but replace the _AW_SRC_DIR-based completion path with standalone version
awk '
  /^# Main entry point$/ { found=1 }
  found && /^_AW_SCRIPT_DIR=.*_AW_SRC_DIR/ {
    # Replace the src-relative path with standalone path
    print "_AW_SCRIPT_DIR=\"${BASH_SOURCE[0]:-${(%):-%x}}\""
    print "_AW_SCRIPT_DIR=\"$(cd \"$(dirname \"$_AW_SCRIPT_DIR\")\" && pwd)\""
    next
  }
  found && /^unset _AW_SRC_DIR$/ { next }
  found { print }
' "$SRC_DIR/main.sh" >> "$OUTPUT"

chmod +x "$OUTPUT"

# Show result
line_count=$(wc -l < "$OUTPUT")
echo "Built $OUTPUT ($line_count lines)"
