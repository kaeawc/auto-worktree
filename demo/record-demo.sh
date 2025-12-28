#!/bin/bash
# Demo recording script for claude-worktree
# Uses asciinema to record a simulated demo

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

# Record the demo
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

echo "Done! GIF saved to $PROJECT_DIR/demo.gif"
