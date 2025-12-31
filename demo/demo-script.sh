#!/bin/bash
# Simulated interactive demo for claude-worktree
# Shows the interactive flow without requiring full TTY

set -e

# Get script directory and project directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Add mock claude to PATH
export PATH="$SCRIPT_DIR:$PATH"

# Source for access to word lists and functions
compdef() { :; }
source "$PROJECT_DIR/cw.sh"

# Helper to type command with delay
type_cmd() {
    for ((i=0; i<${#1}; i++)); do
        echo -n "${1:$i:1}"
        sleep 0.04
    done
    echo ""
}

# Helper to show a pause
pause() {
    sleep "${1:-0.8}"
}

# Cleanup function
cleanup_demo_worktrees() {
    local worktree_base="$HOME/worktrees/claude-worktree"
    if [[ -d "$worktree_base" ]]; then
        for wt in "$worktree_base"/*; do
            if [[ -d "$wt" ]]; then
                local branch_name=$(git -C "$wt" branch --show-current 2>/dev/null || echo "")
                git worktree remove --force "$wt" 2>/dev/null || true
                if [[ -n "$branch_name" ]]; then
                    git branch -D "$branch_name" 2>/dev/null || true
                fi
            fi
        done
    fi
}

# Clean up any previous demo worktrees
cleanup_demo_worktrees

clear
pause 0.3

# Show the command being typed
echo -n "❯ "
type_cmd "claude-worktree"
pause 0.5

# Show status message
gum style --foreground 240 "No additional worktrees for claude-worktree"
echo ""
pause 0.3

# Show the interactive menu
gum style --foreground 99 "Choose:"
gum style --foreground 212 "> New worktree"
echo "  Resume worktree"
echo "  Work on issue"
echo "  Review PR"
echo "  Cancel"
echo ""
pause 1.5

# User "selects" New worktree - show the branch input
echo ""
echo -n "Branch name (leave blank for random): "
pause 0.8
echo ""  # User presses enter
pause 0.3

# Generate random branch name
random_color="${_WORKTREE_COLORS[$((RANDOM % ${#_WORKTREE_COLORS[@]} + 1))]}"
random_word1="${_WORKTREE_WORDS[$((RANDOM % ${#_WORKTREE_WORDS[@]} + 1))]}"
random_word2="${_WORKTREE_WORDS[$((RANDOM % ${#_WORKTREE_WORDS[@]} + 1))]}"
branch_name="work/$random_color-$random_word1-$random_word2"
worktree_name=$(echo "$branch_name" | sed 's/\//-/g')
worktree_path="$HOME/worktrees/claude-worktree/$worktree_name"

gum style --foreground 6 "Generated: $branch_name"
echo ""
pause 0.5

# Show worktree creation box
gum style --border rounded --padding "0 1" --border-foreground 4 \
  "Creating worktree" \
  "  Path:   $worktree_path" \
  "  Branch: $branch_name" \
  "Base:" \
  "main"
echo ""
pause 0.3

# Actually create the worktree
cd "$PROJECT_DIR"
git worktree add -b "$branch_name" "$worktree_path" main >/dev/null 2>&1

# Show spinner effect
echo -ne "\033[38;5;212m⠋\033[0m Creating worktree..."
sleep 0.2
echo -ne "\r\033[38;5;212m⠙\033[0m Creating worktree..."
sleep 0.2
echo -ne "\r\033[38;5;212m⠹\033[0m Creating worktree..."
sleep 0.2
echo -ne "\r\033[32m✓\033[0m Created worktree   "
echo ""
pause 0.5

# Show mock Claude launch
gum style --foreground 2 "Starting Claude Code..."
pause 0.5
claude
pause 0.5

# Clean up
cleanup_demo_worktrees 2>/dev/null || true

echo ""
