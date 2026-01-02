package github

import (
	"errors"
	"fmt"
	"os/exec"
	"regexp"
	"strings"
)

var (
	// ErrNotGitHubRepo is returned when the repository is not a GitHub repository
	ErrNotGitHubRepo = errors.New("not a GitHub repository")
	// ErrNoRemote is returned when no git remote is configured
	ErrNoRemote = errors.New("no git remote configured")
)

// RepositoryInfo contains detected repository information
type RepositoryInfo struct {
	Owner string // Repository owner (user or organization)
	Name  string // Repository name
	URL   string // Remote URL
}

// DetectRepository auto-detects GitHub owner/repo from git remote
// Tries 'origin' remote first, falls back to first available remote
// Supports both HTTPS and SSH URLs
func DetectRepository(gitRoot string) (*RepositoryInfo, error) {
	// Try origin remote first
	cmd := exec.Command("git", "config", "--get", "remote.origin.url")
	cmd.Dir = gitRoot
	output, err := cmd.Output()

	if err != nil {
		// Origin not found, try to get first remote
		cmd = exec.Command("git", "remote")
		cmd.Dir = gitRoot
		remotesOutput, remotesErr := cmd.Output()
		if remotesErr != nil {
			return nil, ErrNoRemote
		}

		remotes := strings.Split(strings.TrimSpace(string(remotesOutput)), "\n")
		if len(remotes) == 0 || remotes[0] == "" {
			return nil, ErrNoRemote
		}

		// Get URL for first remote
		cmd = exec.Command("git", "config", "--get", fmt.Sprintf("remote.%s.url", remotes[0]))
		cmd.Dir = gitRoot
		output, err = cmd.Output()
		if err != nil {
			return nil, ErrNoRemote
		}
	}

	url := strings.TrimSpace(string(output))
	if url == "" {
		return nil, ErrNoRemote
	}

	owner, repo, err := parseGitHubURL(url)
	if err != nil {
		return nil, err
	}

	return &RepositoryInfo{
		Owner: owner,
		Name:  repo,
		URL:   url,
	}, nil
}

// parseGitHubURL extracts owner/repo from a GitHub remote URL
// Handles:
//   - https://github.com/owner/repo.git
//   - https://github.com/owner/repo
//   - git@github.com:owner/repo.git
func parseGitHubURL(url string) (owner, repo string, err error) {
	// HTTPS pattern: https://github.com/owner/repo(.git)?
	httpsPattern := regexp.MustCompile(`^https://github\.com/([^/]+)/([^/]+?)(\.git)?$`)
	if matches := httpsPattern.FindStringSubmatch(url); matches != nil {
		return matches[1], matches[2], nil
	}

	// SSH pattern: git@github.com:owner/repo(.git)?
	sshPattern := regexp.MustCompile(`^git@github\.com:([^/]+)/([^/]+?)(\.git)?$`)
	if matches := sshPattern.FindStringSubmatch(url); matches != nil {
		return matches[1], matches[2], nil
	}

	return "", "", ErrNotGitHubRepo
}
