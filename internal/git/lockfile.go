package git

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// LockFile represents a Git lock file with metadata
type LockFile struct {
	Path         string
	Age          time.Duration
	ProcessID    int
	ProcessAlive bool
}

// String returns a human-readable description of the lock file
func (lf *LockFile) String() string {
	status := "stale"
	if lf.ProcessAlive {
		status = "active"
	}
	return fmt.Sprintf("%s (age: %s, pid: %d, %s)", lf.Path, lf.Age.Round(time.Second), lf.ProcessID, status)
}

// DetectLockFiles finds all Git lock files in the repository
func DetectLockFiles(repoPath string) ([]LockFile, error) {
	var lockFiles []LockFile

	gitDir := filepath.Join(repoPath, ".git")

	// Check if .git exists and is a directory
	info, err := os.Stat(gitDir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, fmt.Errorf("not a git repository: %s", repoPath)
		}
		return nil, fmt.Errorf("failed to access .git directory: %w", err)
	}

	// Handle .git file (worktree case)
	if !info.IsDir() {
		content, err := os.ReadFile(gitDir)
		if err != nil {
			return nil, fmt.Errorf("failed to read .git file: %w", err)
		}
		// Parse "gitdir: /path/to/repo/.git/worktrees/name"
		gitDirPath := strings.TrimSpace(strings.TrimPrefix(string(content), "gitdir:"))
		gitDir = gitDirPath
	}

	// Walk the .git directory to find lock files
	err = filepath.Walk(gitDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			// Skip inaccessible paths
			return nil
		}

		if info.IsDir() {
			return nil
		}

		// Check if file has .lock extension
		if !strings.HasSuffix(info.Name(), ".lock") {
			return nil
		}

		// Get file age
		age := time.Since(info.ModTime())

		// Try to determine process ID from lock file content
		pid := extractPIDFromLockFile(path)

		// Check if process is still running
		processAlive := isProcessAlive(pid)

		lockFiles = append(lockFiles, LockFile{
			Path:         path,
			Age:          age,
			ProcessID:    pid,
			ProcessAlive: processAlive,
		})

		return nil
	})

	if err != nil {
		return nil, fmt.Errorf("failed to walk .git directory: %w", err)
	}

	return lockFiles, nil
}

// extractPIDFromLockFile attempts to extract the process ID from a lock file
// Git lock files typically contain the PID as the first line or part of the content
func extractPIDFromLockFile(path string) int {
	content, err := os.ReadFile(path)
	if err != nil {
		return -1
	}

	// Git lock files often contain the PID followed by a newline
	// Example: "12345\n" or just "12345"
	lines := strings.Split(string(content), "\n")
	if len(lines) > 0 {
		pidStr := strings.TrimSpace(lines[0])
		// Some lock files might have additional content, try to extract just the number
		for _, part := range strings.Fields(pidStr) {
			if pid, err := strconv.Atoi(part); err == nil {
				return pid
			}
		}
	}

	return -1
}

// isProcessAlive checks if a process with the given PID is still running
func isProcessAlive(pid int) bool {
	if pid <= 0 {
		// Invalid PID, can't determine
		return false
	}

	// Try to send signal 0 to check if process exists
	// Signal 0 doesn't actually send a signal but checks if we could
	process, err := os.FindProcess(pid)
	if err != nil {
		return false
	}

	// On Unix systems, signal 0 checks if process exists
	err = process.Signal(syscall.Signal(0))
	if err != nil {
		// Process doesn't exist or we don't have permission
		return false
	}

	return true
}

// GetStaleLockFiles returns only lock files that are considered stale
func GetStaleLockFiles(lockFiles []LockFile) []LockFile {
	var stale []LockFile
	for _, lf := range lockFiles {
		if !lf.ProcessAlive {
			stale = append(stale, lf)
		}
	}
	return stale
}

// IsLockFileError checks if an error is related to a Git lock file
func IsLockFileError(err error) bool {
	if err == nil {
		return false
	}

	errStr := strings.ToLower(err.Error())
	return strings.Contains(errStr, "index.lock") ||
		strings.Contains(errStr, ".lock") ||
		strings.Contains(errStr, "unable to create") ||
		(strings.Contains(errStr, "file exists") && strings.Contains(errStr, ".git"))
}

// RemoveLockFile safely removes a lock file after verifying it's stale
func RemoveLockFile(lockFile LockFile) error {
	if lockFile.ProcessAlive {
		return fmt.Errorf("cannot remove lock file: process %d is still alive", lockFile.ProcessID)
	}

	err := os.Remove(lockFile.Path)
	if err != nil {
		if os.IsNotExist(err) {
			// Already removed, not an error
			return nil
		}
		return fmt.Errorf("failed to remove lock file %s: %w", lockFile.Path, err)
	}

	return nil
}

// FormatLockFileWarning creates a user-friendly warning message about lock files
func FormatLockFileWarning(lockFiles []LockFile) string {
	if len(lockFiles) == 0 {
		return ""
	}

	staleLocks := GetStaleLockFiles(lockFiles)
	if len(staleLocks) == 0 {
		return fmt.Sprintf("⚠️  Warning: Found %d active lock file(s). Git operations are currently in progress.\n", len(lockFiles))
	}

	var msg strings.Builder
	msg.WriteString(fmt.Sprintf("⚠️  Warning: Found %d stale lock file(s):\n", len(staleLocks)))
	for _, lf := range staleLocks {
		msg.WriteString(fmt.Sprintf("  • %s\n", lf.String()))
	}
	msg.WriteString("\nThese lock files may be preventing Git operations.\n")
	msg.WriteString("Run 'auto-worktree doctor --check-locks' for more information.\n")
	msg.WriteString("To remove stale locks manually: find .git -name '*.lock' -type f -delete\n")

	return msg.String()
}
