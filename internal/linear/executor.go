package linear

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
)

// Executor defines the interface for executing linear CLI commands
type Executor interface {
	// Execute runs a linear command and returns the output
	Execute(args ...string) (string, error)
	// ExecuteInDir runs a linear command in a specific directory
	ExecuteInDir(dir string, args ...string) (string, error)
}

// RealExecutor executes actual linear commands via exec.Command
type RealExecutor struct{}

// NewExecutor creates a new real Linear executor for production use
func NewExecutor() Executor {
	return &RealExecutor{}
}

// Execute runs a linear command and returns the output
func (e *RealExecutor) Execute(args ...string) (string, error) {
	cmd := exec.CommandContext(context.Background(), "linear", args...)
	output, err := cmd.CombinedOutput()

	if err != nil {
		return "", fmt.Errorf("linear %s failed: %w", strings.Join(args, " "), err)
	}

	return strings.TrimSpace(string(output)), nil
}

// ExecuteInDir runs a linear command in a specific directory
func (e *RealExecutor) ExecuteInDir(dir string, args ...string) (string, error) {
	cmd := exec.CommandContext(context.Background(), "linear", args...)
	cmd.Dir = dir
	output, err := cmd.CombinedOutput()

	if err != nil {
		return "", fmt.Errorf("linear %s failed in %s: %w", strings.Join(args, " "), dir, err)
	}

	return strings.TrimSpace(string(output)), nil
}

// FakeExecutor is a fake implementation for testing
type FakeExecutor struct {
	// Commands records all executed commands for verification
	Commands [][]string
	// Responses maps command strings to their responses
	Responses map[string]string
	// Errors maps command strings to errors
	Errors map[string]error
	// DefaultResponse is returned when no specific response is configured
	DefaultResponse string
}

// NewFakeExecutor creates a new fake Linear executor for testing
func NewFakeExecutor() *FakeExecutor {
	return &FakeExecutor{
		Commands:  [][]string{},
		Responses: make(map[string]string),
		Errors:    make(map[string]error),
	}
}

// Execute records the command and returns a configured response
func (e *FakeExecutor) Execute(args ...string) (string, error) {
	e.Commands = append(e.Commands, args)
	key := strings.Join(args, " ")

	if err, ok := e.Errors[key]; ok {
		return "", err
	}

	if resp, ok := e.Responses[key]; ok {
		return resp, nil
	}

	return e.DefaultResponse, nil
}

// ExecuteInDir records the command and returns a configured response
func (e *FakeExecutor) ExecuteInDir(dir string, args ...string) (string, error) {
	// Record with directory context
	cmdWithDir := append([]string{"[in:" + dir + "]"}, args...)
	e.Commands = append(e.Commands, cmdWithDir)

	key := strings.Join(args, " ")

	if err, ok := e.Errors[key]; ok {
		return "", err
	}

	if resp, ok := e.Responses[key]; ok {
		return resp, nil
	}

	return e.DefaultResponse, nil
}

// SetResponse configures a response for a specific command
func (e *FakeExecutor) SetResponse(command string, response string) {
	e.Responses[command] = response
}

// SetError configures an error for a specific command
func (e *FakeExecutor) SetError(command string, err error) {
	e.Errors[command] = err
}

// GetCommandCount returns the number of commands executed
func (e *FakeExecutor) GetCommandCount() int {
	return len(e.Commands)
}

// GetLastCommand returns the last executed command, or nil if none
func (e *FakeExecutor) GetLastCommand() []string {
	if len(e.Commands) == 0 {
		return nil
	}

	return e.Commands[len(e.Commands)-1]
}

// Reset clears all recorded commands and responses
func (e *FakeExecutor) Reset() {
	e.Commands = [][]string{}
	e.Responses = make(map[string]string)
	e.Errors = make(map[string]error)
	e.DefaultResponse = ""
}
