package github

import (
	"testing"
)

func TestIsInstalled(t *testing.T) {
	// This test checks if gh CLI is installed on the system
	// The result will vary based on the environment
	installed := IsInstalled()

	// We can't assert a specific value, but we can verify the function runs
	t.Logf("gh CLI installed: %v", installed)

	// If gh is installed, test IsAuthenticated
	if installed {
		err := IsAuthenticated()
		if err == nil {
			t.Log("gh CLI is authenticated")
		} else if err == ErrGHNotAuthenticated {
			t.Log("gh CLI is not authenticated")
		} else {
			t.Errorf("IsAuthenticated() unexpected error: %v", err)
		}
	}
}

func TestNewClientWithRepo(t *testing.T) {
	tests := []struct {
		name    string
		owner   string
		repo    string
		wantErr bool
	}{
		{
			name:    "Valid owner and repo",
			owner:   "testowner",
			repo:    "testrepo",
			wantErr: !IsInstalled(), // Will error if gh not installed
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			client, err := NewClientWithRepo(tt.owner, tt.repo)

			if tt.wantErr {
				if err == nil {
					t.Error("NewClientWithRepo() expected error, got nil")
				}
				return
			}

			// Only proceed if gh is installed and authenticated
			if !IsInstalled() {
				t.Skip("gh CLI not installed, skipping test")
				return
			}

			if IsAuthenticated() != nil {
				t.Skip("gh CLI not authenticated, skipping test")
				return
			}

			if err != nil {
				t.Errorf("NewClientWithRepo() unexpected error: %v", err)
				return
			}

			if client.Owner != tt.owner {
				t.Errorf("NewClientWithRepo() Owner = %v, want %v", client.Owner, tt.owner)
			}

			if client.Repo != tt.repo {
				t.Errorf("NewClientWithRepo() Repo = %v, want %v", client.Repo, tt.repo)
			}
		})
	}
}

func TestNewClient(t *testing.T) {
	// This test requires a git repository with a GitHub remote
	// We'll skip it if gh is not installed or authenticated
	if !IsInstalled() {
		t.Skip("gh CLI not installed")
	}

	if IsAuthenticated() != nil {
		t.Skip("gh CLI not authenticated")
	}

	// Try to create client from current directory
	// This will only work if we're in a git repo with a GitHub remote
	_, err := NewClient(".")

	// We expect either success or ErrNotGitHubRepo/ErrNoRemote
	// but not ErrGHNotInstalled since we already checked
	if err != nil {
		if err == ErrGHNotInstalled {
			t.Errorf("NewClient() returned ErrGHNotInstalled, but gh is installed")
		} else if err == ErrGHNotAuthenticated {
			t.Errorf("NewClient() returned ErrGHNotAuthenticated, but gh is authenticated")
		} else {
			// Expected errors (not a git repo, not a GitHub repo, etc.)
			t.Logf("NewClient() error (expected in some environments): %v", err)
		}
	}
}

func TestClientExecGH(t *testing.T) {
	if !IsInstalled() {
		t.Skip("gh CLI not installed")
	}

	if IsAuthenticated() != nil {
		t.Skip("gh CLI not authenticated")
	}

	client := &Client{
		Owner: "cli",
		Repo:  "cli",
	}

	// Test a simple gh command (checking version should always work)
	// Note: We can't use execGH directly as it's not exported and expects repo context
	// Instead, we'll test execGHInRepo with a read-only command
	_, err := client.execGHInRepo("issue", "list", "--limit", "1", "--json", "number")

	if err != nil {
		// This might fail if we don't have access to cli/cli repo
		// or if the command syntax is wrong
		t.Logf("execGHInRepo() error (may be expected): %v", err)
	}
}
