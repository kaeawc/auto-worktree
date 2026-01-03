// Package linear provides a client for interacting with the Linear CLI tool.
package linear

import (
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"

	"github.com/kaeawc/auto-worktree/internal/git"
)

var (
	// ErrLinearNotInstalled is returned when linear CLI is not installed
	ErrLinearNotInstalled = errors.New("linear CLI not installed")
	// ErrLinearNotAuthenticated is returned when linear CLI is not authenticated
	ErrLinearNotAuthenticated = errors.New("linear CLI not authenticated")
	// ErrNoTeamConfigured is returned when no Linear team is configured
	ErrNoTeamConfigured = errors.New("no Linear team configured")
)

// Client provides Linear operations via linear CLI
type Client struct {
	// Team is the Linear team key (e.g., "ENG", "PRODUCT")
	Team string
	// executor handles linear CLI command execution
	executor Executor
}

// NewClient creates a Linear client with team from git config
// Returns error if linear CLI not installed, not authenticated, or no team configured
func NewClient(gitRoot string, config *git.Config) (*Client, error) {
	executor := NewExecutor()
	return NewClientWithExecutor(gitRoot, config, executor)
}

// NewClientWithExecutor creates a Linear client with custom executor (for testing)
func NewClientWithExecutor(_ string, config *git.Config, executor Executor) (*Client, error) {
	// Check if linear CLI is installed
	if !IsInstalled(executor) {
		return nil, ErrLinearNotInstalled
	}

	// Check authentication
	if err := IsAuthenticated(executor); err != nil {
		return nil, err
	}

	// Get team from config
	team := config.GetWithDefault(git.ConfigLinearTeam, "", git.ConfigScopeAuto)
	if team == "" {
		return nil, ErrNoTeamConfigured
	}

	return &Client{
		Team:     team,
		executor: executor,
	}, nil
}

// IsInstalled checks if linear CLI is installed
func IsInstalled(executor Executor) bool {
	_, err := executor.Execute("--version")
	return err == nil
}

// IsAuthenticated checks if linear CLI is authenticated
func IsAuthenticated(executor Executor) error {
	// Try to fetch teams - this will fail if not authenticated
	_, err := executor.Execute("team", "list")
	if err != nil {
		if strings.Contains(err.Error(), "api_key is not set") ||
			strings.Contains(err.Error(), "not authenticated") {
			return ErrLinearNotAuthenticated
		}

		return fmt.Errorf("failed to verify authentication: %w", err)
	}

	return nil
}

// execLinear executes a linear CLI command and returns raw output bytes
func (c *Client) execLinear(args ...string) ([]byte, error) {
	output, err := c.executor.Execute(args...)

	if err != nil {
		return nil, err
	}

	return []byte(output), nil
}

// ListOpenIssues fetches open issues for the team (up to limit)
// Uses: linear issue list --team <team> --limit <limit> --state unstarted,started
// Note: linear issue list does NOT support --json, so we parse text output then fetch JSON for each
func (c *Client) ListOpenIssues(limit int) ([]Issue, error) {
	// Fetch issues as text (no JSON support)
	output, err := c.execLinear("issue", "list",
		"--team", c.Team,
		"--limit", strconv.Itoa(limit),
		"--state", "unstarted",
		"--state", "started")
	if err != nil {
		return nil, fmt.Errorf("failed to list issues: %w", err)
	}

	// Parse text output to extract issue identifiers
	identifiers := parseIssueListOutput(string(output))

	// Fetch full details for each issue using JSON
	issues := make([]Issue, 0, len(identifiers))

	for _, id := range identifiers {
		issue, err := c.GetIssue(id)
		if err != nil {
			// Skip issues we can't fetch
			continue
		}

		issues = append(issues, *issue)
	}

	return issues, nil
}

// GetIssue fetches a specific issue by identifier (e.g., "ENG-123")
// Uses: linear issue view <identifier> --json
func (c *Client) GetIssue(identifier string) (*Issue, error) {
	output, err := c.execLinear("issue", "view", identifier, "--json")
	if err != nil {
		if strings.Contains(err.Error(), "not found") {
			return nil, fmt.Errorf("issue %s not found", identifier)
		}

		return nil, fmt.Errorf("failed to get issue %s: %w", identifier, err)
	}

	var issue Issue
	if err := json.Unmarshal(output, &issue); err != nil {
		return nil, fmt.Errorf("failed to parse issue: %w", err)
	}

	return &issue, nil
}

// parseIssueListOutput parses text output from 'linear issue list'
// Extracts issue identifiers (e.g., "ENG-123")
// Linear CLI outputs in format: "  ENG-123  Issue title here"
func parseIssueListOutput(output string) []string {
	var identifiers []string
	lines := strings.Split(output, "\n")

	for _, line := range lines {
		// Look for lines that start with whitespace followed by TEAM-NUMBER pattern
		trimmed := strings.TrimLeft(line, " \t")
		if trimmed == "" {
			continue
		}

		// Extract the first word (should be the identifier like "ENG-123")
		parts := strings.Fields(trimmed)
		if len(parts) > 0 {
			id := parts[0]
			// Validate it matches the pattern TEAM-NUMBER
			if isValidLinearIdentifier(id) {
				identifiers = append(identifiers, id)
			}
		}
	}

	return identifiers
}

// isValidLinearIdentifier checks if a string matches the Linear identifier pattern (e.g., "ENG-123")
func isValidLinearIdentifier(s string) bool {
	parts := strings.Split(s, "-")
	if len(parts) != 2 {
		return false
	}

	// First part should be letters only
	if len(parts[0]) == 0 {
		return false
	}

	for _, ch := range parts[0] {
		if ch < 'A' || ch > 'Z' {
			return false
		}
	}

	// Second part should be digits only
	if len(parts[1]) == 0 {
		return false
	}

	for _, ch := range parts[1] {
		if ch < '0' || ch > '9' {
			return false
		}
	}

	return true
}
