#!/bin/bash

# ============================================================================
# Git hook finding, execution, running
# ============================================================================
_aw_find_hook_paths() {
  # Find all possible hook directories
  # Returns paths separated by newlines
  local worktree_path="$1"
  local hook_paths=()

  # 1. Check custom git config core.hooksPath
  local custom_hooks_path=$(git -C "$worktree_path" config core.hooksPath 2>/dev/null)
  if [[ -n "$custom_hooks_path" ]]; then
    # Handle both absolute and relative paths
    if [[ "$custom_hooks_path" == /* ]]; then
      hook_paths+=("$custom_hooks_path")
    else
      hook_paths+=("$worktree_path/$custom_hooks_path")
    fi
  fi

  # 2. Check .husky directory (popular Node.js hook manager)
  if [[ -d "$worktree_path/.husky" ]]; then
    hook_paths+=("$worktree_path/.husky")
  fi

  # 3. Standard .git/hooks directory
  # For worktrees, use --git-common-dir to get the shared hooks directory
  local git_common_dir=$(git -C "$worktree_path" rev-parse --git-common-dir 2>/dev/null)
  if [[ -n "$git_common_dir" && -d "$git_common_dir/hooks" ]]; then
    hook_paths+=("$git_common_dir/hooks")
  fi

  # Print paths (one per line)
  for path in "${hook_paths[@]}"; do
    echo "$path"
  done
}

_aw_execute_hook() {
  # Execute a single git hook if it exists and is executable
  # Returns 0 on success, 1 on failure, 2 if hook doesn't exist
  local hook_path="$1"
  local worktree_path="$2"
  local hook_name=$(basename "$hook_path")

  if [[ ! -f "$hook_path" ]]; then
    return 2  # Hook doesn't exist
  fi

  if [[ ! -x "$hook_path" ]]; then
    return 2  # Hook not executable
  fi

  # Display hook execution
  echo ""
  gum style --foreground 6 "Running git hook: $hook_name"

  # Execute hook in worktree context
  # Pass standard git hook parameters for post-checkout: <prev-head> <new-head> <branch-flag>
  # For worktree creation, we use: 0000000000000000000000000000000000000000 HEAD 1
  local prev_head="0000000000000000000000000000000000000000"
  local new_head=$(git -C "$worktree_path" rev-parse HEAD 2>/dev/null || echo "HEAD")
  local branch_flag="1"  # 1 = branch checkout, 0 = file checkout

  # Set up PATH for hook execution
  # Git hooks run with minimal environment, so we need to ensure they have access to:
  # 1. User's current PATH (includes user-installed tools like gum, homebrew packages, etc.)
  # 2. Standard system directories (fallback for basic commands)
  # 3. Common package manager directories (Homebrew on macOS, etc.)
  local hook_path_env="$PATH"

  # Add common directories if not already in PATH (for robustness)
  local additional_paths="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  hook_path_env="$hook_path_env:$additional_paths"

  # Run hook with output displayed directly to user
  if (cd "$worktree_path" && PATH="$hook_path_env" "$hook_path" "$prev_head" "$new_head" "$branch_flag"); then
    gum style --foreground 2 "✓ Hook $hook_name completed successfully"
    return 0
  else
    return 1
  fi
}

_aw_run_git_hooks() {
  # Run git hooks during worktree setup
  # Executes hooks in order: post-checkout, post-clone, post-worktree, custom hooks
  local worktree_path="$1"

  # Check if hook execution is enabled (default: true)
  local run_hooks=$(git -C "$worktree_path" config --bool auto-worktree.run-hooks 2>/dev/null)
  if [[ "$run_hooks" == "false" ]]; then
    return 0
  fi

  # Get failure handling preference (default: false = warn only)
  local fail_on_error=$(git -C "$worktree_path" config --bool auto-worktree.fail-on-hook-error 2>/dev/null)
  if [[ -z "$fail_on_error" ]]; then
    fail_on_error="false"
  fi

  # Find all hook directories
  local hook_paths=()
  while IFS= read -r hook_dir_path; do
    hook_paths+=("$hook_dir_path")
  done < <(_aw_find_hook_paths "$worktree_path")

  if [[ ${#hook_paths[@]} -eq 0 ]]; then
    # No hook directories found, skip silently
    return 0
  fi

  # Define hooks to run in order
  # Note: post-checkout is already run by git automatically during worktree creation
  local hooks_to_run=("post-clone" "post-worktree")

  # Check for custom hooks config
  local custom_hooks=$(git -C "$worktree_path" config auto-worktree.custom-hooks 2>/dev/null)
  if [[ -n "$custom_hooks" ]]; then
    # Add custom hooks (space or comma separated)
    IFS=', ' read -ra custom_array <<< "$custom_hooks"
    hooks_to_run+=("${custom_array[@]}")
  fi

  local any_hook_ran=false
  local any_hook_failed=false
  local failed_hooks=()

  # Execute each hook in order
  for hook_name in "${hooks_to_run[@]}"; do
    local hook_found=false

    # Try to find and execute the hook in each hook directory
    for hook_dir in "${hook_paths[@]}"; do
      local hook_path="$hook_dir/$hook_name"

      _aw_execute_hook "$hook_path" "$worktree_path"
      local result=$?

      if [[ $result -eq 0 ]]; then
        # Hook succeeded
        hook_found=true
        any_hook_ran=true
        break  # Don't run same hook from other directories
      elif [[ $result -eq 1 ]]; then
        # Hook failed
        hook_found=true
        any_hook_ran=true
        any_hook_failed=true
        failed_hooks+=("$hook_name")

        # Display error with config hint
        echo ""
        gum style --foreground 1 "✗ Hook $hook_name failed"
        if [[ "$fail_on_error" == "true" ]]; then
          gum style --foreground 3 "To continue despite hook failures, run:"
          gum style --foreground 7 "  git config auto-worktree.fail-on-hook-error false"
          return 1
        else
          gum style --foreground 3 "⚠ Continuing despite hook failure (auto-worktree.fail-on-hook-error=false)"
          gum style --foreground 7 "  To fail on hook errors, run: git config auto-worktree.fail-on-hook-error true"
        fi
        break  # Don't try other directories for this hook
      fi
      # result == 2 means hook doesn't exist, continue to next directory
    done
  done

  if [[ "$any_hook_ran" == "true" ]]; then
    echo ""
  fi

  return 0
}
