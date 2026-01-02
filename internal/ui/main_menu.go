package ui

import (
	"github.com/charmbracelet/bubbles/list"
	tea "github.com/charmbracelet/bubbletea"
)

// MainMenuAction represents an action that can be selected from the main menu
type MainMenuAction int

const (
	ActionNone MainMenuAction = iota
	ActionListWorktrees
	ActionNewWorktree
	ActionRemoveWorktree
	ActionPruneWorktrees
	ActionSettings
	ActionQuit
)

// MenuItem represents an item in the main menu
type MenuItem struct {
	title       string
	description string
	action      MainMenuAction
}

func (i MenuItem) Title() string       { return i.title }
func (i MenuItem) Description() string { return i.description }
func (i MenuItem) FilterValue() string { return i.title }

// MainMenuModel represents the main navigation menu
type MainMenuModel struct {
	list     list.Model
	choice   MainMenuAction
	quitting bool
}

// NewMainMenuModel creates a new main menu model
func NewMainMenuModel() *MainMenuModel {
	items := []list.Item{
		MenuItem{
			title:       "List Worktrees",
			description: "View and manage existing worktrees",
			action:      ActionListWorktrees,
		},
		MenuItem{
			title:       "New Worktree",
			description: "Create a new worktree from a branch or issue",
			action:      ActionNewWorktree,
		},
		MenuItem{
			title:       "Remove Worktree",
			description: "Remove an existing worktree",
			action:      ActionRemoveWorktree,
		},
		MenuItem{
			title:       "Prune Worktrees",
			description: "Clean up orphaned worktree references",
			action:      ActionPruneWorktrees,
		},
		MenuItem{
			title:       "Settings",
			description: "Configure providers and preferences",
			action:      ActionSettings,
		},
		MenuItem{
			title:       "Quit",
			description: "Exit the application",
			action:      ActionQuit,
		},
	}

	const defaultWidth = 80
	const defaultHeight = 20

	delegate := list.NewDefaultDelegate()
	delegate.Styles.SelectedTitle = SelectedItemStyle
	delegate.Styles.SelectedDesc = HighlightStyle

	l := list.New(items, delegate, defaultWidth, defaultHeight)
	l.Title = "Auto Worktree - Main Menu"
	l.Styles.Title = TitleStyle
	l.SetShowStatusBar(false)

	return &MainMenuModel{
		list:   l,
		choice: ActionNone,
	}
}

func (m MainMenuModel) Init() tea.Cmd {
	return nil
}

func (m MainMenuModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.list.SetWidth(msg.Width)
		m.list.SetHeight(msg.Height - 2)
		return m, nil

	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "q":
			m.quitting = true
			m.choice = ActionQuit
			return m, tea.Quit

		case "enter":
			if selectedItem, ok := m.list.SelectedItem().(MenuItem); ok {
				m.choice = selectedItem.action
				m.quitting = true
				return m, tea.Quit
			}
		}
	}

	var cmd tea.Cmd
	m.list, cmd = m.list.Update(msg)
	return m, cmd
}

func (m MainMenuModel) View() string {
	if m.quitting {
		return ""
	}
	return "\n" + m.list.View()
}

// GetChoice returns the selected action
func (m MainMenuModel) GetChoice() MainMenuAction {
	return m.choice
}
