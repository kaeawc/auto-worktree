package session

import (
	"os"
	"strconv"

	"github.com/kaeawc/auto-worktree/internal/git"
)

// TmuxConfig holds tmux session configuration
type TmuxConfig struct {
	Enabled           bool
	AutoInstall       bool
	Layout            string
	Shell             string
	WindowCount       int
	IdleThreshold     int // minutes
	LogCommands       bool
	PostCreateHook    string
	PostResumeHook    string
	PreKillHook       string
}

// DefaultTmuxConfig returns default tmux configuration
func DefaultTmuxConfig() *TmuxConfig {
	shell := os.Getenv("SHELL")
	if shell == "" {
		shell = "/bin/bash"
	}

	return &TmuxConfig{
		Enabled:       true,
		AutoInstall:   true,
		Layout:        "tiled",
		Shell:         shell,
		WindowCount:   1,
		IdleThreshold: 120,
		LogCommands:   true,
	}
}

// LoadTmuxConfig loads tmux configuration from git config
func LoadTmuxConfig(repo *git.Repository) (*TmuxConfig, error) {
	config := DefaultTmuxConfig()

	if repo == nil {
		return config, nil
	}

	// Load each configuration key with fallback to defaults
	if enabled, err := repo.Config.Get(git.ConfigTmuxEnabled, git.ConfigScopeAuto); err == nil && enabled != "" {
		config.Enabled = enabled == "true"
	}

	if autoInstall, err := repo.Config.Get(git.ConfigTmuxAutoInstall, git.ConfigScopeAuto); err == nil && autoInstall != "" {
		config.AutoInstall = autoInstall == "true"
	}

	if layout, err := repo.Config.Get(git.ConfigTmuxLayout, git.ConfigScopeAuto); err == nil && layout != "" {
		config.Layout = layout
	}

	if shell, err := repo.Config.Get(git.ConfigTmuxShell, git.ConfigScopeAuto); err == nil && shell != "" {
		config.Shell = shell
	}

	if windowCount, err := repo.Config.Get(git.ConfigTmuxWindowCount, git.ConfigScopeAuto); err == nil && windowCount != "" {
		if count, err := strconv.Atoi(windowCount); err == nil && count > 0 {
			config.WindowCount = count
		}
	}

	if idleThreshold, err := repo.Config.Get(git.ConfigTmuxIdleThreshold, git.ConfigScopeAuto); err == nil && idleThreshold != "" {
		if threshold, err := strconv.Atoi(idleThreshold); err == nil && threshold > 0 {
			config.IdleThreshold = threshold
		}
	}

	if logCommands, err := repo.Config.Get(git.ConfigTmuxLogCommands, git.ConfigScopeAuto); err == nil && logCommands != "" {
		config.LogCommands = logCommands == "true"
	}

	if postCreate, err := repo.Config.Get(git.ConfigTmuxPostCreateHook, git.ConfigScopeAuto); err == nil && postCreate != "" {
		config.PostCreateHook = postCreate
	}

	if postResume, err := repo.Config.Get(git.ConfigTmuxPostResumeHook, git.ConfigScopeAuto); err == nil && postResume != "" {
		config.PostResumeHook = postResume
	}

	if preKill, err := repo.Config.Get(git.ConfigTmuxPreKillHook, git.ConfigScopeAuto); err == nil && preKill != "" {
		config.PreKillHook = preKill
	}

	return config, nil
}
