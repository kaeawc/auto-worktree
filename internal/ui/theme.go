package ui

import (
	"time"

	"github.com/charmbracelet/lipgloss"
)

// Color scheme matching the gum-based UI from aw.sh
// Uses ANSI color codes 1-6
const (
	ColorRed     = lipgloss.Color("1") // Errors, stale worktrees (>4 days)
	ColorGreen   = lipgloss.Color("2") // Success, recent worktrees (<1 day)
	ColorYellow  = lipgloss.Color("3") // Warnings, worktrees 1-4 days old
	ColorBlue    = lipgloss.Color("4") // Info boxes/headers
	ColorMagenta = lipgloss.Color("5") // Merged indicators
	ColorCyan    = lipgloss.Color("6") // Highlights/prompts
)

// Semantic color names for different contexts
var (
	ErrorStyle     = lipgloss.NewStyle().Foreground(ColorRed)
	SuccessStyle   = lipgloss.NewStyle().Foreground(ColorGreen)
	WarningStyle   = lipgloss.NewStyle().Foreground(ColorYellow)
	InfoStyle      = lipgloss.NewStyle().Foreground(ColorBlue)
	MergedStyle    = lipgloss.NewStyle().Foreground(ColorMagenta)
	HighlightStyle = lipgloss.NewStyle().Foreground(ColorCyan)

	// Container styles
	BorderStyle = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(ColorBlue).
			Padding(0, 1)

	TitleStyle = lipgloss.NewStyle().
			Foreground(ColorCyan).
			Bold(true).
			Padding(0, 1)

	// List item styles
	SelectedItemStyle = lipgloss.NewStyle().
				Foreground(ColorCyan).
				Bold(true)

	UnselectedItemStyle = lipgloss.NewStyle()

	// Help text style
	HelpStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("8")).
			Italic(true)
)

// GetWorktreeAgeColor returns the appropriate color based on worktree age
// Matches the shell script logic:
// - Red: >4 days (stale)
// - Yellow: 1-4 days
// - Green: <1 day (recent)
func GetWorktreeAgeColor(age time.Duration) lipgloss.Color {
	days := age.Hours() / 24
	switch {
	case days > 4:
		return ColorRed
	case days >= 1:
		return ColorYellow
	default:
		return ColorGreen
	}
}

// GetWorktreeAgeStyle returns a lipgloss style for the given age
func GetWorktreeAgeStyle(age time.Duration) lipgloss.Style {
	return lipgloss.NewStyle().Foreground(GetWorktreeAgeColor(age))
}
