package linear

import (
	"testing"
)

func TestIssueBranchName(t *testing.T) {
	tests := []struct {
		name       string
		issue      Issue
		wantBranch string
	}{
		{
			name: "standard issue",
			issue: Issue{
				Identifier: "ENG-123",
				Title:      "Fix Login Bug",
			},
			wantBranch: "work/ENG-123-fix-login-bug",
		},
		{
			name: "issue with special characters",
			issue: Issue{
				Identifier: "PRODUCT-456",
				Title:      "Implement @new feature!",
			},
			wantBranch: "work/PRODUCT-456-implement-new-feature",
		},
		{
			name: "long title truncated",
			issue: Issue{
				Identifier: "ENG-789",
				Title:      "This is a very long title that should be truncated to forty characters maximum",
			},
			wantBranch: "work/ENG-789-this-is-a-very-long-title-that-should-be",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := tt.issue.BranchName()
			if got != tt.wantBranch {
				t.Errorf("BranchName() = %q, want %q", got, tt.wantBranch)
			}
		})
	}
}

func TestIssueSanitizedTitle(t *testing.T) {
	tests := []struct {
		name      string
		title     string
		wantTitle string
	}{
		{
			name:      "simple title",
			title:     "Fix Login Bug",
			wantTitle: "fix-login-bug",
		},
		{
			name:      "title with special characters",
			title:     "Add @feature #123",
			wantTitle: "add-feature-123",
		},
		{
			name:      "title that's too long",
			title:     "This is a very long title that definitely exceeds the forty character limit",
			wantTitle: "this-is-a-very-long-title-that-definitel",
		},
		{
			name:      "uppercase title",
			title:     "IMPLEMENT NEW FEATURE",
			wantTitle: "implement-new-feature",
		},
		{
			name:      "title with multiple spaces",
			title:     "Fix   multiple   spaces",
			wantTitle: "fix-multiple-spaces",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			issue := Issue{Title: tt.title}
			got := issue.SanitizedTitle()
			if got != tt.wantTitle {
				t.Errorf("SanitizedTitle() = %q, want %q", got, tt.wantTitle)
			}
		})
	}
}

func TestIssueFormatForDisplay(t *testing.T) {
	tests := []struct {
		name   string
		issue  Issue
		expect string
	}{
		{
			name: "issue without labels",
			issue: Issue{
				Identifier: "ENG-123",
				Title:      "Fix Login Bug",
				Labels:     []Label{},
			},
			expect: "ENG-123 | Fix Login Bug",
		},
		{
			name: "issue with labels",
			issue: Issue{
				Identifier: "PRODUCT-456",
				Title:      "Implement Feature",
				Labels: []Label{
					{Name: "bug"},
					{Name: "urgent"},
				},
			},
			expect: "PRODUCT-456 | Implement Feature | [bug] [urgent]",
		},
		{
			name: "issue with single label",
			issue: Issue{
				Identifier: "ENG-789",
				Title:      "Refactor Code",
				Labels: []Label{
					{Name: "refactor"},
				},
			},
			expect: "ENG-789 | Refactor Code | [refactor]",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := tt.issue.FormatForDisplay()
			if got != tt.expect {
				t.Errorf("FormatForDisplay() = %q, want %q", got, tt.expect)
			}
		})
	}
}
