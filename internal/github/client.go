package github

import (
	"errors"
	"fmt"
	"os/exec"
)

var (
	// ErrGHNotInstalled is returned when gh CLI is not installed
	ErrGHNotInstalled = errors.New("gh CLI not installed")
	// ErrGHNotAuthenticated is returned when gh CLI is not authenticated
	ErrGHNotAuthenticated = errors.New("gh CLI not authenticated")
)

// Client provides GitHub operations via gh CLI
type Client struct {
	// Owner is the repository owner (org or user)
	Owner string
	// Repo is the repository name
	Repo string
}

// NewClient creates a GitHub client, auto-detecting repo from git remote
// Returns error if gh CLI not installed or not authenticated
func NewClient(gitRoot string) (*Client, error) {
	// Check if gh CLI is installed
	if !IsInstalled() {
		return nil, ErrGHNotInstalled
	}

	// Check if gh is authenticated
	if err := IsAuthenticated(); err != nil {
		return nil, err
	}

	// Auto-detect repository
	info, err := DetectRepository(gitRoot)
	if err != nil {
		return nil, err
	}

	return &Client{
		Owner: info.Owner,
		Repo:  info.Name,
	}, nil
}

// NewClientWithRepo creates a client with explicit owner/repo
func NewClientWithRepo(owner, repo string) (*Client, error) {
	// Check if gh CLI is installed
	if !IsInstalled() {
		return nil, ErrGHNotInstalled
	}

	// Check if gh is authenticated
	if err := IsAuthenticated(); err != nil {
		return nil, err
	}

	return &Client{
		Owner: owner,
		Repo:  repo,
	}, nil
}

// IsInstalled checks if gh CLI is installed
func IsInstalled() bool {
	cmd := exec.Command("gh", "--version")
	err := cmd.Run()
	return err == nil
}

// IsAuthenticated checks if gh CLI is authenticated
func IsAuthenticated() error {
	cmd := exec.Command("gh", "auth", "status")
	if err := cmd.Run(); err != nil {
		return ErrGHNotAuthenticated
	}
	return nil
}

// execGH executes a gh CLI command and returns output
func (c *Client) execGH(args ...string) ([]byte, error) {
	cmd := exec.Command("gh", args...)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("gh command failed: %w\nOutput: %s", err, string(output))
	}
	return output, nil
}

// execGHInRepo executes a gh CLI command with repo context
func (c *Client) execGHInRepo(args ...string) ([]byte, error) {
	// Prepend repo flag to args
	fullArgs := append([]string{"-R", fmt.Sprintf("%s/%s", c.Owner, c.Repo)}, args...)
	return c.execGH(fullArgs...)
}
