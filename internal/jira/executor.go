package jira

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
)

// Executor handles JIRA CLI command execution
type Executor interface {
	Execute(ctx context.Context, args ...string) (string, error)
}

// CLIExecutor executes jira CLI commands
type CLIExecutor struct{}

// NewCLIExecutor creates a new CLI executor
func NewCLIExecutor() *CLIExecutor {
	return &CLIExecutor{}
}

// Execute runs a jira CLI command and returns its output
func (e *CLIExecutor) Execute(ctx context.Context, args ...string) (string, error) {
	cmd := exec.CommandContext(ctx, "jira", args...)
	output, err := cmd.Output()
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			stderr := string(exitErr.Stderr)
			return "", fmt.Errorf("jira command failed: %s", stderr)
		}
		return "", fmt.Errorf("jira command failed: %w", err)
	}
	return strings.TrimSpace(string(output)), nil
}
