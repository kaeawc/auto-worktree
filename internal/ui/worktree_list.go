package ui

import (
	"fmt"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/list"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/kaeawc/auto-worktree/internal/git"
)

// WorktreeListItem wraps a Worktree for use in the list component
type WorktreeListItem struct {
	worktree *git.Worktree
}

func (i WorktreeListItem) Title() string {
	if i.worktree.Branch != "" {
		return i.worktree.Branch
	}
	return fmt.Sprintf("(detached) %s", i.worktree.HEAD[:8])
}

func (i WorktreeListItem) Description() string {
	parts := []string{}

	// Path
	parts = append(parts, i.worktree.Path)

	// Age with color indicator
	age := time.Since(i.worktree.LastCommitTime)
	ageStyle := GetWorktreeAgeStyle(age)
	ageStr := formatAge(age)
	parts = append(parts, ageStyle.Render(ageStr))

	// Unpushed commits
	if i.worktree.UnpushedCount > 0 {
		unpushedStr := fmt.Sprintf("↑%d unpushed", i.worktree.UnpushedCount)
		parts = append(parts, WarningStyle.Render(unpushedStr))
	}

	return strings.Join(parts, " • ")
}

func (i WorktreeListItem) FilterValue() string {
	return i.worktree.Branch + " " + i.worktree.Path
}

// formatAge formats a duration into a human-readable string
func formatAge(d time.Duration) string {
	days := int(d.Hours() / 24)
	hours := int(d.Hours()) % 24

	switch {
	case days > 0:
		return fmt.Sprintf("%dd %dh ago", days, hours)
	case hours > 0:
		return fmt.Sprintf("%dh ago", hours)
	default:
		minutes := int(d.Minutes())
		return fmt.Sprintf("%dm ago", minutes)
	}
}

// WorktreeListModel represents the worktree list view
type WorktreeListModel struct {
	list      list.Model
	repo      *git.Repository
	worktrees []*git.Worktree
	choice    *git.Worktree
	quitting  bool
}

// NewWorktreeListModel creates a new worktree list model
func NewWorktreeListModel(repo *git.Repository) (*WorktreeListModel, error) {
	worktrees, err := repo.ListWorktrees()
	if err != nil {
		return nil, fmt.Errorf("failed to list worktrees: %w", err)
	}

	items := make([]list.Item, len(worktrees))
	for i, wt := range worktrees {
		items[i] = WorktreeListItem{worktree: wt}
	}

	const defaultWidth = 80
	const defaultHeight = 20

	delegate := list.NewDefaultDelegate()
	delegate.Styles.SelectedTitle = SelectedItemStyle
	delegate.Styles.SelectedDesc = lipgloss.NewStyle().Foreground(ColorCyan)

	l := list.New(items, delegate, defaultWidth, defaultHeight)
	l.Title = "Worktrees"
	l.Styles.Title = TitleStyle
	l.AdditionalShortHelpKeys = func() []key.Binding {
		return []key.Binding{
			key.NewBinding(
				key.WithKeys("enter"),
				key.WithHelp("enter", "select"),
			),
			key.NewBinding(
				key.WithKeys("d"),
				key.WithHelp("d", "delete"),
			),
		}
	}

	return &WorktreeListModel{
		list:      l,
		repo:      repo,
		worktrees: worktrees,
	}, nil
}

func (m WorktreeListModel) Init() tea.Cmd {
	return nil
}

func (m WorktreeListModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.list.SetWidth(msg.Width)
		m.list.SetHeight(msg.Height - 2)
		return m, nil

	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "q":
			m.quitting = true
			return m, tea.Quit

		case "enter":
			if selectedItem, ok := m.list.SelectedItem().(WorktreeListItem); ok {
				m.choice = selectedItem.worktree
				m.quitting = true
				return m, tea.Quit
			}

		case "d":
			// Delete worktree action - to be implemented
			if selectedItem, ok := m.list.SelectedItem().(WorktreeListItem); ok {
				// TODO: Show confirmation dialog
				_ = selectedItem
			}
		}
	}

	var cmd tea.Cmd
	m.list, cmd = m.list.Update(msg)
	return m, cmd
}

func (m WorktreeListModel) View() string {
	if m.quitting {
		return ""
	}
	return "\n" + m.list.View()
}

// GetChoice returns the selected worktree, if any
func (m WorktreeListModel) GetChoice() *git.Worktree {
	return m.choice
}
