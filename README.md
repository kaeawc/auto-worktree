# auto-worktree

A bash tool for safely running AI agents in isolated git worktrees. Create separate workspaces for each task, issue, or PR review - keeping your main branch pristine.

![Demo](demo.gif)

## Features

- **Isolated Workspaces**: Each task gets its own worktree - no branch conflicts or stashed changes
- **GitHub Integration**: Work on issues or review PRs with automatic branch naming
- **Interactive TUI**: Beautiful menus powered by [gum](https://github.com/charmbracelet/gum)
- **Auto-cleanup**: Detects merged PRs and stale worktrees, prompts for cleanup
- **Random Names**: Generates memorable branch names like `work/coral-apex-beam`
- **Tab Completion**: Full zsh completion for commands, issues, and PRs

## Installation

### Prerequisites

```bash
brew install gum gh jq
```

- **gum** - Terminal UI components
- **gh** - GitHub CLI (authenticate with `gh auth login`)
- **jq** - JSON processor

### Setup

Add to your `~/.zshrc`:

```bash
source /path/to/auto-worktree/aw.sh
```

## Usage

```bash
auto-worktree              # Interactive menu
auto-worktree new          # Create new worktree
auto-worktree issue [num]  # Work on a GitHub issue
auto-worktree pr [num]     # Review a GitHub PR
auto-worktree list         # List existing worktrees
auto-worktree help         # Show help
```

### Create a New Worktree

```bash
auto-worktree new
```

Enter a branch name or leave blank for a random name like `work/mint-code-flux`.

### Work on a GitHub Issue

```bash
auto-worktree issue        # Select from open issues
auto-worktree issue 42     # Work on issue #42 directly
```

Creates a branch like `work/42-fix-login-bug` and opens Claude Code.

### Review a Pull Request

```bash
auto-worktree pr           # Select from open PRs
auto-worktree pr 123       # Review PR #123 directly
```

Checks out the PR in a new worktree and shows the diff stats.

### List Worktrees

```bash
auto-worktree list
```

Shows all worktrees with:
- Age indicators (green: recent, yellow: few days, red: stale)
- Merged PR/issue detection
- Cleanup prompts for merged or stale worktrees

## How It Works

1. **Worktrees** are stored in `~/worktrees/<repo-name>/`
2. Each worktree is a full copy of your repo on its own branch
3. Claude Code launches with `--dangerously-skip-permissions` for uninterrupted work
4. When done, use `list` to clean up merged worktrees and branches

## Example Workflow

```bash
# Start work on an issue
cd my-project
auto-worktree issue 42

# Claude Code opens in ~/worktrees/my-project/work-42-add-feature/
# Make changes, commit, push, create PR

# Later, check for cleanup
auto-worktree list
# Shows "[merged #42]" indicator, prompts to clean up
```

## Tab Completion

The tool includes full zsh completion:

```bash
auto-worktree <TAB>        # Shows: new, issue, pr, list, help
auto-worktree issue <TAB>  # Shows open issues from GitHub
auto-worktree pr <TAB>     # Shows open PRs from GitHub
```

## Why Worktrees?

- **No context switching**: Keep multiple tasks in progress without stashing
- **Clean isolation**: Claude Code changes won't affect other branches
- **Easy cleanup**: Delete the folder and branch when done
- **Parallel work**: Run multiple Claude Code sessions on different tasks

## License

MIT
