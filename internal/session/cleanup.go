package session

import (
	"fmt"
	"os"
	"path/filepath"
	"time"
)

// CleanupResult contains information about cleanup operations
type CleanupResult struct {
	TotalSessions    int
	ActiveSessions   int
	OrphanedSessions int
	IdleSessions     int
	FailedSessions   int
	RemovedMetadata  []string
	Errors           []error
}

// CleanupOptions controls cleanup behavior
type CleanupOptions struct {
	// RemoveOrphanedMetadata removes metadata files for non-existent sessions
	RemoveOrphanedMetadata bool

	// MarkIdleAsIdle marks sessions idle after threshold without removing them
	MarkIdleAsIdle bool

	// IdleThresholdMinutes is the duration (in minutes) before marking as idle
	IdleThresholdMinutes int

	// DryRun performs cleanup checks without modifying files
	DryRun bool

	// OnProgress is called with progress messages
	OnProgress func(string)
}

// DefaultCleanupOptions returns default cleanup options
func DefaultCleanupOptions() *CleanupOptions {
	return &CleanupOptions{
		RemoveOrphanedMetadata: true,
		MarkIdleAsIdle:         true,
		IdleThresholdMinutes:   120,
		DryRun:                 false,
		OnProgress: func(string) {
			// No-op by default
		},
	}
}

// CleanupOrphanedSessions cleans up metadata for sessions that no longer exist
func (m *Manager) CleanupOrphanedSessions(opts *CleanupOptions) (*CleanupResult, error) {
	if opts == nil {
		opts = DefaultCleanupOptions()
	}

	result := &CleanupResult{
		RemovedMetadata: []string{},
		Errors:          []error{},
	}

	if opts.OnProgress == nil {
		opts.OnProgress = func(string) {}
	}

	// Load all metadata
	allMetadata, err := m.LoadAllSessionMetadata()
	if err != nil {
		return result, fmt.Errorf("failed to load session metadata: %w", err)
	}

	result.TotalSessions = len(allMetadata)

	// Check each session
	for _, metadata := range allMetadata {
		// Check if session still exists
		exists, err := m.HasSession(metadata.SessionName)
		if err != nil {
			result.Errors = append(result.Errors, fmt.Errorf("failed to check session %s: %w", metadata.SessionName, err))
			continue
		}

		if !exists {
			// Session is orphaned
			result.OrphanedSessions++
			opts.OnProgress(fmt.Sprintf("Found orphaned session: %s", metadata.SessionName))

			if opts.RemoveOrphanedMetadata && !opts.DryRun {
				if err := m.DeleteSessionMetadata(metadata.SessionName); err != nil {
					result.Errors = append(result.Errors, err)
					continue
				}
				result.RemovedMetadata = append(result.RemovedMetadata, metadata.SessionName)
				opts.OnProgress(fmt.Sprintf("Removed metadata for orphaned session: %s", metadata.SessionName))
			}
		} else {
			// Session exists
			result.ActiveSessions++

			// Check if session is idle
			if opts.MarkIdleAsIdle && metadata.Status != StatusIdle && metadata.Status != StatusFailed {
				idleDuration := time.Since(metadata.LastAccessedAt)
				idleThreshold := time.Duration(opts.IdleThresholdMinutes) * time.Minute

				if idleDuration > idleThreshold {
					result.IdleSessions++
					opts.OnProgress(fmt.Sprintf("Found idle session: %s (inactive for %v)", metadata.SessionName, idleDuration))

					if !opts.DryRun {
						if err := m.MarkSessionIdle(metadata.SessionName); err != nil {
							result.Errors = append(result.Errors, err)
							continue
						}
						opts.OnProgress(fmt.Sprintf("Marked as idle: %s", metadata.SessionName))
					}
				}
			}

			// Count failed sessions
			if metadata.Status == StatusFailed {
				result.FailedSessions++
			}
		}
	}

	return result, nil
}

// CleanupOrphanedMetadataFiles removes orphaned metadata files from disk
// This is useful if the metadata directory somehow contains files without corresponding sessions
func (m *Manager) CleanupOrphanedMetadataFiles(opts *CleanupOptions) error {
	if opts == nil {
		opts = DefaultCleanupOptions()
	}

	if opts.OnProgress == nil {
		opts.OnProgress = func(string) {}
	}

	// Get the session directory
	sessionDir, err := GetSessionDir()
	if err != nil {
		return err
	}

	// Read all metadata files
	entries, err := os.ReadDir(sessionDir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil // Directory doesn't exist, nothing to clean
		}
		return err
	}

	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}

		if filepath.Ext(entry.Name()) != ".json" {
			continue
		}

		sessionName := entry.Name()[:len(entry.Name())-5] // Remove .json

		// Check if session exists
		exists, err := m.HasSession(sessionName)
		if err != nil {
			continue // Skip on error
		}

		if !exists {
			opts.OnProgress(fmt.Sprintf("Removing orphaned metadata file: %s.json", sessionName))

			if !opts.DryRun {
				path := filepath.Join(sessionDir, entry.Name())
				if err := os.Remove(path); err != nil {
					opts.OnProgress(fmt.Sprintf("Failed to remove %s: %v", entry.Name(), err))
				}
			}
		}
	}

	return nil
}
