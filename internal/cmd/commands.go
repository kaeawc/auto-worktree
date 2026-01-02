// Package cmd provides command implementations for the auto-worktree CLI.
package cmd

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/kaeawc/auto-worktree/internal/git"
	"github.com/kaeawc/auto-worktree/internal/github"
	"github.com/kaeawc/auto-worktree/internal/ui"

	tea "github.com/charmbracelet/bubbletea"
)

// RunInteractiveMenu displays the main interactive menu.
func RunInteractiveMenu() error {
	items := []ui.MenuItem{
		ui.NewMenuItem("New Worktree", "Create a new worktree with a new branch", "new"),
		ui.NewMenuItem("Resume Worktree", "Resume working on the last worktree", "resume"),
		ui.NewMenuItem("Work on Issue", "Create worktree for a GitHub/GitLab/JIRA issue", "issue"),
		ui.NewMenuItem("Create Issue", "Create a new issue and start working on it", "create"),
		ui.NewMenuItem("Review PR", "Review a pull request in a new worktree", "pr"),
		ui.NewMenuItem("List Worktrees", "Show all existing worktrees", "list"),
		ui.NewMenuItem("Cleanup Worktrees", "Interactive cleanup of merged/stale worktrees", "cleanup"),
		ui.NewMenuItem("Settings", "Configure per-repository settings", "settings"),
	}

	menu := ui.NewMenu("auto-worktree", items)
	p := tea.NewProgram(menu)

	m, err := p.Run()
	if err != nil {
		return fmt.Errorf("failed to run menu: %w", err)
	}

	finalModel, ok := m.(ui.MenuModel)
	if !ok {
		return fmt.Errorf("unexpected model type")
	}

	choice := finalModel.Choice()

	if choice == "" {
		return nil
	}

	// Route to the appropriate command handler
	return routeMenuChoice(choice)
}

func routeMenuChoice(choice string) error {
	switch choice {
	case "new":
		return RunNew()
	case "resume":
		return RunResume()
	case "issue":
		return RunIssue("")
	case "create":
		return RunCreate()
	case "pr":
		return RunPR("")
	case "list":
		return RunList()
	case "cleanup":
		return RunCleanup()
	case "settings":
		return RunSettings()
	default:
		return fmt.Errorf("unknown command: %s", choice)
	}
}

// RunList lists all worktrees.
func RunList() error {
	repo, err := git.NewRepository()
	if err != nil {
		return fmt.Errorf("error: %w", err)
	}

	worktrees, err := repo.ListWorktrees()
	if err != nil {
		return fmt.Errorf("error listing worktrees: %w", err)
	}

	if len(worktrees) == 0 {
		fmt.Println("No worktrees found")
		return nil
	}

	fmt.Printf("Repository: %s\n", repo.SourceFolder)
	fmt.Printf("Worktree base: %s\n\n", repo.WorktreeBase)
	fmt.Printf("%-50s %-25s %-15s %s\n", "PATH", "BRANCH", "AGE", "UNPUSHED")
	fmt.Println(strings.Repeat("-", 110))

	for _, wt := range worktrees {
		path := wt.Path
		branch := wt.Branch

		if branch == "" {
			branch = fmt.Sprintf("(detached @ %s)", wt.HEAD[:7])
		}

		age := formatAge(wt.Age())
		unpushed := ""

		if wt.UnpushedCount > 0 {
			unpushed = fmt.Sprintf("%d commits", wt.UnpushedCount)
		} else if !wt.IsDetached {
			unpushed = "up to date"
		}

		// Truncate path if too long
		if len(path) > 48 {
			path = "..." + path[len(path)-45:]
		}

		fmt.Printf("%-50s %-25s %-15s %s\n", path, branch, age, unpushed)
	}

	fmt.Printf("\nTotal: %d worktree(s)\n", len(worktrees))

	return nil
}

// RunNew creates a new worktree.
func RunNew() error {
	repo, err := git.NewRepository()
	if err != nil {
		return fmt.Errorf("error: %w", err)
	}

	branchName, useExisting, err := getBranchInput()
	if err != nil {
		return err
	}

	// Sanitize branch name
	sanitizedName := git.SanitizeBranchName(branchName)

	// Check if worktree already exists for this branch
	if err := checkExistingWorktree(repo, branchName); err != nil {
		return err
	}

	// Construct worktree path
	worktreePath := filepath.Join(repo.WorktreeBase, sanitizedName)

	if err := createWorktree(repo, worktreePath, branchName, useExisting); err != nil {
		return err
	}

	fmt.Printf("✓ Worktree created at: %s\n", worktreePath)
	fmt.Printf("\nTo start working:\n")
	fmt.Printf("  cd %s\n", worktreePath)

	return nil
}

func getBranchInput() (branchName string, useExisting bool, err error) {
	if len(os.Args) > 2 {
		// Command line argument provided
		arg := os.Args[2]
		if arg == "--existing" {
			if len(os.Args) < 4 {
				return "", false, fmt.Errorf("branch name required after --existing")
			}

			return os.Args[3], true, nil
		}

		return arg, false, nil
	}

	// Interactive mode
	input := ui.NewInput("Enter branch name:", "feature/my-feature or leave empty for random name")
	p := tea.NewProgram(input)

	m, err := p.Run()
	if err != nil {
		return "", false, fmt.Errorf("failed to get input: %w", err)
	}

	finalModel, ok := m.(ui.InputModel)
	if !ok {
		return "", false, fmt.Errorf("unexpected model type")
	}

	if finalModel.Err() != nil {
		return "", false, finalModel.Err()
	}

	branchName = finalModel.Value()
	if branchName == "" {
		// TODO: Generate random branch name
		return "", false, fmt.Errorf("random branch names not yet implemented - please provide a branch name")
	}

	return branchName, false, nil
}

func checkExistingWorktree(repo *git.Repository, branchName string) error {
	existingWt, err := repo.GetWorktreeForBranch(branchName)
	if err != nil {
		return fmt.Errorf("error checking for existing worktree: %w", err)
	}

	if existingWt != nil {
		return fmt.Errorf("worktree already exists for branch %s at %s", branchName, existingWt.Path)
	}

	return nil
}

func createWorktree(repo *git.Repository, worktreePath, branchName string, useExisting bool) error {
	if useExisting {
		// Check if branch exists
		if !repo.BranchExists(branchName) {
			return fmt.Errorf("branch %s does not exist", branchName)
		}

		fmt.Printf("Creating worktree for existing branch: %s\n", branchName)

		return repo.CreateWorktree(worktreePath, branchName)
	}

	// Check if branch already exists
	if repo.BranchExists(branchName) {
		return fmt.Errorf("branch %s already exists. Use --existing flag to create worktree for it", branchName)
	}

	// Get default branch as base
	defaultBranch, err := repo.GetDefaultBranch()
	if err != nil {
		return fmt.Errorf("error getting default branch: %w", err)
	}

	fmt.Printf("Creating worktree with new branch: %s (from %s)\n", branchName, defaultBranch)

	return repo.CreateWorktreeWithNewBranch(worktreePath, branchName, defaultBranch)
}

// RunResume resumes the last worktree.
func RunResume() error {
	// TODO: Implement resume logic
	return fmt.Errorf("'resume' command not yet implemented")
}

// RunIssue works on an issue.
// If issueID is empty, shows interactive issue selector.
// If issueID is numeric, directly creates worktree for that issue.
func RunIssue(issueID string) error {
	// 1. Initialize repository
	repo, err := git.NewRepository()
	if err != nil {
		return fmt.Errorf("error: %w", err)
	}

	// 2. Check gh CLI availability
	if !github.IsInstalled() {
		return fmt.Errorf("gh CLI is not installed. Install with: brew install gh")
	}

	// 3. Create GitHub client (auto-detects owner/repo)
	client, err := github.NewClient(repo.RootPath)
	if err != nil {
		if errors.Is(err, github.ErrGHNotInstalled) {
			return fmt.Errorf("gh CLI is not installed. Install with: brew install gh")
		}
		if errors.Is(err, github.ErrGHNotAuthenticated) {
			return fmt.Errorf("gh CLI is not authenticated. Run: gh auth login")
		}
		if errors.Is(err, github.ErrNotGitHubRepo) {
			return fmt.Errorf("not a GitHub repository")
		}
		return fmt.Errorf("failed to initialize GitHub client: %w", err)
	}

	fmt.Printf("Repository: %s/%s\n\n", client.Owner, client.Repo)

	// 4. Get issue number (interactive or direct)
	var issueNum int
	if issueID == "" {
		// Interactive mode: show issue selector
		issueNum, err = selectIssueInteractive(client, repo)
		if err != nil {
			return err
		}
	} else {
		// Direct mode: parse issue number
		issueNum, err = parseIssueNumber(issueID)
		if err != nil {
			return fmt.Errorf("invalid issue number: %s", issueID)
		}
	}

	// 5. Fetch full issue details
	issue, err := client.GetIssue(issueNum)
	if err != nil {
		return fmt.Errorf("failed to fetch issue #%d: %w", issueNum, err)
	}

	// 6. Check if issue is closed/merged
	if issue.State == "CLOSED" {
		merged, err := client.IsIssueMerged(issueNum)
		if err != nil {
			fmt.Printf("Warning: Could not check merge status: %v\n", err)
		} else if merged {
			return fmt.Errorf("issue #%d is already closed and merged", issueNum)
		} else {
			fmt.Printf("Warning: Issue #%d is closed but not merged\n", issueNum)
		}
	}

	// 7. Generate branch name: work/<number>-<sanitized-title>
	branchName := issue.BranchName()

	// 8. Check if worktree already exists
	existingWt, err := repo.GetWorktreeForBranch(branchName)
	if err != nil {
		return fmt.Errorf("error checking for existing worktree: %w", err)
	}

	if existingWt != nil {
		// Offer to resume existing worktree
		return offerResumeWorktree(existingWt, issue)
	}

	// 9. Create worktree
	worktreePath := filepath.Join(repo.WorktreeBase, git.SanitizeBranchName(branchName))

	// Check if branch exists
	if repo.BranchExists(branchName) {
		fmt.Printf("Creating worktree for existing branch: %s\n", branchName)
		if err := repo.CreateWorktree(worktreePath, branchName); err != nil {
			return fmt.Errorf("failed to create worktree: %w", err)
		}
	} else {
		defaultBranch, err := repo.GetDefaultBranch()
		if err != nil {
			return fmt.Errorf("error getting default branch: %w", err)
		}

		fmt.Printf("Creating worktree for issue #%d: %s\n", issue.Number, issue.Title)
		fmt.Printf("Branch: %s (from %s)\n", branchName, defaultBranch)

		if err := repo.CreateWorktreeWithNewBranch(worktreePath, branchName, defaultBranch); err != nil {
			return fmt.Errorf("failed to create worktree: %w", err)
		}
	}

	// 10. Display success message
	fmt.Printf("\n✓ Worktree created at: %s\n", worktreePath)
	fmt.Printf("\nIssue #%d: %s\n", issue.Number, issue.Title)
	fmt.Printf("URL: %s\n", issue.URL)
	fmt.Printf("\nTo start working:\n")
	fmt.Printf("  cd %s\n", worktreePath)

	return nil
}

// RunCreate creates a new issue.
func RunCreate() error {
	// TODO: Implement issue creation
	return fmt.Errorf("'create' command not yet implemented")
}

// RunPR reviews a pull request.
func RunPR(_ string) error {
	// TODO: Implement PR review workflow
	return fmt.Errorf("'pr' command not yet implemented")
}

// RunCleanup performs interactive cleanup.
func RunCleanup() error {
	// TODO: Implement cleanup workflow
	return fmt.Errorf("'cleanup' command not yet implemented")
}

// RunSettings shows settings menu.
func RunSettings() error {
	// TODO: Implement settings menu
	return fmt.Errorf("'settings' command not yet implemented")
}

// RunRemove removes a worktree.
func RunRemove(path string) error {
	repo, err := git.NewRepository()
	if err != nil {
		return fmt.Errorf("error: %w", err)
	}

	// Expand ~ to home directory
	if strings.HasPrefix(path, "~") {
		homeDir, homeErr := os.UserHomeDir()
		if homeErr == nil {
			path = filepath.Join(homeDir, path[1:])
		}
	}

	// Make absolute path
	if !filepath.IsAbs(path) {
		path, err = filepath.Abs(path)
		if err != nil {
			return fmt.Errorf("error resolving path: %w", err)
		}
	}

	fmt.Printf("Removing worktree: %s\n", path)

	err = repo.RemoveWorktree(path)
	if err != nil {
		return fmt.Errorf("error removing worktree: %w", err)
	}

	fmt.Printf("✓ Worktree removed\n")

	return nil
}

// RunPrune prunes orphaned worktrees.
func RunPrune() error {
	repo, err := git.NewRepository()
	if err != nil {
		return fmt.Errorf("error: %w", err)
	}

	fmt.Println("Pruning orphaned worktrees...")

	err = repo.PruneWorktrees()
	if err != nil {
		return fmt.Errorf("error pruning worktrees: %w", err)
	}

	fmt.Println("✓ Pruned orphaned worktrees")

	return nil
}

// formatAge formats a duration into a human-readable string.
func formatAge(d time.Duration) string {
	days := int(d.Hours() / 24)
	hours := int(d.Hours()) % 24
	minutes := int(d.Minutes()) % 60

	switch {
	case days > 0:
		return fmt.Sprintf("%dd %dh", days, hours)
	case hours > 0:
		return fmt.Sprintf("%dh %dm", hours, minutes)
	default:
		return fmt.Sprintf("%dm", minutes)
	}
}

// Helper functions for RunIssue

// selectIssueInteractive shows a filterable list of issues and returns the selected issue number
func selectIssueInteractive(client *github.Client, repo *git.Repository) (int, error) {
	// Fetch issues
	fmt.Println("Fetching issues...")
	issues, err := client.ListOpenIssues(100)
	if err != nil {
		return 0, fmt.Errorf("failed to fetch issues: %w", err)
	}

	if len(issues) == 0 {
		return 0, fmt.Errorf("no open issues found")
	}

	// Convert to filterable list items
	items := make([]ui.FilterableListItem, len(issues))
	for i, issue := range issues {
		// Check if worktree exists for this issue
		branchName := issue.BranchName()
		wt, err := repo.GetWorktreeForBranch(branchName)
		if err != nil {
			// Ignore error, just mark as no worktree
			wt = nil
		}

		// Extract label names
		labelNames := make([]string, len(issue.Labels))
		for j, label := range issue.Labels {
			labelNames[j] = label.Name
		}

		items[i] = ui.NewFilterableListItem(
			issue.Number,
			issue.Title,
			labelNames,
			wt != nil,
		)
	}

	// Show filterable list
	filterList := ui.NewFilterList("Select an issue to work on", items)
	p := tea.NewProgram(filterList, tea.WithAltScreen())

	m, err := p.Run()
	if err != nil {
		return 0, fmt.Errorf("failed to run issue selector: %w", err)
	}

	finalModel, ok := m.(ui.FilterListModel)
	if !ok {
		return 0, fmt.Errorf("unexpected model type")
	}

	if finalModel.Err() != nil {
		return 0, finalModel.Err()
	}

	choice := finalModel.Choice()
	if choice == nil {
		return 0, fmt.Errorf("no issue selected")
	}

	return choice.Number(), nil
}

// parseIssueNumber parses an issue number from a string, handling "#" prefix
func parseIssueNumber(s string) (int, error) {
	// Remove # prefix if present
	s = strings.TrimPrefix(s, "#")
	return strconv.Atoi(s)
}

// offerResumeWorktree displays information about an existing worktree for an issue
func offerResumeWorktree(wt *git.Worktree, issue *github.Issue) error {
	fmt.Printf("Worktree already exists for issue #%d\n", issue.Number)
	fmt.Printf("Path: %s\n", wt.Path)
	fmt.Printf("Branch: %s\n", wt.Branch)
	fmt.Printf("\nTo resume working:\n")
	fmt.Printf("  cd %s\n", wt.Path)
	return nil
}
