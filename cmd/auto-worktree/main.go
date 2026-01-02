// Package main provides the auto-worktree CLI tool for managing git worktrees.
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/x/term"
	"github.com/kaeawc/auto-worktree/internal/git"
	"github.com/kaeawc/auto-worktree/internal/ui"
)

const version = "0.1.0-dev"

func main() {
	// If no arguments provided, launch interactive mode if we have a TTY
	if len(os.Args) < 2 {
		if term.IsTerminal(os.Stdin.Fd()) {
			runInteractiveMode()
		} else {
			showHelp()
		}
		return
	}

	command := os.Args[1]

	switch command {
	case "version", "--version", "-v":
		fmt.Printf("auto-worktree version %s\n", version)
	case "help", "--help", "-h":
		showHelp()
	case "interactive", "-i":
		runInteractiveMode()
	case "list", "ls":
		if hasFlag("--interactive") {
			cmdListInteractive()
		} else {
			cmdList()
		}
	case "new", "create":
		cmdNew()
	case "remove", "rm":
		cmdRemove()
	case "prune":
		cmdPrune()
	default:
		fmt.Fprintf(os.Stderr, "Unknown command: %s\n\n", command)
		showHelp()
		os.Exit(1)
	}
}

// hasFlag checks if a flag is present in os.Args
func hasFlag(flag string) bool {
	for _, arg := range os.Args {
		if arg == flag {
			return true
		}
	}
	return false
}

// runInteractiveMode launches the main interactive TUI menu
func runInteractiveMode() {
	for {
		mainMenu := ui.NewMainMenuModel()
		p := tea.NewProgram(mainMenu, tea.WithAltScreen())

		model, err := p.Run()
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error running interactive mode: %v\n", err)
			os.Exit(1)
		}

		m := model.(ui.MainMenuModel)
		action := m.GetChoice()

		switch action {
		case ui.ActionListWorktrees:
			cmdListInteractive()
		case ui.ActionNewWorktree:
			// TODO: Implement interactive new worktree flow
			fmt.Println("\n" + ui.InfoStyle.Render("New worktree creation coming soon!"))
			fmt.Println("For now, use: auto-worktree new <branch-name>")
			fmt.Println()
		case ui.ActionRemoveWorktree:
			// TODO: Implement interactive remove worktree flow
			fmt.Println("\n" + ui.InfoStyle.Render("Interactive worktree removal coming soon!"))
			fmt.Println("For now, use: auto-worktree remove <path>")
			fmt.Println()
		case ui.ActionPruneWorktrees:
			cmdPruneInteractive()
		case ui.ActionSettings:
			runSettingsMenu()
		case ui.ActionQuit:
			fmt.Println("\n" + ui.SuccessStyle.Render("Goodbye!"))
			return
		default:
			return
		}
	}
}

// runSettingsMenu launches the settings menu
func runSettingsMenu() {
	for {
		settingsMenu := ui.NewSettingsMenuModel()
		p := tea.NewProgram(settingsMenu, tea.WithAltScreen())

		model, err := p.Run()
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error running settings menu: %v\n", err)
			return
		}

		m := model.(ui.SettingsMenuModel)
		action := m.GetChoice()

		switch action {
		case ui.SettingsActionIssueProvider:
			runProviderSelection()
		case ui.SettingsActionAITool:
			runAIToolSelection()
		case ui.SettingsActionGitHubSettings:
			fmt.Println("\n" + ui.InfoStyle.Render("GitHub settings coming soon!"))
			fmt.Println()
		case ui.SettingsActionGitLabSettings:
			fmt.Println("\n" + ui.InfoStyle.Render("GitLab settings coming soon!"))
			fmt.Println()
		case ui.SettingsActionJiraSettings:
			fmt.Println("\n" + ui.InfoStyle.Render("JIRA settings coming soon!"))
			fmt.Println()
		case ui.SettingsActionLinearSettings:
			fmt.Println("\n" + ui.InfoStyle.Render("Linear settings coming soon!"))
			fmt.Println()
		case ui.SettingsActionAutoSelect:
			fmt.Println("\n" + ui.InfoStyle.Render("Auto-select settings coming soon!"))
			fmt.Println()
		case ui.SettingsActionBack:
			return
		default:
			return
		}
	}
}

// runProviderSelection shows the provider selection menu
func runProviderSelection() {
	providerMenu := ui.NewProviderMenuModel()
	p := tea.NewProgram(providerMenu, tea.WithAltScreen())

	model, err := p.Run()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error running provider selection: %v\n", err)
		return
	}

	m := model.(ui.ProviderMenuModel)
	provider := m.GetChoice()

	if provider != "" {
		// TODO: Save to git config
		fmt.Println("\n" + ui.SuccessStyle.Render("Provider set to: "+string(provider)))
		fmt.Println(ui.InfoStyle.Render("(Note: Provider integration coming soon)"))
		fmt.Println()
	}
}

// runAIToolSelection shows the AI tool selection menu
func runAIToolSelection() {
	aiToolMenu := ui.NewAIToolMenuModel()
	p := tea.NewProgram(aiToolMenu, tea.WithAltScreen())

	model, err := p.Run()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error running AI tool selection: %v\n", err)
		return
	}

	m := model.(ui.AIToolMenuModel)
	tool := m.GetChoice()

	if tool != "" {
		// TODO: Save to git config
		fmt.Println("\n" + ui.SuccessStyle.Render("AI tool set to: "+string(tool)))
		fmt.Println(ui.InfoStyle.Render("(Note: AI tool integration coming soon)"))
		fmt.Println()
	}
}

// cmdListInteractive shows an interactive list of worktrees
func cmdListInteractive() {
	repo, err := git.NewRepository()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	worktreeList, err := ui.NewWorktreeListModel(repo)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	p := tea.NewProgram(worktreeList, tea.WithAltScreen())
	model, err := p.Run()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error running interactive list: %v\n", err)
		os.Exit(1)
	}

	m := model.(ui.WorktreeListModel)
	if choice := m.GetChoice(); choice != nil {
		// User selected a worktree
		fmt.Println("\n" + ui.InfoStyle.Render(fmt.Sprintf("Selected worktree: %s", choice.Path)))
		fmt.Printf("\nTo switch to this worktree:\n")
		fmt.Printf("  cd %s\n", choice.Path)
		fmt.Println()
	}
}

// cmdPruneInteractive shows a confirmation dialog before pruning
func cmdPruneInteractive() {
	confirmModel := ui.NewConfirmModel("Are you sure you want to prune orphaned worktrees?")
	p := tea.NewProgram(confirmModel)

	model, err := p.Run()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return
	}

	m := model.(ui.ConfirmModel)
	if m.GetChoice() {
		cmdPrune()
	} else {
		fmt.Println("\n" + ui.InfoStyle.Render("Prune cancelled"))
		fmt.Println()
	}
}

func showHelp() {
	help := `auto-worktree - Git worktree management tool

USAGE:
    auto-worktree                      Launch interactive mode (default)
    auto-worktree <command> [arguments]

COMMANDS:
    interactive, -i       Launch interactive TUI menu
    list, ls              List all worktrees with status
    list --interactive    List worktrees in interactive mode
    new <branch>          Create new worktree with new branch
    new --existing <branch>
                         Create worktree for existing branch
    remove <path>         Remove a worktree
    prune                 Prune orphaned worktrees
    version              Show version information
    help                 Show this help message

EXAMPLES:
    # Launch interactive mode
    auto-worktree

    # List all worktrees (plain text)
    auto-worktree list

    # List worktrees (interactive)
    auto-worktree list --interactive

    # Create a new worktree with a new branch
    auto-worktree new feature/new-feature

    # Create a worktree for an existing branch
    auto-worktree new --existing feature/existing-branch

    # Remove a worktree
    auto-worktree remove ~/worktrees/my-repo/feature-branch

    # Clean up orphaned worktrees
    auto-worktree prune

For more information, visit: https://github.com/kaeawc/auto-worktree
`
	fmt.Print(help)
}

func cmdList() {
	repo, err := git.NewRepository()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	worktrees, err := repo.ListWorktrees()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error listing worktrees: %v\n", err)
		os.Exit(1)
	}

	if len(worktrees) == 0 {
		fmt.Println("No worktrees found")
		return
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
}

func cmdNew() {
	if len(os.Args) < 3 {
		fmt.Fprintf(os.Stderr, "Error: branch name required\n")
		fmt.Fprintf(os.Stderr, "Usage: auto-worktree new <branch>\n")
		os.Exit(1)
	}

	repo, err := git.NewRepository()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	useExisting := false
	branchName := os.Args[2]

	// Check for --existing flag
	if branchName == "--existing" {
		if len(os.Args) < 4 {
			fmt.Fprintf(os.Stderr, "Error: branch name required after --existing\n")
			os.Exit(1)
		}
		useExisting = true
		branchName = os.Args[3]
	}

	// Sanitize branch name
	sanitizedName := git.SanitizeBranchName(branchName)

	// Check if worktree already exists for this branch
	existingWt, err := repo.GetWorktreeForBranch(branchName)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error checking for existing worktree: %v\n", err)
		os.Exit(1)
	}
	if existingWt != nil {
		fmt.Fprintf(os.Stderr, "Error: worktree already exists for branch %s at %s\n", branchName, existingWt.Path)
		os.Exit(1)
	}

	// Construct worktree path
	worktreePath := filepath.Join(repo.WorktreeBase, sanitizedName)

	if useExisting {
		// Check if branch exists
		if !repo.BranchExists(branchName) {
			fmt.Fprintf(os.Stderr, "Error: branch %s does not exist\n", branchName)
			os.Exit(1)
		}

		fmt.Printf("Creating worktree for existing branch: %s\n", branchName)
		err = repo.CreateWorktree(worktreePath, branchName)
	} else {
		// Check if branch already exists
		if repo.BranchExists(branchName) {
			fmt.Fprintf(os.Stderr, "Error: branch %s already exists. Use --existing flag to create worktree for it.\n", branchName)
			os.Exit(1)
		}

		// Get default branch as base
		defaultBranch, err := repo.GetDefaultBranch()
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error getting default branch: %v\n", err)
			os.Exit(1)
		}

		fmt.Printf("Creating worktree with new branch: %s (from %s)\n", branchName, defaultBranch)
		err = repo.CreateWorktreeWithNewBranch(worktreePath, branchName, defaultBranch)
	}

	if err != nil {
		fmt.Fprintf(os.Stderr, "Error creating worktree: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("✓ Worktree created at: %s\n", worktreePath)
	fmt.Printf("\nTo start working:\n")
	fmt.Printf("  cd %s\n", worktreePath)
}

func cmdRemove() {
	if len(os.Args) < 3 {
		fmt.Fprintf(os.Stderr, "Error: worktree path required\n")
		fmt.Fprintf(os.Stderr, "Usage: auto-worktree remove <path>\n")
		os.Exit(1)
	}

	repo, err := git.NewRepository()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	worktreePath := os.Args[2]

	// Expand ~ to home directory
	if strings.HasPrefix(worktreePath, "~") {
		homeDir, err := os.UserHomeDir()
		if err == nil {
			worktreePath = filepath.Join(homeDir, worktreePath[1:])
		}
	}

	// Make absolute path
	if !filepath.IsAbs(worktreePath) {
		worktreePath, err = filepath.Abs(worktreePath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error resolving path: %v\n", err)
			os.Exit(1)
		}
	}

	fmt.Printf("Removing worktree: %s\n", worktreePath)

	err = repo.RemoveWorktree(worktreePath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error removing worktree: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("✓ Worktree removed\n")
}

func cmdPrune() {
	repo, err := git.NewRepository()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	fmt.Println("Pruning orphaned worktrees...")

	err = repo.PruneWorktrees()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error pruning worktrees: %v\n", err)
		os.Exit(1)
	}

	fmt.Println("✓ Pruned orphaned worktrees")
}

func formatAge(d time.Duration) string {
	days := int(d.Hours() / 24)
	hours := int(d.Hours()) % 24
	minutes := int(d.Minutes()) % 60

	if days > 0 {
		return fmt.Sprintf("%dd %dh", days, hours)
	} else if hours > 0 {
		return fmt.Sprintf("%dh %dm", hours, minutes)
	} else {
		return fmt.Sprintf("%dm", minutes)
	}
}
