// Package main provides the auto-worktree CLI tool for managing git worktrees.
package main

import (
	"fmt"
	"os"

	"github.com/kaeawc/auto-worktree/internal/cmd"
)

const version = "0.1.0-dev"

func main() {
	// If no arguments, show interactive menu
	if len(os.Args) < 2 {
		if err := cmd.RunInteractiveMenu(); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
		return
	}

	command := os.Args[1]

	var err error

	switch command {
	case "version", "--version", "-v":
		fmt.Printf("auto-worktree version %s\n", version)
		return

	case "help", "--help", "-h":
		showHelp()
		return

	case "list", "ls":
		err = cmd.RunList()

	case "new", "create":
		err = cmd.RunNew()

	case "resume":
		err = cmd.RunResume()

	case "issue":
		issueID := ""
		if len(os.Args) > 2 {
			issueID = os.Args[2]
		}
		err = cmd.RunIssue(issueID)

	case "pr":
		prNum := ""
		if len(os.Args) > 2 {
			prNum = os.Args[2]
		}
		err = cmd.RunPR(prNum)

	case "cleanup":
		err = cmd.RunCleanup()

	case "settings":
		err = cmd.RunSettings()

	case "remove", "rm":
		if len(os.Args) < 3 {
			fmt.Fprintf(os.Stderr, "Error: worktree path required\n")
			fmt.Fprintf(os.Stderr, "Usage: auto-worktree remove <path>\n")
			os.Exit(1)
		}
		err = cmd.RunRemove(os.Args[2])

	case "prune":
		err = cmd.RunPrune()

	default:
		fmt.Fprintf(os.Stderr, "Unknown command: %s\n\n", command)
		showHelp()
		os.Exit(1)
	}

	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

func showHelp() {
	help := `auto-worktree - Git worktree management tool

USAGE:
    auto-worktree [command] [arguments]
    aw [command] [arguments]              # Shorter alias

COMMANDS:
    (no command)          Show interactive menu
    new [branch]          Create new worktree
    resume                Resume last worktree
    issue [id]            Work on an issue (GitHub, GitLab, JIRA, or Linear)
    create                Create a new issue and start working on it
    pr [num]              Review a pull request
    list, ls              List all worktrees with status
    cleanup               Interactive cleanup of merged/stale worktrees
    settings              Configure per-repository settings
    remove <path>         Remove a worktree
    prune                 Prune orphaned worktrees
    version               Show version information
    help                  Show this help message

EXAMPLES:
    # Show interactive menu
    auto-worktree

    # Create a new worktree
    auto-worktree new feature/new-feature

    # Work on a GitHub issue
    auto-worktree issue 42

    # Review a pull request
    auto-worktree pr 123

    # List all worktrees
    auto-worktree list

    # Resume last worktree
    auto-worktree resume

    # Interactive cleanup
    auto-worktree cleanup

    # Configure settings
    auto-worktree settings

    # Remove a worktree
    auto-worktree remove ~/worktrees/my-repo/feature-branch

    # Clean up orphaned worktrees
    auto-worktree prune

For more information, visit: https://github.com/kaeawc/auto-worktree
`
	fmt.Print(help)
}
