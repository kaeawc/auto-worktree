package jira

import (
	"context"
	"testing"

	"github.com/kaeawc/auto-worktree/internal/providers"
)

// TestProviderListIssues tests ListIssues method
func TestProviderListIssues(t *testing.T) {
	executor := NewMockExecutor()
	executor.SetResponse("issue list", `[
		{
			"key": "PROJ-123",
			"fields": {
				"summary": "Test issue 1",
				"description": "Description 1",
				"status": {"name": "Open"},
				"resolution": {"name": "Unresolved"},
				"assignee": {"displayName": "user1"},
				"creator": {"displayName": "creator1"},
				"created": "2025-01-01T00:00:00Z",
				"updated": "2025-01-02T00:00:00Z",
				"labels": ["bug"],
				"url": "https://jira.example.com/browse/PROJ-123"
			}
		},
		{
			"key": "PROJ-124",
			"fields": {
				"summary": "Test issue 2",
				"description": "Description 2",
				"status": {"name": "In Progress"},
				"resolution": {"name": "Unresolved"},
				"assignee": {"displayName": "user2"},
				"creator": {"displayName": "creator2"},
				"created": "2025-01-01T01:00:00Z",
				"updated": "2025-01-02T01:00:00Z",
				"labels": ["feature"],
				"url": "https://jira.example.com/browse/PROJ-124"
			}
		}
	]`)

	provider, err := NewProviderWithExecutor("https://jira.example.com", "PROJ", executor)
	if err != nil {
		t.Fatalf("failed to create provider: %v", err)
	}

	ctx := context.Background()
	issues, err := provider.ListIssues(ctx, 0)
	if err != nil {
		t.Fatalf("ListIssues failed: %v", err)
	}

	if len(issues) != 2 {
		t.Errorf("expected 2 issues, got %d", len(issues))
	}

	if issues[0].Key != "PROJ-123" {
		t.Errorf("expected first issue key PROJ-123, got %s", issues[0].Key)
	}

	if issues[0].Title != "Test issue 1" {
		t.Errorf("expected title 'Test issue 1', got %s", issues[0].Title)
	}

	if len(issues[0].Labels) != 1 || issues[0].Labels[0] != "bug" {
		t.Errorf("expected labels [bug], got %v", issues[0].Labels)
	}
}

// TestProviderGetIssue tests GetIssue method
func TestProviderGetIssue(t *testing.T) {
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
			"labels": ["bug", "test"],
			"url": "https://jira.example.com/browse/PROJ-123"
		}
	}`)

	provider, err := NewProviderWithExecutor("https://jira.example.com", "PROJ", executor)
	if err != nil {
		t.Fatalf("failed to create provider: %v", err)
	}

	ctx := context.Background()
	issue, err := provider.GetIssue(ctx, "PROJ-123")
	if err != nil {
		t.Fatalf("GetIssue failed: %v", err)
	}

	if issue.Key != "PROJ-123" {
		t.Errorf("expected key PROJ-123, got %s", issue.Key)
	}

	if issue.Title != "Test issue" {
		t.Errorf("expected title 'Test issue', got %s", issue.Title)
	}

	if len(issue.Labels) != 2 {
		t.Errorf("expected 2 labels, got %d", len(issue.Labels))
	}
}

// TestProviderIsIssueClosed tests IsIssueClosed method
func TestProviderIsIssueClosed(t *testing.T) {
	tests := []struct {
		name     string
		status   string
		expected bool
	}{
		{"Done", "Done", true},
		{"Resolved", "Resolved", true},
		{"Closed", "Closed", true},
		{"Open", "Open", false},
		{"In Progress", "In Progress", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			executor := NewMockExecutor()
			executor.SetResponse("issue view", `{
				"key": "PROJ-123",
				"fields": {
					"summary": "Test",
					"description": "Test",
					"status": {"name": "`+tt.status+`"},
					"resolution": {"name": "Unresolved"},
					"assignee": {"displayName": "user"},
					"creator": {"displayName": "creator"},
					"created": "2025-01-01T00:00:00Z",
					"updated": "2025-01-02T00:00:00Z",
					"labels": [],
					"url": "https://jira.example.com/browse/PROJ-123"
				}
			}`)

			provider, err := NewProviderWithExecutor("https://jira.example.com", "PROJ", executor)
			if err != nil {
				t.Fatalf("failed to create provider: %v", err)
			}

			ctx := context.Background()
			isClosed, err := provider.IsIssueClosed(ctx, "PROJ-123")
			if err != nil {
				t.Fatalf("IsIssueClosed failed: %v", err)
			}

			if isClosed != tt.expected {
				t.Errorf("expected %v, got %v", tt.expected, isClosed)
			}
		})
	}
}

// TestProviderPullRequestsNotSupported tests that PR methods return errors
func TestProviderPullRequestsNotSupported(t *testing.T) {
	executor := NewMockExecutor()
	provider, err := NewProviderWithExecutor("https://jira.example.com", "PROJ", executor)
	if err != nil {
		t.Fatalf("failed to create provider: %v", err)
	}

	ctx := context.Background()

	_, err = provider.ListPullRequests(ctx, 0)
	if err == nil {
		t.Errorf("expected error for ListPullRequests, got nil")
	}

	_, err = provider.GetPullRequest(ctx, "PR-1")
	if err == nil {
		t.Errorf("expected error for GetPullRequest, got nil")
	}

	_, err = provider.IsPullRequestMerged(ctx, "PR-1")
	if err == nil {
		t.Errorf("expected error for IsPullRequestMerged, got nil")
	}

	_, err = provider.CreatePullRequest(ctx, "title", "body", "main", "feature")
	if err == nil {
		t.Errorf("expected error for CreatePullRequest, got nil")
	}
}

// TestProviderCreateIssue tests CreateIssue method
func TestProviderCreateIssue(t *testing.T) {
	executor := NewMockExecutor()
	executor.SetResponse("issue create", `{
		"key": "PROJ-125",
		"fields": {
			"summary": "New issue",
			"description": "New description",
			"status": {"name": "Open"},
			"resolution": {"name": "Unresolved"},
			"assignee": {"displayName": "user"},
			"creator": {"displayName": "creator"},
			"created": "2025-01-03T00:00:00Z",
			"updated": "2025-01-03T00:00:00Z",
			"labels": [],
			"url": "https://jira.example.com/browse/PROJ-125"
		}
	}`)

	provider, err := NewProviderWithExecutor("https://jira.example.com", "PROJ", executor)
	if err != nil {
		t.Fatalf("failed to create provider: %v", err)
	}

	ctx := context.Background()
	issue, err := provider.CreateIssue(ctx, "New issue", "New description")
	if err != nil {
		t.Fatalf("CreateIssue failed: %v", err)
	}

	if issue.Key != "PROJ-125" {
		t.Errorf("expected key PROJ-125, got %s", issue.Key)
	}

	if issue.Title != "New issue" {
		t.Errorf("expected title 'New issue', got %s", issue.Title)
	}
}

// TestProviderMetadata tests provider metadata methods
func TestProviderMetadata(t *testing.T) {
	executor := NewMockExecutor()
	provider, err := NewProviderWithExecutor("https://jira.example.com", "PROJ", executor)
	if err != nil {
		t.Fatalf("failed to create provider: %v", err)
	}

	if provider.Name() != "JIRA" {
		t.Errorf("expected name 'JIRA', got %s", provider.Name())
	}

	if provider.ProviderType() != "jira" {
		t.Errorf("expected type 'jira', got %s", provider.ProviderType())
	}

	issue := &providers.Issue{
		Key: "PROJ-123",
	}

	suffix := provider.GetBranchNameSuffix(issue)
	if suffix != "PROJ-123" {
		t.Errorf("expected suffix 'PROJ-123', got %s", suffix)
	}

	sanitized := provider.SanitizeBranchName("Fix bug in authentication")
	if sanitized == "" {
		t.Errorf("expected non-empty sanitized name")
	}
}
