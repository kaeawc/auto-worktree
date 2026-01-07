package git

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestIsLockFileError(t *testing.T) {
	tests := []struct {
		name     string
		err      error
		expected bool
	}{
		{
			name:     "nil error",
			err:      nil,
			expected: false,
		},
		{
			name:     "index.lock error",
			err:      errors.New("fatal: Unable to create '.git/index.lock': File exists"),
			expected: true,
		},
		{
			name:     "generic lock error",
			err:      errors.New("error: could not lock config file .git/config.lock"),
			expected: true,
		},
		{
			name:     "unable to create error",
			err:      errors.New("unable to create '.git/refs/heads/main.lock'"),
			expected: true,
		},
		{
			name:     "file exists in .git",
			err:      errors.New("file exists: .git/index.lock"),
			expected: true,
		},
		{
			name:     "non-lock error",
			err:      errors.New("branch not found"),
			expected: false,
		},
		{
			name:     "empty error",
			err:      errors.New(""),
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := IsLockFileError(tt.err)
			if result != tt.expected {
				t.Errorf("IsLockFileError(%v) = %v, want %v", tt.err, result, tt.expected)
			}
		})
	}
}

func TestGetStaleLockFiles(t *testing.T) {
	lockFiles := []LockFile{
		{
			Path:         "/path/to/.git/index.lock",
			Age:          10 * time.Minute,
			ProcessID:    12345,
			ProcessAlive: false,
		},
		{
			Path:         "/path/to/.git/refs/heads/main.lock",
			Age:          5 * time.Minute,
			ProcessID:    67890,
			ProcessAlive: true,
		},
		{
			Path:         "/path/to/.git/config.lock",
			Age:          15 * time.Minute,
			ProcessID:    -1,
			ProcessAlive: false,
		},
	}

	stale := GetStaleLockFiles(lockFiles)

	if len(stale) != 2 {
		t.Errorf("GetStaleLockFiles() returned %d stale locks, want 2", len(stale))
	}

	for _, lf := range stale {
		if lf.ProcessAlive {
			t.Errorf("GetStaleLockFiles() included active lock: %s", lf.Path)
		}
	}
}

func TestRemoveLockFile(t *testing.T) {
	// Test removing a stale lock file
	t.Run("remove stale lock", func(t *testing.T) {
		// Create a temporary lock file
		tmpDir := t.TempDir()
		lockPath := filepath.Join(tmpDir, "test.lock")
		if err := os.WriteFile(lockPath, []byte("12345"), 0644); err != nil {
			t.Fatalf("Failed to create test lock file: %v", err)
		}

		lockFile := LockFile{
			Path:         lockPath,
			Age:          10 * time.Minute,
			ProcessID:    12345,
			ProcessAlive: false,
		}

		err := RemoveLockFile(lockFile)
		if err != nil {
			t.Errorf("RemoveLockFile() error = %v, want nil", err)
		}

		// Verify file was removed
		if _, err := os.Stat(lockPath); !os.IsNotExist(err) {
			t.Errorf("Lock file still exists after removal")
		}
	})

	// Test refusing to remove active lock
	t.Run("refuse to remove active lock", func(t *testing.T) {
		lockFile := LockFile{
			Path:         "/path/to/.git/index.lock",
			Age:          1 * time.Minute,
			ProcessID:    12345,
			ProcessAlive: true,
		}

		err := RemoveLockFile(lockFile)
		if err == nil {
			t.Error("RemoveLockFile() succeeded for active lock, want error")
		}

		if !strings.Contains(err.Error(), "still alive") {
			t.Errorf("RemoveLockFile() error = %v, want error about process being alive", err)
		}
	})

	// Test removing already removed lock (should not error)
	t.Run("remove non-existent lock", func(t *testing.T) {
		lockFile := LockFile{
			Path:         "/nonexistent/path/test.lock",
			Age:          10 * time.Minute,
			ProcessID:    -1,
			ProcessAlive: false,
		}

		err := RemoveLockFile(lockFile)
		if err != nil {
			t.Errorf("RemoveLockFile() error = %v for non-existent file, want nil", err)
		}
	})
}

func TestDetectLockFilesInvalidRepo(t *testing.T) {
	// Test with non-existent directory
	_, err := DetectLockFiles("/nonexistent/path")
	if err == nil {
		t.Error("DetectLockFiles() succeeded for non-existent path, want error")
	}

	if !strings.Contains(err.Error(), "not a git repository") {
		t.Errorf("DetectLockFiles() error = %v, want error about not being a git repository", err)
	}
}

func TestDetectLockFilesNoLocks(t *testing.T) {
	// Create a temporary directory structure mimicking a git repo
	tmpDir := t.TempDir()
	gitDir := filepath.Join(tmpDir, ".git")
	if err := os.Mkdir(gitDir, 0755); err != nil {
		t.Fatalf("Failed to create .git directory: %v", err)
	}

	// Create some non-lock files
	if err := os.WriteFile(filepath.Join(gitDir, "config"), []byte("test"), 0644); err != nil {
		t.Fatalf("Failed to create config file: %v", err)
	}

	lockFiles, err := DetectLockFiles(tmpDir)
	if err != nil {
		t.Errorf("DetectLockFiles() error = %v, want nil", err)
	}

	if len(lockFiles) != 0 {
		t.Errorf("DetectLockFiles() returned %d locks, want 0", len(lockFiles))
	}
}

func TestDetectLockFilesWithLocks(t *testing.T) {
	// Create a temporary directory structure mimicking a git repo
	tmpDir := t.TempDir()
	gitDir := filepath.Join(tmpDir, ".git")
	if err := os.Mkdir(gitDir, 0755); err != nil {
		t.Fatalf("Failed to create .git directory: %v", err)
	}

	refsDir := filepath.Join(gitDir, "refs", "heads")
	if err := os.MkdirAll(refsDir, 0755); err != nil {
		t.Fatalf("Failed to create refs/heads directory: %v", err)
	}

	// Create lock files
	indexLock := filepath.Join(gitDir, "index.lock")
	currentPID := fmt.Sprintf("%d", os.Getpid())
	if err := os.WriteFile(indexLock, []byte(currentPID), 0644); err != nil {
		t.Fatalf("Failed to create index.lock: %v", err)
	}

	configLock := filepath.Join(gitDir, "config.lock")
	if err := os.WriteFile(configLock, []byte("99999"), 0644); err != nil {
		t.Fatalf("Failed to create config.lock: %v", err)
	}

	branchLock := filepath.Join(refsDir, "main.lock")
	if err := os.WriteFile(branchLock, []byte("12345"), 0644); err != nil {
		t.Fatalf("Failed to create main.lock: %v", err)
	}

	// Add a small delay to ensure age is measurable
	time.Sleep(10 * time.Millisecond)

	lockFiles, err := DetectLockFiles(tmpDir)
	if err != nil {
		t.Errorf("DetectLockFiles() error = %v, want nil", err)
	}

	if len(lockFiles) != 3 {
		t.Errorf("DetectLockFiles() returned %d locks, want 3", len(lockFiles))
	}

	// Verify each lock file has the expected properties
	foundIndex := false
	foundConfig := false
	foundBranch := false

	for _, lf := range lockFiles {
		if strings.HasSuffix(lf.Path, "index.lock") {
			foundIndex = true
			// This should be our own process, so likely alive
			if lf.ProcessID != os.Getpid() {
				t.Errorf("index.lock ProcessID = %d, want %d", lf.ProcessID, os.Getpid())
			}
		}
		if strings.HasSuffix(lf.Path, "config.lock") {
			foundConfig = true
			// Unlikely PID 99999 is running
			if lf.ProcessID != 99999 {
				t.Errorf("config.lock ProcessID = %d, want 99999", lf.ProcessID)
			}
		}
		if strings.HasSuffix(lf.Path, "main.lock") {
			foundBranch = true
			if lf.ProcessID != 12345 {
				t.Errorf("main.lock ProcessID = %d, want 12345", lf.ProcessID)
			}
		}

		// Check that age is reasonable (should be very recent)
		if lf.Age < 0 || lf.Age > 10*time.Second {
			t.Errorf("Lock file age = %v, expected between 0 and 10 seconds", lf.Age)
		}
	}

	if !foundIndex {
		t.Error("DetectLockFiles() did not find index.lock")
	}
	if !foundConfig {
		t.Error("DetectLockFiles() did not find config.lock")
	}
	if !foundBranch {
		t.Error("DetectLockFiles() did not find main.lock")
	}
}

func TestLockFileString(t *testing.T) {
	lf := LockFile{
		Path:         "/path/to/.git/index.lock",
		Age:          5*time.Minute + 30*time.Second,
		ProcessID:    12345,
		ProcessAlive: false,
	}

	str := lf.String()

	// Check that the string contains expected information
	if !strings.Contains(str, "index.lock") {
		t.Errorf("String() = %q, expected to contain 'index.lock'", str)
	}
	if !strings.Contains(str, "12345") {
		t.Errorf("String() = %q, expected to contain PID '12345'", str)
	}
	if !strings.Contains(str, "stale") {
		t.Errorf("String() = %q, expected to contain 'stale'", str)
	}
}

func TestFormatLockFileWarning(t *testing.T) {
	t.Run("empty lock files", func(t *testing.T) {
		warning := FormatLockFileWarning([]LockFile{})
		if warning != "" {
			t.Errorf("FormatLockFileWarning([]) = %q, want empty string", warning)
		}
	})

	t.Run("only active locks", func(t *testing.T) {
		lockFiles := []LockFile{
			{
				Path:         "/path/to/.git/index.lock",
				Age:          1 * time.Minute,
				ProcessID:    12345,
				ProcessAlive: true,
			},
		}

		warning := FormatLockFileWarning(lockFiles)
		if !strings.Contains(warning, "active") {
			t.Errorf("FormatLockFileWarning() should mention active locks")
		}
		if strings.Contains(warning, "stale") {
			t.Errorf("FormatLockFileWarning() should not mention stale locks when there are none")
		}
	})

	t.Run("stale locks", func(t *testing.T) {
		lockFiles := []LockFile{
			{
				Path:         "/path/to/.git/index.lock",
				Age:          10 * time.Minute,
				ProcessID:    12345,
				ProcessAlive: false,
			},
		}

		warning := FormatLockFileWarning(lockFiles)
		if !strings.Contains(warning, "stale") {
			t.Errorf("FormatLockFileWarning() should mention stale locks")
		}
		if !strings.Contains(warning, "doctor") {
			t.Errorf("FormatLockFileWarning() should mention the doctor command")
		}
	})

	t.Run("mixed locks", func(t *testing.T) {
		lockFiles := []LockFile{
			{
				Path:         "/path/to/.git/index.lock",
				Age:          1 * time.Minute,
				ProcessID:    12345,
				ProcessAlive: true,
			},
			{
				Path:         "/path/to/.git/config.lock",
				Age:          10 * time.Minute,
				ProcessID:    67890,
				ProcessAlive: false,
			},
		}

		warning := FormatLockFileWarning(lockFiles)
		if !strings.Contains(warning, "stale") {
			t.Errorf("FormatLockFileWarning() should mention stale locks")
		}
		// Should show stale lock info even if there are active locks
		if !strings.Contains(warning, "doctor") {
			t.Errorf("FormatLockFileWarning() should mention the doctor command")
		}
	})
}
