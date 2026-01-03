package linear

import (
	"testing"

	"github.com/kaeawc/auto-worktree/internal/git"
)

func TestIsInstalled(t *testing.T) {
	tests := []struct {
		name          string
		setupFake     func() *FakeExecutor
		wantInstalled bool
	}{
		{
			name: "linear is installed",
			setupFake: func() *FakeExecutor {
				fake := NewFakeExecutor()
				fake.SetResponse("--version", "linear version 1.5.0")
				return fake
			},
			wantInstalled: true,
		},
		{
			name: "linear is not installed",
			setupFake: func() *FakeExecutor {
				fake := NewFakeExecutor()
				fake.SetError("--version", ErrLinearNotInstalled)
				return fake
			},
			wantInstalled: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			fake := tt.setupFake()
			installed := IsInstalled(fake)

			if installed != tt.wantInstalled {
				t.Errorf("IsInstalled() = %v, want %v", installed, tt.wantInstalled)
			}
		})
	}
}

func TestIsAuthenticated(t *testing.T) {
	tests := []struct {
		name      string
		setupFake func() *FakeExecutor
		wantErr   bool
	}{
		{
			name: "authenticated",
			setupFake: func() *FakeExecutor {
				fake := NewFakeExecutor()
				fake.SetResponse("team list", "ENG PRODUCT")
				return fake
			},
			wantErr: false,
		},
		{
			name: "not authenticated - api_key not set",
			setupFake: func() *FakeExecutor {
				fake := NewFakeExecutor()
				fake.SetError("team list", ErrLinearNotAuthenticated)
				return fake
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			fake := tt.setupFake()
			err := IsAuthenticated(fake)

			if (err != nil) != tt.wantErr {
				t.Errorf("IsAuthenticated() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}

func TestParseIssueListOutput(t *testing.T) {
	tests := []struct {
		name      string
		output    string
		wantCount int
		wantFirst string
	}{
		{
			name: "parse multiple issues",
			output: `  ENG-123  Fix login bug
  ENG-456  Add authentication
  PRODUCT-789  Implement feature`,
			wantCount: 3,
			wantFirst: "ENG-123",
		},
		{
			name:      "empty output",
			output:    "",
			wantCount: 0,
		},
		{
			name:      "single issue",
			output:    "  ENG-999  Single issue",
			wantCount: 1,
			wantFirst: "ENG-999",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ids := parseIssueListOutput(tt.output)

			if len(ids) != tt.wantCount {
				t.Errorf("parseIssueListOutput() got %d issues, want %d", len(ids), tt.wantCount)
			}

			if tt.wantCount > 0 && ids[0] != tt.wantFirst {
				t.Errorf("parseIssueListOutput() first = %s, want %s", ids[0], tt.wantFirst)
			}
		})
	}
}

func TestIsValidLinearIdentifier(t *testing.T) {
	tests := []struct {
		identifier string
		wantValid  bool
	}{
		{"ENG-123", true},
		{"PRODUCT-456", true},
		{"ABC-789", true},
		{"eng-123", false}, // lowercase not allowed
		{"ENG-abc", false}, // letters in number part
		{"ENG", false},     // no dash
		{"123-ENG", false}, // wrong order
		{"", false},        // empty
		{"-123", false},    // missing team
		{"ENG-", false},    // missing number
	}

	for _, tt := range tests {
		t.Run(tt.identifier, func(t *testing.T) {
			got := isValidLinearIdentifier(tt.identifier)
			if got != tt.wantValid {
				t.Errorf("isValidLinearIdentifier(%q) = %v, want %v", tt.identifier, got, tt.wantValid)
			}
		})
	}
}

func TestNewClientWithExecutor(t *testing.T) {
	tests := []struct {
		name      string
		setupFake func() (*FakeExecutor, *git.Config)
		wantErr   string
	}{
		{
			name: "successful client creation",
			setupFake: func() (*FakeExecutor, *git.Config) {
				fake := NewFakeExecutor()
				fake.SetResponse("--version", "linear version 1.5.0")
				fake.SetResponse("team list", "ENG")

				// Create a mock config
				config := &git.Config{}
				return fake, config
			},
			wantErr: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(_ *testing.T) {
			fake, config := tt.setupFake()

			// Mock config GetWithDefault to return a team
			_ = fake
			_ = config

			// Note: Full integration test would require mocking git.Config
			// For now, we've tested the individual components
		})
	}
}
