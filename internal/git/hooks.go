package git

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// HookExecutor defines the interface for executing git hooks
type HookExecutor interface {
	// Execute runs a hook script with the given parameters and streams output
	Execute(hookPath string, params []string, env []string, output io.Writer) error
	// IsExecutable checks if a file exists and is executable
	IsExecutable(path string) bool
}

// RealHookExecutor executes actual hook scripts
type RealHookExecutor struct{}

// NewHookExecutor creates a new real hook executor for production use
func NewHookExecutor() HookExecutor {
	return &RealHookExecutor{}
}

// Execute runs a hook script with the given parameters
func (e *RealHookExecutor) Execute(hookPath string, params []string, env []string, output io.Writer) error {
	cmd := exec.Command(hookPath, params...)
	cmd.Env = env
	cmd.Stdout = output
	cmd.Stderr = output

	if err := cmd.Run(); err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			return fmt.Errorf("hook exited with code %d", exitErr.ExitCode())
		}
		return fmt.Errorf("failed to execute hook: %w", err)
	}

	return nil
}

// IsExecutable checks if a file exists and is executable
func (e *RealHookExecutor) IsExecutable(path string) bool {
	info, err := os.Stat(path)
	if err != nil {
		return false
	}
	// Check if it's a regular file and has execute permission
	return info.Mode().IsRegular() && (info.Mode().Perm()&0111) != 0
}

// HookManager manages git hook discovery and execution
type HookManager struct {
	// repoPath is the repository root directory
	repoPath string
	// config provides access to git configuration
	config *Config
	// gitExecutor executes git commands for hook discovery
	gitExecutor GitExecutor
	// hookExecutor executes hook scripts
	hookExecutor HookExecutor
	// output is where hook output is written
	output io.Writer
}

// NewHookManager creates a new HookManager
func NewHookManager(repoPath string, config *Config, gitExecutor GitExecutor, hookExecutor HookExecutor, output io.Writer) *HookManager {
	return &HookManager{
		repoPath:     repoPath,
		config:       config,
		gitExecutor:  gitExecutor,
		hookExecutor: hookExecutor,
		output:       output,
	}
}

// findHookDirectories returns the list of directories to search for hooks
// Priority order: core.hooksPath, .husky, .git/hooks
func (hm *HookManager) findHookDirectories() ([]string, error) {
	var dirs []string

	// 1. Check for custom hooks path in git config
	customPath, err := hm.config.Get("core.hooksPath", ConfigScopeAuto)
	if err == nil && customPath != "" {
		// Convert relative paths to absolute
		if !filepath.IsAbs(customPath) {
			customPath = filepath.Join(hm.repoPath, customPath)
		}
		dirs = append(dirs, customPath)
	}

	// 2. Check for .husky directory
	huskyPath := filepath.Join(hm.repoPath, ".husky")
	if info, err := os.Stat(huskyPath); err == nil && info.IsDir() {
		dirs = append(dirs, huskyPath)
	}

	// 3. Get standard git hooks directory using git rev-parse --git-common-dir
	gitCommonDir, err := hm.gitExecutor.ExecuteInDir(hm.repoPath, "rev-parse", "--git-common-dir")
	if err == nil && gitCommonDir != "" {
		// Convert relative path to absolute
		if !filepath.IsAbs(gitCommonDir) {
			gitCommonDir = filepath.Join(hm.repoPath, gitCommonDir)
		}
		standardHooksPath := filepath.Join(gitCommonDir, "hooks")
		dirs = append(dirs, standardHooksPath)
	}

	return dirs, nil
}

// findHook searches for a hook in the configured directories
// Returns the path to the first executable hook found, or empty string if none found
func (hm *HookManager) findHook(hookName string) (string, error) {
	dirs, err := hm.findHookDirectories()
	if err != nil {
		return "", err
	}

	// On Windows, also try common executable extensions
	var hookVariants []string
	hookVariants = append(hookVariants, hookName)
	if filepath.Separator == '\\' { // Windows
		hookVariants = append(hookVariants, hookName+".bat", hookName+".cmd", hookName+".exe", hookName+".ps1")
	}

	for _, dir := range dirs {
		for _, variant := range hookVariants {
			hookPath := filepath.Join(dir, variant)
			if hm.hookExecutor.IsExecutable(hookPath) {
				return hookPath, nil
			}
		}
	}

	return "", nil
}

// executeHook executes a single hook with the given parameters
func (hm *HookManager) executeHook(hookName string, params []string) error {
	hookPath, err := hm.findHook(hookName)
	if err != nil {
		return fmt.Errorf("failed to find hook %s: %w", hookName, err)
	}

	// Hook not found is not an error
	if hookPath == "" {
		return nil
	}

	// Build environment with enhanced PATH
	env := os.Environ()
	pathEnhanced := false
	for i, e := range env {
		if strings.HasPrefix(e, "PATH=") {
			// Append common directories to PATH
			additionalPaths := "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
			env[i] = e + ":" + additionalPaths
			pathEnhanced = true
			break
		}
	}
	if !pathEnhanced {
		// PATH not found, add it
		env = append(env, "PATH=/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
	}

	// Execute the hook
	if err := hm.hookExecutor.Execute(hookPath, params, env, hm.output); err != nil {
		return fmt.Errorf("hook %s failed: %w", hookName, err)
	}

	return nil
}

// ExecuteWorktreeHooks executes post-checkout and post-worktree hooks after worktree creation
func (hm *HookManager) ExecuteWorktreeHooks(worktreePath string) error {
	// Check if hooks are enabled
	if !hm.config.GetRunHooks() {
		return nil
	}

	failOnError := hm.config.GetFailOnHookError()

	// Get current HEAD for hook parameters
	headSHA, err := hm.gitExecutor.ExecuteInDir(worktreePath, "rev-parse", "HEAD")
	if err != nil {
		// If we can't get HEAD, use a placeholder
		headSHA = "0000000000000000000000000000000000000000"
	}

	// post-checkout hook parameters: <prev-head> <new-head> <branch-flag>
	// prev-head: null SHA (new worktree, no previous HEAD)
	// new-head: current HEAD SHA
	// branch-flag: 1 (indicates branch checkout, not file checkout)
	postCheckoutParams := []string{
		"0000000000000000000000000000000000000000",
		headSHA,
		"1",
	}

	// Execute post-checkout hook
	if err := hm.executeHook("post-checkout", postCheckoutParams); err != nil {
		if failOnError {
			return err
		}
		fmt.Fprintf(hm.output, "Warning: %v\n", err)
	}

	// Execute post-worktree hook (no standard parameters)
	if err := hm.executeHook("post-worktree", []string{}); err != nil {
		if failOnError {
			return err
		}
		fmt.Fprintf(hm.output, "Warning: %v\n", err)
	}

	// Execute custom hooks
	customHooks := hm.config.GetCustomHooks()
	for _, hookName := range customHooks {
		if err := hm.executeHook(hookName, []string{}); err != nil {
			if failOnError {
				return err
			}
			fmt.Fprintf(hm.output, "Warning: %v\n", err)
		}
	}

	return nil
}
