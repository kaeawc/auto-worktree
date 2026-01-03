package jira

import (
	"context"
	"testing"
)

// MockExecutor is a mock implementation of Executor for testing
type MockExecutor struct {
	responses map[string]string
	errors    map[string]error
	calls     []ExecutorCall
}

// ExecutorCall tracks an executor call
type ExecutorCall struct {
	Args []string
}

// NewMockExecutor creates a new mock executor
func NewMockExecutor() *MockExecutor {
	return &MockExecutor{
		responses: make(map[string]string),
		errors:    make(map[string]error),
		calls:     []ExecutorCall{},
	}
}

// Execute executes a command and returns output
func (m *MockExecutor) Execute(_ context.Context, args ...string) (string, error) {
	m.calls = append(m.calls, ExecutorCall{Args: args})

	// Build key from first arg
	key := args[0]
	if len(args) > 1 {
		key = args[0] + " " + args[1]
	}

	if err, ok := m.errors[key]; ok {
		return "", err
	}

	return m.responses[key], nil
}

// SetResponse configures a response for a command
func (m *MockExecutor) SetResponse(key, response string) {
	m.responses[key] = response
}

// SetError configures an error for a command
func (m *MockExecutor) SetError(key string, err error) {
	m.errors[key] = err
}

// TestListOpenIssuesSuccess tests successful issue listing
func TestListOpenIssuesSuccess(t *testing.T) {
	executor := NewMockExecutor()
	executor.SetResponse("issue list", `[
		{
			"key": "PROJ-123",
			"fields": {
				"summary": "Test issue",
				"description": "Test description",
				"status": {"name": "Open"},
				"resolution": {"name": "Unresolved"},
				"assignee": {"displayName": "user@example.com"},
				"creator": {"displayName": "creator@example.com"},
				"created": "2025-01-01T00:00:00Z",
				"updated": "2025-01-02T00:00:00Z",
				"labels": ["bug", "test"],
				"url": "https://jira.example.com/browse/PROJ-123"
			}
		}
	]`)

	client, err := NewClientWithExecutor("https://jira.example.com", "PROJ", executor)
	if err != nil {
		t.Fatalf("failed to create client: %v", err)
	}

	ctx := context.Background()
	issues, err := client.ListOpenIssues(ctx)
	if err != nil {
		t.Fatalf("ListOpenIssues failed: %v", err)
	}

	if len(issues) != 1 {
		t.Errorf("expected 1 issue, got %d", len(issues))
	}

	if issues[0].Key != "PROJ-123" {
		t.Errorf("expected key PROJ-123, got %s", issues[0].Key)
	}
}

// TestGetIssueSuccess tests successful issue retrieval
func TestGetIssueSuccess(t *testing.T) {
	executor := NewMockExecutor()
	executor.SetResponse("issue view", `{
		"key": "PROJ-123",
		"fields": {
			"summary": "Test issue",
			"description": "Test description",
			"status": {"name": "Open"},
			"resolution": {"name": "Unresolved"},
			"assignee": {"displayName": "user@example.com"},
			"creator": {"displayName": "creator@example.com"},
			"created": "2025-01-01T00:00:00Z",
			"updated": "2025-01-02T00:00:00Z",
			"labels": ["bug"],
			"url": "https://jira.example.com/browse/PROJ-123"
		}
	}`)

	client, err := NewClientWithExecutor("https://jira.example.com", "PROJ", executor)
	if err != nil {
		t.Fatalf("failed to create client: %v", err)
	}

	ctx := context.Background()
	issue, err := client.GetIssue(ctx, "PROJ-123")
	if err != nil {
		t.Fatalf("GetIssue failed: %v", err)
	}

	if issue.Key != "PROJ-123" {
		t.Errorf("expected key PROJ-123, got %s", issue.Key)
	}

	if issue.Fields.Summary != "Test issue" {
		t.Errorf("expected summary 'Test issue', got %s", issue.Fields.Summary)
	}
}

// TestGetIssueStatusResolved tests status checking for resolved issues
func TestGetIssueStatusResolved(t *testing.T) {
	executor := NewMockExecutor()
	executor.SetResponse("issue view", `{
		"key": "PROJ-123",
		"fields": {
			"summary": "Test issue",
			"description": "Test description",
			"status": {"name": "Done"},
			"resolution": {"name": "Fixed"},
			"assignee": {"displayName": "user@example.com"},
			"creator": {"displayName": "creator@example.com"},
			"created": "2025-01-01T00:00:00Z",
			"updated": "2025-01-02T00:00:00Z",
			"labels": [],
			"url": "https://jira.example.com/browse/PROJ-123"
		}
	}`)

	client, err := NewClientWithExecutor("https://jira.example.com", "PROJ", executor)
	if err != nil {
		t.Fatalf("failed to create client: %v", err)
	}

	ctx := context.Background()
	isClosed, err := client.GetIssueStatus(ctx, "PROJ-123")
	if err != nil {
		t.Fatalf("GetIssueStatus failed: %v", err)
	}

	if !isClosed {
		t.Errorf("expected issue to be closed, but it's not")
	}
}

// TestIssueClosedStatus tests Issue.IsClosed() method
func TestIssueClosedStatus(t *testing.T) {
	tests := []struct {
		name       string
		status     string
		resolution string
		expected   bool
	}{
		{"Done status", "Done", "Unresolved", true},
		{"Resolved status", "Resolved", "Unresolved", true},
		{"Closed status", "Closed", "Unresolved", true},
		{"Done resolution", "Open", "Done", true},
		{"Fixed resolution", "Open", "Fixed", true},
		{"Open issue", "Open", "Unresolved", false},
		{"In Progress", "In Progress", "Unresolved", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			issue := &Issue{
				Key: "TEST-1",
			}
			issue.Fields.Summary = "Test"
			issue.Fields.Status.Name = tt.status
			issue.Fields.Resolution.Name = tt.resolution
			issue.Fields.Assignee.DisplayName = "user"
			issue.Fields.Creator.DisplayName = "creator"
			issue.Fields.Created = "2025-01-01T00:00:00Z"
			issue.Fields.Updated = "2025-01-02T00:00:00Z"

			result := issue.IsClosed()
			if result != tt.expected {
				t.Errorf("expected %v, got %v", tt.expected, result)
			}
		})
	}
}
