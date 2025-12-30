# Agent Guide for claude-worktree

This document provides essential context for AI agents working on the claude-worktree project.

## Project Overview

**claude-worktree** is a bash/zsh tool that enables safe, isolated workspaces for Claude Code sessions using git worktrees. It provides an interactive TUI for creating worktrees, working on GitHub issues, reviewing PRs, and managing cleanup of merged/stale worktrees.

- **Type**: Bash/Zsh shell utility
- **Primary File**: `cw.sh` (single-file implementation)
- **Dependencies**: `gum`, `gh`, `jq` (all installable via Homebrew)
- **Target Shell**: zsh (with zsh completion support)
- **License**: MIT

## Repository Structure

```
.
├── LICENSE              # MIT license
├── README.md            # User documentation
├── cw.sh                # Main shell script (source from ~/.zshrc)
├── demo.gif             # Animated demo for README
└── demo/
    ├── demo-script.sh   # Simulated demo script
    ├── demo.cast        # asciinema recording
    └── record-demo.sh   # Records and converts demo to GIF
```

## Core Architecture

### Main Script: `cw.sh`

The entire tool is implemented as a **single bash script** with these components:

1. **Dependency Management** (`_cw_check_deps`)
   - Validates `gum`, `gh`, `jq` availability
   - Shows installation commands if missing

2. **Word Lists** (`_WORKTREE_WORDS`, `_WORKTREE_COLORS`)
   - Arrays used for generating random branch names
   - Pattern: `{color}-{word1}-{word2}` (e.g., `coral-apex-beam`)

3. **Helper Functions** (prefixed with `_cw_`)
   - Repository info gathering
   - Branch name sanitization
   - Issue/PR merge detection
   - Worktree creation and cleanup

4. **Core Commands**
   - `claude-worktree new` - Create new worktree with random or custom branch
   - `claude-worktree issue [num]` - Work on GitHub issue
   - `claude-worktree pr [num]` - Review GitHub PR
   - `claude-worktree list` - List/manage existing worktrees
   - `claude-worktree help` - Show help

5. **Zsh Completion** (`_claude_worktree`)
   - Auto-completes commands, issue numbers, PR numbers
   - Fetches live data from GitHub via `gh` CLI

### Key Design Patterns

#### Function Naming Convention
- **Public function**: `claude-worktree` (main entry point)
- **Private helpers**: `_cw_*` prefix (not meant for direct invocation)
- **Pattern**: All internal functions use `_cw_` namespace to avoid conflicts

#### Error Handling
- Functions return `1` on error, `0` on success
- Use `gum style --foreground 1` for error messages
- Early returns with `|| return 1` pattern

#### User Experience
- Interactive prompts powered by `gum` (choose, confirm, input, spin, style)
- Color-coded output:
  - Red (1): Errors, stale worktrees (>4 days)
  - Green (2): Success, recent worktrees (<1 day)
  - Yellow (3): Warnings, worktrees 1-4 days old
  - Blue (4): Info boxes
  - Magenta (5): Merged indicators
  - Cyan (6): Highlights

#### Worktree Lifecycle
1. **Creation**: `git worktree add -b <branch> <path> <base>`
2. **Storage**: `~/worktrees/<repo-name>/<worktree-name>/`
3. **Launch**: `claude --dangerously-skip-permissions` in worktree directory
4. **Cleanup**: `git worktree remove --force <path>` + optional branch deletion

## Important Implementation Details

### Branch Name Sanitization
```bash
_cw_sanitize_branch_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\+/-/g' | sed 's/^-//;s/-$//'
}
```
- Converts to lowercase
- Replaces non-alphanumeric with dashes
- Collapses multiple dashes
- Strips leading/trailing dashes

### Issue/PR Merge Detection

**Issue merge detection** (`_cw_check_issue_merged`):
- Checks if issue state is `CLOSED`
- Checks if `stateReason` is `COMPLETED` (indicates PR was merged)
- Searches for merged PRs with "closes #N" / "fixes #N" / "resolves #N"

**PR merge detection** (`_cw_check_branch_pr_merged`):
- Uses `gh pr view <branch>` to check if PR exists and is merged
- Returns 0 if `state` is `MERGED`

### Worktree Age Calculation
- Uses commit timestamp from `git log -1 --format=%ct`
- Falls back to file modification time if no commits
- Age thresholds:
  - `<1 day`: Green, shows hours (e.g., `[2h ago]`)
  - `1-4 days`: Yellow, shows days (e.g., `[3d ago]`)
  - `>4 days`: Red (stale), shows days (e.g., `[7d ago]`)

### Cleanup Priority
1. **Merged worktrees** are prompted for cleanup first (higher priority)
2. **Stale worktrees** (>4 days) are prompted only if no merged ones exist
3. Only prompts for **one worktree at a time** for user control

## Common Development Tasks

### Testing Changes to `cw.sh`

Since this is a shell utility loaded in the user's shell:

```bash
# Reload after changes
source cw.sh

# Test in a git repository
cd /path/to/any/git/repo
claude-worktree list
claude-worktree new
```

**Important**: Always test in an actual git repository, not in the claude-worktree directory itself.

### Testing GitHub Integration

Requires:
- GitHub repository context
- `gh` CLI authenticated (`gh auth login`)
- Open issues/PRs to test with

```bash
# Test issue workflow
claude-worktree issue

# Test PR workflow  
claude-worktree pr

# Test with specific number
claude-worktree issue 42
claude-worktree pr 123
```

### Recording Demo

```bash
cd demo/
./record-demo.sh
```

Requirements:
- `asciinema` (install: `brew install asciinema`)
- `agg` (install: `brew install agg`)

Creates `demo.gif` in project root using `demo-script.sh` simulation.

## Code Style and Conventions

### Shell Style
- **Indentation**: 2 spaces (not tabs)
- **Line length**: Generally <100 chars, but not strict
- **Quoting**: Always quote variables: `"$variable"` not `$variable`
- **Arrays**: Use zsh array syntax `${#array[@]}`, `${array[$i]}`

### Variable Naming
- **Global state**: `_CW_UPPERCASE` (e.g., `_CW_GIT_ROOT`, `_CW_WORKTREE_BASE`)
- **Local vars**: `snake_case` (e.g., `branch_name`, `worktree_path`)
- **Function params**: Positional `$1`, `$2` or named locals

### Error Messages
```bash
# Error pattern
gum style --foreground 1 "Error: <message>"
return 1

# Warning pattern
gum style --foreground 3 "<message>"

# Success pattern
gum style --foreground 2 "<message>"
```

### gum UI Patterns

**Spinner for async operations**:
```bash
gum spin --spinner dot --title "Loading..." -- command args
```

**Bordered info box**:
```bash
gum style --border rounded --padding "0 1" --border-foreground 4 \
  "Title" \
  "Line 1" \
  "Line 2"
```

**User confirmation**:
```bash
if gum confirm "Proceed?"; then
  # user said yes
fi
```

**Interactive selection**:
```bash
choice=$(echo "$options" | gum filter --placeholder "Select...")
```

**User input**:
```bash
value=$(gum input --placeholder "Enter value")
value=$(gum input --value "default" --header "Confirm:")
```

## Known Quirks and Gotchas

### 1. Zsh Array Iteration Bug (Fixed)
**Historical issue** (fixed in commit `034fadc`):
- Arrays in zsh are 1-indexed, not 0-indexed
- Iteration must use `while [[ $i -le ${#array[@]} ]]` pattern
- Access with `${array[$i]}` not `${array[i]}`

### 2. Variable Assignment with Echo (Fixed)
**Historical issue** (fixed in commit `991ad67`):
- Cannot use `echo` for variable assignment in zsh in some contexts
- Use direct assignment or command substitution instead

### 3. `claude` Command Dependency
- Hardcoded call to `claude --dangerously-skip-permissions`
- Assumes Claude Code CLI is installed and in PATH
- No fallback if `claude` is not available

### 4. `gum`, `gh`, `jq` Required
- Tool **will not function** without these dependencies
- Dependency check happens at runtime, not install-time
- User must install via Homebrew on macOS

### 5. Worktree Paths
- Worktrees stored in `~/worktrees/<repo-name>/`
- **Not configurable** (hardcoded in `_cw_get_repo_info`)
- Multiple repos with same basename will share directory (potential conflict)

### 6. Merge Detection Rate Limits
- Calls `gh issue view` and `gh pr view` for each worktree in `list` command
- Can hit GitHub API rate limits with many worktrees
- No caching mechanism

### 7. Detached HEAD for PRs
- PR checkout uses `--detach` flag (commits on FETCH_HEAD)
- Worktree created from FETCH_HEAD, not a named branch
- User must create branch manually if they want to push changes

## GitHub Integration

### Required Setup
```bash
# Install and authenticate
brew install gh
gh auth login
```

### API Usage Patterns

**Fetch issues**:
```bash
gh issue list --limit 20 --state open --json number,title,labels
```

**Fetch PRs**:
```bash
gh pr list --limit 20 --state open --json number,title,author,headRefName,baseRefName
```

**Check issue state**:
```bash
gh issue view $num --json state,stateReason
```

**Check PR state**:
```bash
gh pr view $num --json state,mergedAt
```

**Checkout PR**:
```bash
gh pr checkout $num --detach
```

### JSON Processing with jq
All GitHub CLI output uses `--json` with `--jq` for extraction:
```bash
# Extract single field
title=$(echo "$data" | jq -r '.title')

# Template format for lists
--template '{{range .}}#{{.number}} | {{.title}}{{"\n"}}{{end}}'
```

## Testing Strategy

Since this is a shell utility without automated tests:

### Manual Testing Checklist

**Basic functionality**:
- [ ] `claude-worktree` shows interactive menu
- [ ] `claude-worktree new` creates worktree with random name
- [ ] `claude-worktree new` accepts custom branch name
- [ ] `claude-worktree list` shows existing worktrees
- [ ] `claude-worktree help` shows usage

**GitHub integration** (requires repo with issues/PRs):
- [ ] `claude-worktree issue` lists open issues
- [ ] `claude-worktree issue <num>` creates worktree for issue
- [ ] `claude-worktree pr` lists open PRs
- [ ] `claude-worktree pr <num>` creates worktree for PR review
- [ ] Merged issue/PR shows `[merged #N]` indicator
- [ ] Cleanup prompt appears for merged worktrees

**Edge cases**:
- [ ] Creating worktree for existing branch
- [ ] Branch name with special characters gets sanitized
- [ ] Missing dependencies show helpful error
- [ ] Running outside git repo shows error
- [ ] Repository with no worktrees shows appropriate message

**Zsh completion**:
- [ ] `claude-worktree <TAB>` shows commands
- [ ] `claude-worktree issue <TAB>` shows issue numbers
- [ ] `claude-worktree pr <TAB>` shows PR numbers

## Future Enhancement Ideas

Based on code review, potential improvements:

1. **Configurable worktree base path** - Allow user to set custom directory
2. **Dependency fallbacks** - Graceful degradation without `gh` (no GitHub features)
3. **Merge detection caching** - Cache GitHub API calls to avoid rate limits
4. **Named branches for PRs** - Option to create local branch instead of detached HEAD
5. **Batch cleanup** - Option to clean up multiple merged/stale worktrees at once
6. **Status indicators** - Show git status (dirty/clean) in `list` output
7. **Shell detection** - Support bash in addition to zsh
8. **Configuration file** - `.cwrc` for user preferences

## Commands Reference

### No Commands to Memorize
This project has **no build, test, or lint commands** - it's a pure shell script utility.

### Development Workflow
1. Edit `cw.sh`
2. `source cw.sh` to reload in current shell
3. Test in a git repository: `claude-worktree <command>`
4. Commit changes when satisfied

### Installation
Add to `~/.zshrc`:
```bash
source /path/to/claude-worktree/cw.sh
```

## When Contributing

### Before Making Changes
- Read through `cw.sh` to understand the flow
- Test in a real git repository (not this one)
- Consider impact on existing worktrees
- Preserve backward compatibility with function signatures

### Code Changes
- Maintain `_cw_` prefix for internal functions
- Use `gum` for all UI interactions
- Follow existing color scheme (error=red, success=green, etc.)
- Quote all variable references
- Use `local` for function-scoped variables

### Documentation
- Update README.md for user-facing changes
- Update this AGENTS.md for implementation details
- Update function header comments in `cw.sh` if behavior changes

### Testing
- Test with and without GitHub integration
- Test dependency checking (temporarily rename a dependency)
- Test edge cases (special chars, long names, existing branches)
- Verify zsh completion still works

## Summary for Quick Start

**What this tool does**: Creates isolated git worktrees for Claude Code sessions, with GitHub issue/PR integration.

**Key file**: `cw.sh` (single-file implementation)

**Dependencies**: `gum`, `gh`, `jq` (install via Homebrew)

**Testing**: Source the file, run `claude-worktree` commands in a git repo

**Common pitfall**: Must be in a git repository to use any command

**Critical pattern**: All internal functions use `_cw_` prefix; only `claude-worktree` is public

**Integration point**: Calls `claude --dangerously-skip-permissions` to launch Claude Code
