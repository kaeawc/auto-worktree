package ui

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

const (
	scopeLocal  = "local"
	scopeGlobal = "global"
)

// SettingsViewerModel displays all current settings
type SettingsViewerModel struct {
	content  string
	quitting bool
}

// ConfigValue represents a config key-value pair with scope
type ConfigValue struct {
	Key   string
	Value string
	Scope string // "local", "global", or empty if not set
}

// settingCategories defines the grouping and order of settings
var settingCategories = map[string][]string{
	"Issue Provider": {
		"auto-worktree.issue-provider",
	},
	"AI Tool": {
		"auto-worktree.ai-tool",
	},
	"Auto-select": {
		"auto-worktree.issue-autoselect",
		"auto-worktree.pr-autoselect",
	},
	"Hooks": {
		"auto-worktree.run-hooks",
		"auto-worktree.fail-on-hook-error",
		"auto-worktree.custom-hooks",
	},
	"Issue Templates": {
		"auto-worktree.issue-templates-dir",
		"auto-worktree.issue-templates-disabled",
		"auto-worktree.issue-templates-no-prompt",
		"auto-worktree.issue-templates-detected",
	},
	"Provider Configuration": {
		"auto-worktree.jira-server",
		"auto-worktree.jira-project",
		"auto-worktree.gitlab-server",
		"auto-worktree.gitlab-project",
		"auto-worktree.linear-team",
	},
}

var categoryOrder = []string{
	"Issue Provider",
	"AI Tool",
	"Auto-select",
	"Hooks",
	"Issue Templates",
	"Provider Configuration",
}

// formatSettingValue formats a config value for display
func formatSettingValue(val string, scope string, isLocal bool) string {
	scopeLabel := SubtleStyle.Render(fmt.Sprintf("[%s]", scope))
	var styledValue string

	switch {
	case val == "":
		styledValue = SubtleStyle.Render("(not set)")
	case isLocal:
		styledValue = SuccessStyle.Render(val)
	default:
		styledValue = InfoStyle.Render(val)
	}

	return fmt.Sprintf("  %s %s\n", scopeLabel, styledValue)
}

// renderCategory renders a single category of settings
func renderCategory(category string, keys []string, localValues, globalValues map[string]string) string {
	var categoryContent strings.Builder

	categoryContent.WriteString(HeaderStyle.Render(category) + "\n")

	hasValues := false

	for _, key := range keys {
		localVal, hasLocal := localValues[key]
		globalVal, hasGlobal := globalValues[key]

		if !hasLocal && !hasGlobal {
			continue
		}

		hasValues = true
		shortKey := strings.TrimPrefix(key, "auto-worktree.")
		categoryContent.WriteString(fmt.Sprintf("  %s\n", shortKey))

		if hasLocal {
			categoryContent.WriteString(formatSettingValue(localVal, scopeLocal, true))
		}

		if hasGlobal && (!hasLocal || globalVal != localVal) {
			categoryContent.WriteString(formatSettingValue(globalVal, scopeGlobal, false))
		}
	}

	if !hasValues {
		return ""
	}

	return categoryContent.String() + "\n"
}

// NewSettingsViewer creates a new settings viewer
func NewSettingsViewer(localValues, globalValues map[string]string) *SettingsViewerModel {
	var b strings.Builder

	b.WriteString(TitleStyle.Render("Current Configuration") + "\n\n")

	for _, category := range categoryOrder {
		keys := settingCategories[category]
		if content := renderCategory(category, keys, localValues, globalValues); content != "" {
			b.WriteString(content)
		}
	}

	b.WriteString("\n")
	b.WriteString(HelpStyle.Render("Press q or Esc to return"))

	return &SettingsViewerModel{
		content: b.String(),
	}
}

// Init initializes the viewer
func (m SettingsViewerModel) Init() tea.Cmd {
	return nil
}

// Update handles user input
func (m SettingsViewerModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	if msg, ok := msg.(tea.KeyMsg); ok {
		switch msg.String() {
		case "q", keyEsc, keyCtrlC, keyEnter:
			m.quitting = true

			return m, tea.Quit
		}
	}

	return m, nil
}

// View renders the viewer
func (m SettingsViewerModel) View() string {
	if m.quitting {
		return ""
	}

	// Wrap in a box
	return "\n" + lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(ColorBlue).
		Padding(1, 2).
		Render(m.content) + "\n"
}
