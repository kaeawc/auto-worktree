package ui

import (
	"github.com/charmbracelet/bubbles/list"
	tea "github.com/charmbracelet/bubbletea"
)

// SettingsAction represents a settings category that can be configured
type SettingsAction int

const (
	SettingsActionNone SettingsAction = iota
	SettingsActionIssueProvider
	SettingsActionAITool
	SettingsActionGitHubSettings
	SettingsActionGitLabSettings
	SettingsActionJiraSettings
	SettingsActionLinearSettings
	SettingsActionAutoSelect
	SettingsActionBack
)

// SettingsItem represents an item in the settings menu
type SettingsItem struct {
	title       string
	description string
	action      SettingsAction
}

func (i SettingsItem) Title() string       { return i.title }
func (i SettingsItem) Description() string { return i.description }
func (i SettingsItem) FilterValue() string { return i.title }

// SettingsMenuModel represents the settings/configuration menu
type SettingsMenuModel struct {
	list     list.Model
	choice   SettingsAction
	quitting bool
}

// NewSettingsMenuModel creates a new settings menu model
func NewSettingsMenuModel() *SettingsMenuModel {
	items := []list.Item{
		SettingsItem{
			title:       "Issue Provider",
			description: "Select GitHub, GitLab, JIRA, or Linear",
			action:      SettingsActionIssueProvider,
		},
		SettingsItem{
			title:       "AI Tool",
			description: "Configure Claude Code, Codex, Gemini, or skip",
			action:      SettingsActionAITool,
		},
		SettingsItem{
			title:       "GitHub Settings",
			description: "Configure GitHub authentication and repository",
			action:      SettingsActionGitHubSettings,
		},
		SettingsItem{
			title:       "GitLab Settings",
			description: "Configure GitLab server and project",
			action:      SettingsActionGitLabSettings,
		},
		SettingsItem{
			title:       "JIRA Settings",
			description: "Configure JIRA server and project key",
			action:      SettingsActionJiraSettings,
		},
		SettingsItem{
			title:       "Linear Settings",
			description: "Configure Linear team settings",
			action:      SettingsActionLinearSettings,
		},
		SettingsItem{
			title:       "Auto-Select Options",
			description: "Enable/disable automatic issue and PR selection",
			action:      SettingsActionAutoSelect,
		},
		SettingsItem{
			title:       "Back to Main Menu",
			description: "Return to the main menu",
			action:      SettingsActionBack,
		},
	}

	const defaultWidth = 80
	const defaultHeight = 20

	delegate := list.NewDefaultDelegate()
	delegate.Styles.SelectedTitle = SelectedItemStyle
	delegate.Styles.SelectedDesc = HighlightStyle

	l := list.New(items, delegate, defaultWidth, defaultHeight)
	l.Title = "Settings"
	l.Styles.Title = TitleStyle
	l.SetShowStatusBar(false)

	return &SettingsMenuModel{
		list:   l,
		choice: SettingsActionNone,
	}
}

func (m SettingsMenuModel) Init() tea.Cmd {
	return nil
}

func (m SettingsMenuModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.list.SetWidth(msg.Width)
		m.list.SetHeight(msg.Height - 2)
		return m, nil

	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "q", "esc":
			m.quitting = true
			m.choice = SettingsActionBack
			return m, tea.Quit

		case "enter":
			if selectedItem, ok := m.list.SelectedItem().(SettingsItem); ok {
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

func (m SettingsMenuModel) View() string {
	if m.quitting {
		return ""
	}
	return "\n" + m.list.View()
}

// GetChoice returns the selected settings action
func (m SettingsMenuModel) GetChoice() SettingsAction {
	return m.choice
}
