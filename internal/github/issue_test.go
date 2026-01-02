package github

import (
	"testing"
)

func TestIssueSanitizedTitle(t *testing.T) {
	tests := []struct {
		name  string
		title string
		want  string
	}{
		{
			name:  "Simple title",
			title: "Fix bug in authentication",
			want:  "fix-bug-in-authentication",
		},
		{
			name:  "Title with special characters",
			title: "Fix: Critical Bug in Auth!!",
			want:  "fix-critical-bug-in-auth",
		},
		{
			name:  "Long title (over 40 chars)",
			title: "This is a very long title that exceeds forty characters and should be truncated",
			want:  "this-is-a-very-long-title-that-exceeds-f",
		},
		{
			name:  "Title with numbers",
			title: "Add feature #123",
			want:  "add-feature-123",
		},
		{
			name:  "Title with multiple spaces",
			title: "Fix   multiple   spaces",
			want:  "fix-multiple-spaces",
		},
		{
			name:  "Title with leading/trailing spaces",
			title: "  trim spaces  ",
			want:  "trim-spaces",
		},
		{
			name:  "Title with underscores",
			title: "fix_underscore_naming",
			want:  "fix-underscore-naming",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			issue := &Issue{Title: tt.title}
			got := issue.SanitizedTitle()

			if got != tt.want {
				t.Errorf("SanitizedTitle() = %v, want %v", got, tt.want)
			}

			// Verify it's not longer than 40 characters
			if len(got) > 40 {
				t.Errorf("SanitizedTitle() length = %d, want <= 40", len(got))
			}
		})
	}
}

func TestIssueBranchName(t *testing.T) {
	tests := []struct {
		name   string
		number int
		title  string
		want   string
	}{
		{
			name:   "Simple issue",
			number: 123,
			title:  "Fix login bug",
			want:   "work/123-fix-login-bug",
		},
		{
			name:   "Issue with special characters",
			number: 456,
			title:  "Add: New Feature!",
			want:   "work/456-add-new-feature",
		},
		{
			name:   "Long title",
			number: 789,
			title:  "This is a very long issue title that should be truncated properly",
			want:   "work/789-this-is-a-very-long-issue-title-that-sho",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			issue := &Issue{
				Number: tt.number,
				Title:  tt.title,
			}
			got := issue.BranchName()

			if got != tt.want {
				t.Errorf("BranchName() = %v, want %v", got, tt.want)
			}

			// Verify format is work/<number>-<sanitized>
			if len(got) < 6 || got[:5] != "work/" {
				t.Errorf("BranchName() should start with 'work/', got %v", got)
			}
		})
	}
}

func TestIssueFormatForDisplay(t *testing.T) {
	tests := []struct {
		name   string
		issue  Issue
		want   string
	}{
		{
			name: "Issue without labels",
			issue: Issue{
				Number: 123,
				Title:  "Fix bug",
			},
			want: "#123 | Fix bug",
		},
		{
			name: "Issue with single label",
			issue: Issue{
				Number: 456,
				Title:  "Add feature",
				Labels: []Label{
					{Name: "enhancement"},
				},
			},
			want: "#456 | Add feature | [enhancement]",
		},
		{
			name: "Issue with multiple labels",
			issue: Issue{
				Number: 789,
				Title:  "Critical bug",
				Labels: []Label{
					{Name: "bug"},
					{Name: "critical"},
					{Name: "security"},
				},
			},
			want: "#789 | Critical bug | [bug] [critical] [security]",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := tt.issue.FormatForDisplay()

			if got != tt.want {
				t.Errorf("FormatForDisplay() = %v, want %v", got, tt.want)
			}
		})
	}
}

// Integration tests for GitHub API operations
// These tests require gh CLI to be installed and authenticated

func TestListOpenIssues(t *testing.T) {
	if !IsInstalled() {
		t.Skip("gh CLI not installed")
	}

	if IsAuthenticated() != nil {
		t.Skip("gh CLI not authenticated")
	}

	// Use the GitHub CLI repository as a test case (it should always have issues)
	client, err := NewClientWithRepo("cli", "cli")
	if err != nil {
		t.Fatalf("NewClientWithRepo() error = %v", err)
	}

	issues, err := client.ListOpenIssues(10)
	if err != nil {
		t.Fatalf("ListOpenIssues() error = %v", err)
	}

	// Just verify we got some structure back
	// We can't assert specific issues since they change over time
	t.Logf("Retrieved %d issues", len(issues))

	for _, issue := range issues {
		// Verify basic structure
		if issue.Number == 0 {
			t.Error("Issue number should not be 0")
		}
		if issue.Title == "" {
			t.Error("Issue title should not be empty")
		}
		if issue.URL == "" {
			t.Error("Issue URL should not be empty")
		}
	}
}

func TestGetIssue(t *testing.T) {
	if !IsInstalled() {
		t.Skip("gh CLI not installed")
	}

	if IsAuthenticated() != nil {
		t.Skip("gh CLI not authenticated")
	}

	// Use the GitHub CLI repository
	client, err := NewClientWithRepo("cli", "cli")
	if err != nil {
		t.Fatalf("NewClientWithRepo() error = %v", err)
	}

	// Get issue #1 (first issue, should always exist)
	issue, err := client.GetIssue(1)
	if err != nil {
		t.Fatalf("GetIssue() error = %v", err)
	}

	// Verify structure
	if issue.Number != 1 {
		t.Errorf("GetIssue() Number = %d, want 1", issue.Number)
	}

	if issue.Title == "" {
		t.Error("GetIssue() Title should not be empty")
	}

	if issue.URL == "" {
		t.Error("GetIssue() URL should not be empty")
	}

	if issue.State == "" {
		t.Error("GetIssue() State should not be empty")
	}

	t.Logf("Issue #1: %s (State: %s)", issue.Title, issue.State)
}

func TestIsIssueMerged(t *testing.T) {
	if !IsInstalled() {
		t.Skip("gh CLI not installed")
	}

	if IsAuthenticated() != nil {
		t.Skip("gh CLI not authenticated")
	}

	// Use the GitHub CLI repository
	client, err := NewClientWithRepo("cli", "cli")
	if err != nil {
		t.Fatalf("NewClientWithRepo() error = %v", err)
	}

	// Test with issue #1 (should be closed and likely merged)
	merged, err := client.IsIssueMerged(1)
	if err != nil {
		t.Fatalf("IsIssueMerged() error = %v", err)
	}

	t.Logf("Issue #1 merged status: %v", merged)

	// We can't assert the exact value since it depends on the repository state
	// But we can verify the function runs without error
}
