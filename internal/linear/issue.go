package linear

import (
	"fmt"
	"strings"

	"github.com/kaeawc/auto-worktree/internal/git"
)

// Issue represents a Linear issue
type Issue struct {
	// Identifier is the team-prefixed ID (e.g., "ENG-123")
	Identifier string `json:"identifier"`
	// ID is the internal UUID (not used for branch names)
	ID string `json:"id"`
	// Number is the numeric part only (e.g., 123)
	Number int `json:"number"`
	// Title is the issue title
	Title string `json:"title"`
	// Description is the issue body/description
	Description string `json:"description"`
	// State contains state information
	State struct {
		Name string `json:"name"`
		Type string `json:"type"`
	} `json:"state"`
	// Team prefix (e.g., "ENG")
	Team struct {
		Key string `json:"key"`
	} `json:"team"`
	// Labels attached to the issue
	Labels []Label `json:"labels"`
	// URL to view issue in Linear
	URL string `json:"url"`
}

// Label represents a Linear label
type Label struct {
	Name  string `json:"name"`
	Color string `json:"color"`
}

// SanitizedTitle returns sanitized title suitable for branch names (max 40 chars)
func (i *Issue) SanitizedTitle() string {
	title := i.Title

	// Lowercase
	title = strings.ToLower(title)

	// Truncate to 40 characters
	if len(title) > 40 {
		title = title[:40]
	}

	// Use git.SanitizeBranchName for consistent sanitization
	return git.SanitizeBranchName(title)
}

// BranchName generates the branch name for this issue
// Format: work/<identifier>-<sanitized-title>
// Example: work/ENG-456-fix-login-bug
func (i *Issue) BranchName() string {
	return fmt.Sprintf("work/%s-%s", i.Identifier, i.SanitizedTitle())
}

// FormatForDisplay formats issue for display in lists
// Format: <identifier> | <title> | [label1] [label2]
func (i *Issue) FormatForDisplay() string {
	var parts []string
	parts = append(parts, fmt.Sprintf("%s | %s", i.Identifier, i.Title))

	if len(i.Labels) > 0 {
		labelNames := make([]string, len(i.Labels))
		for idx, label := range i.Labels {
			labelNames[idx] = fmt.Sprintf("[%s]", label.Name)
		}

		parts = append(parts, "|", strings.Join(labelNames, " "))
	}

	return strings.Join(parts, " ")
}
