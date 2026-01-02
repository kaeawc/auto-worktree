# Interactive UI Guide

This guide covers the interactive TUI (Terminal User Interface) features added to auto-worktree using Bubble Tea.

## Overview

Auto-worktree now supports both traditional CLI commands and an interactive menu-driven interface. The interactive mode provides:

- Intuitive navigation with arrow keys
- Visual selection menus
- Color-coded status indicators
- Confirmation dialogs for destructive operations
- Settings configuration interface

## Launching Interactive Mode

### Default Behavior

Simply run `auto-worktree` without any arguments to launch interactive mode:

```bash
auto-worktree
```

### Explicit Interactive Flag

You can also explicitly request interactive mode:

```bash
auto-worktree interactive
# or
auto-worktree -i
```

### Hybrid Mode

Most commands support both CLI and interactive modes:

```bash
# Traditional CLI
auto-worktree list

# Interactive list view
auto-worktree list --interactive
```

## Main Menu

The main menu provides access to all major features:

1. **List Worktrees** - View and manage existing worktrees interactively
2. **New Worktree** - Create a new worktree (coming soon)
3. **Remove Worktree** - Remove an existing worktree (coming soon)
4. **Prune Worktrees** - Clean up orphaned worktree references
5. **Settings** - Configure providers and preferences
6. **Quit** - Exit the application

### Navigation

- **↑/↓ or j/k** - Navigate up/down
- **Enter** - Select current item
- **q or Ctrl+C** - Quit/go back
- **/** - Filter/search (in list views)

## Worktree List View

The interactive worktree list shows:

- **Branch name** (or detached HEAD state)
- **Path** to the worktree
- **Age** with color coding:
  - 🟢 Green: Recent (< 1 day)
  - 🟡 Yellow: 1-4 days old
  - 🔴 Red: Stale (> 4 days)
- **Unpushed commits** count

### Actions

- **Enter** - Select a worktree (shows path for switching)
- **d** - Delete selected worktree (coming soon)
- **/** - Filter by branch name or path

## Settings Menu

Configure auto-worktree settings interactively:

1. **Issue Provider** - Select GitHub, GitLab, JIRA, or Linear
2. **AI Tool** - Configure Claude Code, Codex, Gemini, or skip
3. **GitHub Settings** - Configure GitHub-specific options (coming soon)
4. **GitLab Settings** - Configure GitLab server and project (coming soon)
5. **JIRA Settings** - Configure JIRA server and project key (coming soon)
6. **Linear Settings** - Configure Linear team settings (coming soon)
7. **Auto-Select Options** - Enable/disable automatic selection (coming soon)

### Provider Selection

When selecting an issue provider, choose from:

- **GitHub** - Use GitHub Issues and Pull Requests
- **GitLab** - Use GitLab Issues and Merge Requests
- **JIRA** - Use Atlassian JIRA for issue tracking
- **Linear** - Use Linear for issue tracking

Settings are saved to git config for the current repository.

### AI Tool Selection

Choose your preferred AI coding assistant:

- **Claude Code** (Anthropic) - Install and configure Claude Code CLI
- **Codex CLI** (OpenAI) - Install and configure OpenAI Codex
- **Gemini** - Install and configure Google Gemini
- **Skip** - Don't use an AI tool

## Color Scheme

The interactive UI matches the existing gum-based color scheme:

| Color | Usage | Example |
|-------|-------|---------|
| Red (1) | Errors, stale worktrees (>4 days) | Error messages, old branches |
| Green (2) | Success, recent worktrees (<1 day) | Success messages, fresh work |
| Yellow (3) | Warnings, worktrees 1-4 days old | Warnings, moderate age |
| Blue (4) | Info boxes, headers | Container borders, titles |
| Magenta (5) | Merged indicators | [merged #42] |
| Cyan (6) | Highlights, prompts | Selected items, section headers |

## Confirmation Dialogs

Destructive operations require confirmation:

```
┌─────────────────────────────────────────────────┐
│                                                 │
│ ⚠ Are you sure you want to prune orphaned     │
│   worktrees?                                    │
│                                                 │
│  ┌──────┐  No                                  │
│  │ Yes  │                                       │
│  └──────┘                                       │
│                                                 │
│ Use arrow keys or y/n to select, enter to      │
│ confirm                                         │
└─────────────────────────────────────────────────┘
```

Navigation:
- **←/→ or h/l** - Switch between Yes/No
- **y** - Select Yes
- **n** - Select No
- **Enter** - Confirm selection
- **Esc or q** - Cancel (defaults to No)

## Keyboard Shortcuts

### Global

- **q** - Quit current view / go back
- **Ctrl+C** - Force quit
- **?** - Show help (when available)

### List Views

- **↑/↓ or k/j** - Navigate up/down
- **Enter** - Select item
- **/** - Filter/search
- **Esc** - Clear filter

### Confirmation Dialogs

- **←/→ or h/l** - Switch option
- **y/n** - Quick select
- **Enter** - Confirm
- **Esc** - Cancel

## Backward Compatibility

All existing CLI commands continue to work:

```bash
# These still work exactly as before
auto-worktree list
auto-worktree new feature/my-feature
auto-worktree remove ~/worktrees/repo/branch
auto-worktree prune
auto-worktree version
auto-worktree help
```

The interactive mode is additive - it doesn't break any existing workflows.

## Coming Soon

Features currently stubbed out for future implementation:

- **Interactive worktree creation** - Guided flow with branch selection
- **Interactive worktree removal** - Select from list to remove
- **Issue/PR selection menus** - Browse and select from provider
- **Provider-specific settings** - Detailed configuration per provider
- **Auto-select configuration** - Toggle automatic selections
- **Keyboard shortcuts help** - Context-sensitive help overlay

## Implementation Details

### Architecture

The interactive UI is implemented using:

- **Bubble Tea** - TUI framework for terminal applications
- **Lipgloss** - Styling and layout library
- **Bubbles** - Pre-built UI components (lists, inputs, etc.)

### Package Structure

```
internal/ui/
├── theme.go           # Color scheme and styling constants
├── main_menu.go       # Main navigation menu
├── worktree_list.go   # Interactive worktree list view
├── settings_menu.go   # Settings/configuration menu
├── provider_menu.go   # Provider and AI tool selection
├── confirm.go         # Confirmation dialog component
└── *_test.go          # Unit tests for UI components
```

### Testing

Run UI component tests:

```bash
go test ./internal/ui/...
```

The tests verify:
- Menu initialization
- Color scheme logic (age-based coloring)
- Provider/tool constant values
- Component state management

## Troubleshooting

### Interactive Mode Not Launching

If interactive mode doesn't launch:

1. Ensure your terminal supports ANSI colors
2. Check terminal size is adequate (minimum 80x20)
3. Try explicit flag: `auto-worktree -i`

### Display Issues

If the UI looks corrupted:

1. Resize your terminal window
2. Try a different terminal emulator
3. Check `TERM` environment variable

### Navigation Not Working

If keyboard navigation fails:

1. Ensure your terminal sends proper key codes
2. Try alternative keys (j/k instead of arrows)
3. Check for terminal multiplexer conflicts (tmux/screen)

## Feedback

For bugs, feature requests, or feedback on the interactive UI:

- Open an issue: https://github.com/kaeawc/auto-worktree/issues
- Tag with `enhancement` and `devxp` labels
- Reference issue #76 for UI-related items
