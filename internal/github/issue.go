package github

import (
	"encoding/json"
	"fmt"
	"strconv"
	"strings"

	"github.com/kaeawc/auto-worktree/internal/git"
)

// Issue represents a GitHub issue
type Issue struct {
	Number      int     `json:"number"`
	Title       string  `json:"title"`
	Body        string  `json:"body"`
	State       string  `json:"state"`       // "OPEN" or "CLOSED"
	StateReason string  `json:"stateReason"` // "COMPLETED", "NOT_PLANNED", etc.
	Labels      []Label `json:"labels"`
	URL         string  `json:"url"`
}

// Label represents a GitHub label
type Label struct {
	Name  string `json:"name"`
	Color string `json:"color"`
}

// ListOpenIssues fetches open issues (up to limit)
// Uses: gh issue list --limit <limit> --state open --json number,title,labels,url
func (c *Client) ListOpenIssues(limit int) ([]Issue, error) {
	output, err := c.execGHInRepo("issue", "list",
		"--limit", strconv.Itoa(limit),
		"--state", "open",
		"--json", "number,title,labels,url")
	if err != nil {
		return nil, fmt.Errorf("failed to list issues: %w", err)
	}

	var issues []Issue
	if err := json.Unmarshal(output, &issues); err != nil {
		return nil, fmt.Errorf("failed to parse issues: %w", err)
	}

	return issues, nil
}

// GetIssue fetches a specific issue by number
// Uses: gh issue view <number> --json number,title,body,state,stateReason,labels,url
func (c *Client) GetIssue(number int) (*Issue, error) {
	output, err := c.execGHInRepo("issue", "view", strconv.Itoa(number),
		"--json", "number,title,body,state,stateReason,labels,url")
	if err != nil {
		return nil, fmt.Errorf("failed to get issue #%d: %w", number, err)
	}

	var issue Issue
	if err := json.Unmarshal(output, &issue); err != nil {
		return nil, fmt.Errorf("failed to parse issue: %w", err)
	}

	return &issue, nil
}

// IsIssueMerged checks if an issue is closed and was completed (merged PR)
// Searches for merged PRs that reference the issue
func (c *Client) IsIssueMerged(number int) (bool, error) {
	// First check if issue is closed
	issue, err := c.GetIssue(number)
	if err != nil {
		return false, err
	}

	if issue.State != "CLOSED" {
		return false, nil
	}

	// Check if there are merged PRs that reference this issue
	query := fmt.Sprintf("closes #%d OR fixes #%d OR resolves #%d", number, number, number)
	output, err := c.execGHInRepo("pr", "list",
		"--state", "merged",
		"--search", query,
		"--json", "number",
		"--jq", "length")
	if err != nil {
		// If the search fails, assume not merged
		return false, nil
	}

	// Parse the count
	countStr := strings.TrimSpace(string(output))
	count, err := strconv.Atoi(countStr)
	if err != nil {
		return false, nil
	}

	return count > 0, nil
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

// FormatForDisplay formats issue for display in lists
// Format: #<number> | <title> | [label1] [label2]
func (i *Issue) FormatForDisplay() string {
	var parts []string

	// Add number and title
	parts = append(parts, fmt.Sprintf("#%d | %s", i.Number, i.Title))

	// Add labels if present
	if len(i.Labels) > 0 {
		labelNames := make([]string, len(i.Labels))
		for idx, label := range i.Labels {
			labelNames[idx] = fmt.Sprintf("[%s]", label.Name)
		}
		parts = append(parts, "|", strings.Join(labelNames, " "))
	}

	return strings.Join(parts, " ")
}

// BranchName generates the branch name for this issue
// Format: work/<number>-<sanitized-title>
func (i *Issue) BranchName() string {
	return fmt.Sprintf("work/%d-%s", i.Number, i.SanitizedTitle())
}

// Milestone represents a GitHub milestone
type Milestone struct {
	Number       int    `json:"number"`
	Title        string `json:"title"`
	Description  string `json:"description"`
	State        string `json:"state"` // "OPEN" or "CLOSED"
	OpenIssues   int    `json:"openIssues"`
	ClosedIssues int    `json:"closedIssues"`
	DueOn        string `json:"dueOn"`
	URL          string `json:"url"`
}

// ListOpenMilestones fetches open milestones
// Uses: gh api repos/{owner}/{repo}/milestones --jq '.[] | select(.state == "open")'
func (c *Client) ListOpenMilestones(limit int) ([]Milestone, error) {
	// Use gh api to get milestones
	output, err := c.execGHInRepo("api",
		fmt.Sprintf("repos/%s/%s/milestones", c.Owner, c.Repo),
		"--jq", ".",
	)
	if err != nil {
		return nil, fmt.Errorf("failed to list milestones: %w", err)
	}

	// GitHub API returns milestones with lowercase field names
	var apiMilestones []struct {
		Number       int    `json:"number"`
		Title        string `json:"title"`
		Description  string `json:"description"`
		State        string `json:"state"` // "open" or "closed"
		OpenIssues   int    `json:"open_issues"`
		ClosedIssues int    `json:"closed_issues"`
		DueOn        string `json:"due_on"`
		HTMLURL      string `json:"html_url"`
	}
	if err := json.Unmarshal(output, &apiMilestones); err != nil {
		return nil, fmt.Errorf("failed to parse milestones: %w", err)
	}

	// Convert to our Milestone struct, filtering to open only
	milestones := make([]Milestone, 0, len(apiMilestones))
	for _, m := range apiMilestones {
		if m.State != "open" {
			continue
		}
		milestones = append(milestones, Milestone{
			Number:       m.Number,
			Title:        m.Title,
			Description:  m.Description,
			State:        strings.ToUpper(m.State),
			OpenIssues:   m.OpenIssues,
			ClosedIssues: m.ClosedIssues,
			DueOn:        m.DueOn,
			URL:          m.HTMLURL,
		})
		if limit > 0 && len(milestones) >= limit {
			break
		}
	}

	return milestones, nil
}

// ListOpenIssuesByMilestone fetches open issues for a specific milestone
// Uses: gh issue list --milestone <title> --state open --json number,title,labels,url
func (c *Client) ListOpenIssuesByMilestone(milestoneTitle string, limit int) ([]Issue, error) {
	output, err := c.execGHInRepo("issue", "list",
		"--milestone", milestoneTitle,
		"--limit", strconv.Itoa(limit),
		"--state", "open",
		"--json", "number,title,labels,url")
	if err != nil {
		return nil, fmt.Errorf("failed to list issues for milestone %s: %w", milestoneTitle, err)
	}

	var issues []Issue
	if err := json.Unmarshal(output, &issues); err != nil {
		return nil, fmt.Errorf("failed to parse issues: %w", err)
	}

	return issues, nil
}
