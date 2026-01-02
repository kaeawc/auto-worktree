package github

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func TestParseGitHubURL(t *testing.T) {
	tests := []struct {
		name      string
		url       string
		wantOwner string
		wantRepo  string
		wantErr   error
	}{
		{
			name:      "HTTPS with .git",
			url:       "https://github.com/owner/repo.git",
			wantOwner: "owner",
			wantRepo:  "repo",
			wantErr:   nil,
		},
		{
			name:      "HTTPS without .git",
			url:       "https://github.com/owner/repo",
			wantOwner: "owner",
			wantRepo:  "repo",
			wantErr:   nil,
		},
		{
			name:      "SSH with .git",
			url:       "git@github.com:owner/repo.git",
			wantOwner: "owner",
			wantRepo:  "repo",
			wantErr:   nil,
		},
		{
			name:      "SSH without .git",
			url:       "git@github.com:owner/repo",
			wantOwner: "owner",
			wantRepo:  "repo",
			wantErr:   nil,
		},
		{
			name:      "Non-GitHub URL",
			url:       "https://gitlab.com/owner/repo.git",
			wantOwner: "",
			wantRepo:  "",
			wantErr:   ErrNotGitHubRepo,
		},
		{
			name:      "Invalid URL",
			url:       "not-a-url",
			wantOwner: "",
			wantRepo:  "",
			wantErr:   ErrNotGitHubRepo,
		},
		{
			name:      "Empty URL",
			url:       "",
			wantOwner: "",
			wantRepo:  "",
			wantErr:   ErrNotGitHubRepo,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			owner, repo, err := parseGitHubURL(tt.url)

			if err != tt.wantErr {
				t.Errorf("parseGitHubURL() error = %v, wantErr %v", err, tt.wantErr)
				return
			}

			if owner != tt.wantOwner {
				t.Errorf("parseGitHubURL() owner = %v, want %v", owner, tt.wantOwner)
			}

			if repo != tt.wantRepo {
				t.Errorf("parseGitHubURL() repo = %v, want %v", repo, tt.wantRepo)
			}
		})
	}
}

func TestDetectRepository(t *testing.T) {
	// Create a temporary directory for test repository
	tmpDir, err := os.MkdirTemp("", "auto-worktree-test-*")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	// Initialize a git repository
	cmd := exec.Command("git", "init")
	cmd.Dir = tmpDir
	if err := cmd.Run(); err != nil {
		t.Fatalf("failed to init git repo: %v", err)
	}

	tests := []struct {
		name       string
		setupRepo  func() error
		wantOwner  string
		wantRepo   string
		wantErr    error
		wantErrMsg string // For checking error type when exact match isn't possible
	}{
		{
			name: "Origin remote with HTTPS URL",
			setupRepo: func() error {
				cmd := exec.Command("git", "remote", "add", "origin", "https://github.com/testowner/testrepo.git")
				cmd.Dir = tmpDir
				return cmd.Run()
			},
			wantOwner: "testowner",
			wantRepo:  "testrepo",
			wantErr:   nil,
		},
		{
			name: "Origin remote with SSH URL",
			setupRepo: func() error {
				// Remove existing origin first
				cmd := exec.Command("git", "remote", "remove", "origin")
				cmd.Dir = tmpDir
				cmd.Run() // Ignore error if doesn't exist

				cmd = exec.Command("git", "remote", "add", "origin", "git@github.com:sshowner/sshrepo.git")
				cmd.Dir = tmpDir
				return cmd.Run()
			},
			wantOwner: "sshowner",
			wantRepo:  "sshrepo",
			wantErr:   nil,
		},
		{
			name: "Fallback to first remote when no origin",
			setupRepo: func() error {
				// Remove origin
				cmd := exec.Command("git", "remote", "remove", "origin")
				cmd.Dir = tmpDir
				cmd.Run()

				// Add a different remote
				cmd = exec.Command("git", "remote", "add", "upstream", "https://github.com/upstream/repo.git")
				cmd.Dir = tmpDir
				return cmd.Run()
			},
			wantOwner: "upstream",
			wantRepo:  "repo",
			wantErr:   nil,
		},
		{
			name: "No remotes configured",
			setupRepo: func() error {
				// Remove all remotes
				cmd := exec.Command("git", "remote", "remove", "upstream")
				cmd.Dir = tmpDir
				cmd.Run()
				return nil
			},
			wantOwner: "",
			wantRepo:  "",
			wantErr:   ErrNoRemote,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.setupRepo != nil {
				if err := tt.setupRepo(); err != nil {
					t.Fatalf("failed to setup repo: %v", err)
				}
			}

			info, err := DetectRepository(tmpDir)

			if tt.wantErr != nil {
				if err == nil {
					t.Errorf("DetectRepository() error = nil, wantErr %v", tt.wantErr)
					return
				}
				if err != tt.wantErr {
					t.Errorf("DetectRepository() error = %v, wantErr %v", err, tt.wantErr)
				}
				return
			}

			if err != nil {
				t.Errorf("DetectRepository() unexpected error = %v", err)
				return
			}

			if info.Owner != tt.wantOwner {
				t.Errorf("DetectRepository() Owner = %v, want %v", info.Owner, tt.wantOwner)
			}

			if info.Name != tt.wantRepo {
				t.Errorf("DetectRepository() Name = %v, want %v", info.Name, tt.wantRepo)
			}

			if info.URL == "" {
				t.Error("DetectRepository() URL should not be empty")
			}
		})
	}
}

func TestDetectRepositoryNonGitHubRemote(t *testing.T) {
	// Create a temporary directory for test repository
	tmpDir, err := os.MkdirTemp("", "auto-worktree-test-*")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	// Initialize a git repository
	cmd := exec.Command("git", "init")
	cmd.Dir = tmpDir
	if err := cmd.Run(); err != nil {
		t.Fatalf("failed to init git repo: %v", err)
	}

	// Add a non-GitHub remote
	cmd = exec.Command("git", "remote", "add", "origin", "https://gitlab.com/owner/repo.git")
	cmd.Dir = tmpDir
	if err := cmd.Run(); err != nil {
		t.Fatalf("failed to add remote: %v", err)
	}

	info, err := DetectRepository(tmpDir)

	if err != ErrNotGitHubRepo {
		t.Errorf("DetectRepository() error = %v, want %v", err, ErrNotGitHubRepo)
	}

	if info != nil {
		t.Errorf("DetectRepository() = %v, want nil", info)
	}
}

func TestDetectRepositoryInvalidPath(t *testing.T) {
	// Use a non-existent path
	nonExistentPath := filepath.Join(os.TempDir(), "non-existent-repo-12345")

	_, err := DetectRepository(nonExistentPath)

	if err == nil {
		t.Error("DetectRepository() error = nil, want error for non-existent path")
	}
}
