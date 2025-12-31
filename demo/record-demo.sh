#!/bin/bash
# Demo recording script for claude-worktree
# Records with asciinema and converts to GIF with agg

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Check dependencies
if ! command -v asciinema &> /dev/null; then
    echo "asciinema not found. Install with: brew install asciinema"
    exit 1
fi

if ! command -v agg &> /dev/null; then
    echo "agg not found. Install with: brew install agg"
    exit 1
fi

echo "Recording demo..."

# Record the demo using bash script
asciinema rec "$SCRIPT_DIR/demo.cast" \
    --overwrite \
    --cols 80 \
    --rows 24 \
    --command "bash $SCRIPT_DIR/demo-script.sh"

echo "Converting to GIF..."

# Convert to high-quality GIF
agg "$SCRIPT_DIR/demo.cast" "$PROJECT_DIR/demo.gif" \
    --font-size 16 \
    --speed 1.2 \
    --theme monokai

echo "Cleaning up demo worktrees..."

# Clean up any worktrees created during demo
cd "$PROJECT_DIR"
worktree_base="$HOME/worktrees/claude-worktree"
if [[ -d "$worktree_base" ]]; then
    for wt in "$worktree_base"/*; do
        if [[ -d "$wt" ]]; then
            # Get the branch name before removing worktree
            branch_name=$(git -C "$wt" branch --show-current 2>/dev/null || echo "")
            git worktree remove --force "$wt" 2>/dev/null || true
            # Clean up the branch if we got one
            if [[ -n "$branch_name" ]]; then
                git branch -D "$branch_name" 2>/dev/null || true
            fi
        fi
    done
fi

echo "Done! GIF saved to $PROJECT_DIR/demo.gif"
