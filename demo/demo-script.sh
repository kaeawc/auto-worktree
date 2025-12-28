#!/bin/bash
# Simulated demo script for claude-worktree
# This script types commands and shows simulated output

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Simulate typing
type_cmd() {
    echo -ne "${GREEN}❯${NC} "
    for ((i=0; i<${#1}; i++)); do
        echo -n "${1:$i:1}"
        sleep 0.04
    done
    echo ""
    sleep 0.3
}

# Simulate gum box
gum_box() {
    local title="$1"
    shift
    local width=50
    echo "╭$(printf '─%.0s' $(seq 1 $((width-2))))╮"
    printf "│ ${CYAN}%-$((width-4))s${NC} │\n" "$title"
    for line in "$@"; do
        printf "│ %-$((width-4))s │\n" "$line"
    done
    echo "╰$(printf '─%.0s' $(seq 1 $((width-2))))╯"
}

clear
sleep 0.5

echo -e "${BOLD}claude-worktree${NC} - Isolated workspaces for Claude Code"
echo ""
sleep 1

# Show help
type_cmd "claude-worktree help"
echo "Usage: claude-worktree [command] [args]"
echo ""
echo "Commands:"
echo "  new           Create a new worktree"
echo "  issue [num]   Work on a GitHub issue"
echo "  pr [num]      Review a GitHub pull request"
echo "  list          List existing worktrees"
echo ""
echo "Run without arguments for interactive menu."
sleep 2

echo ""

# Show list
type_cmd "claude-worktree list"
sleep 0.3
gum_box "Worktrees for my-project"
echo -e "  ${CYAN}work-42-add-dark-mode${NC} (work/42-add-dark-mode) ${GREEN}[2h ago]${NC}"
echo -e "  ${CYAN}work-57-fix-auth${NC} (work/57-fix-auth) ${YELLOW}[3d ago]${NC}"
echo -e "  ${CYAN}pr-89${NC} (review/pr-89) ${MAGENTA}[PR merged]${NC}"
echo ""
sleep 2

# Merged cleanup prompt
echo -e "${MAGENTA}Linked PR was merged! Worktree can be cleaned up: pr-89${NC}"
echo ""
echo -e "${BOLD}? Clean up this worktree?${NC}"
echo -e "  ${GREEN}▸ Yes${NC}"
echo "    No"
sleep 1.5
echo ""
echo -e "${GREEN}✓ Worktree removed.${NC}"
sleep 1.5

echo ""

# Create new worktree
type_cmd "claude-worktree new"
sleep 0.3
echo ""
echo -e "${BOLD}? Branch name (leave blank for random):${NC}"
sleep 0.8
echo ""
echo -e "${CYAN}Generated: work/coral-apex-beam${NC}"
sleep 0.5
echo ""
gum_box "Creating worktree" \
    "  Path:   ~/worktrees/my-project/coral-apex-beam" \
    "  Branch: work/coral-apex-beam" \
    "  Base:   main"
echo ""
sleep 0.5
echo -e "${CYAN}⠋${NC} Creating worktree..."
sleep 0.3
echo -e "\r${CYAN}⠙${NC} Creating worktree..."
sleep 0.3
echo -e "\r${CYAN}⠹${NC} Creating worktree..."
sleep 0.3
echo -e "\r${GREEN}✓${NC} Created worktree"
echo ""
sleep 0.5
echo -e "${GREEN}Starting Claude Code...${NC}"
sleep 1.5

echo ""
echo -e "${BOLD}Ready to code!${NC} 🚀"
sleep 2
