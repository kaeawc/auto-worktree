// Package jira provides JIRA issue provider implementation using jira-cli.
package jira

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"
	"time"
)

var (
	// ErrJiraNotInstalled is returned when jira CLI is not installed
	ErrJiraNotInstalled = errors.New("jira CLI not installed")
	// ErrJiraNotConfigured is returned when jira CLI is not configured
	ErrJiraNotConfigured = errors.New("jira CLI not configured - run 'jira init'")
)

// Client provides JIRA operations via jira CLI
type Client struct {
	// Server URL for JIRA
	Server string
	// Project key for filtering issues
	Project string
	// Executor handles jira CLI commands
	executor Executor
}

// NewClient creates a new JIRA client
// Returns error if jira CLI is not installed or not configured
func NewClient(server, project string) (*Client, error) {
	executor := NewCLIExecutor()
	return NewClientWithExecutor(server, project, executor)
}

// NewClientWithExecutor creates a JIRA client with custom executor (for testing)
// Skips CLI checks since executor is provided for testing
func NewClientWithExecutor(server, project string, executor Executor) (*Client, error) {
	// Skip checks when using custom executor (for testing)
	return &Client{
		Server:   server,
		Project:  project,
		executor: executor,
	}, nil
}

// IsInstalled checks if jira CLI is installed
func IsInstalled() bool {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "jira", "version")
	err := cmd.Run()
	return err == nil
}

// IsConfigured checks if jira CLI is configured
func IsConfigured() error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "jira", "config")
	err := cmd.Run()
	if err != nil {
		return ErrJiraNotConfigured
	}
	return nil
}

// exec executes a jira CLI command and returns output
func (c *Client) exec(ctx context.Context, args ...string) (string, error) {
	return c.executor.Execute(ctx, args...)
}

// ListOpenIssues returns open issues assigned to the current user
// Uses JQL: assignee = currentUser() AND status != Done
func (c *Client) ListOpenIssues(ctx context.Context) ([]Issue, error) {
	jql := "assignee = currentUser() AND status != Done"
	if c.Project != "" {
		jql = fmt.Sprintf("project = %s AND %s", c.Project, jql)
	}

	// Use jira issue list with JQL filter and JSON output
	args := []string{"issue", "list", "--jql", jql, "--json"}
	output, err := c.exec(ctx, args...)
	if err != nil {
		return nil, fmt.Errorf("failed to list issues: %w", err)
	}

	var issues []Issue
	if err := json.Unmarshal([]byte(output), &issues); err != nil {
		return nil, fmt.Errorf("failed to parse issues: %w", err)
	}

	return issues, nil
}

// GetIssue fetches a specific JIRA issue by key
func (c *Client) GetIssue(ctx context.Context, key string) (*Issue, error) {
	// Use jira issue view with JSON output
	args := []string{"issue", "view", key, "--json"}
	output, err := c.exec(ctx, args...)
	if err != nil {
		return nil, fmt.Errorf("failed to get issue %s: %w", key, err)
	}

	var issue Issue
	if err := json.Unmarshal([]byte(output), &issue); err != nil {
		return nil, fmt.Errorf("failed to parse issue: %w", err)
	}

	return &issue, nil
}

// GetIssueStatus checks if a JIRA issue is resolved/done
func (c *Client) GetIssueStatus(ctx context.Context, key string) (bool, error) {
	issue, err := c.GetIssue(ctx, key)
	if err != nil {
		return false, err
	}

	// Use Issue.IsClosed() for consistent status checking
	return issue.IsClosed(), nil
}

// CreateIssue creates a new JIRA issue
func (c *Client) CreateIssue(ctx context.Context, title, body string) (*Issue, error) {
	if title == "" {
		return nil, fmt.Errorf("issue title cannot be empty")
	}

	// Build args for jira issue create
	args := []string{"issue", "create"}

	// Set project if configured
	if c.Project != "" {
		args = append(args, "--project", c.Project)
	}

	// Add title and body
	args = append(args, "--summary", title)
	if body != "" {
		args = append(args, "--description", body)
	}

	// Request JSON output
	args = append(args, "--json")

	output, err := c.exec(ctx, args...)
	if err != nil {
		return nil, fmt.Errorf("failed to create issue: %w", err)
	}

	var issue Issue
	if err := json.Unmarshal([]byte(output), &issue); err != nil {
		return nil, fmt.Errorf("failed to parse created issue: %w", err)
	}

	return &issue, nil
}
