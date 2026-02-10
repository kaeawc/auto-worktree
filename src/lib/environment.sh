#!/bin/bash

# ============================================================================
# Auto-install project dependencies (npm, pip, cargo, go, etc.)
# ============================================================================
_aw_setup_environment() {
  # Automatically set up the development environment based on detected project files
  local worktree_path="$1"

  if [[ ! -d "$worktree_path" ]]; then
    return 0
  fi

  # Run git hooks before dependency installation
  _aw_run_git_hooks "$worktree_path"
  local hook_result=$?
  if [[ $hook_result -ne 0 ]]; then
    # Hook failed and fail-on-hook-error is true
    return 1
  fi

  local setup_ran=false

  # Node.js project
  if [[ -f "$worktree_path/package.json" ]]; then
    setup_ran=true
    echo ""
    gum style --foreground 6 "Detected Node.js project (package.json)"

    # Detect which package manager to use
    local pkg_manager="npm"
    local install_cmd=""

    # Check packageManager field in package.json
    if command -v jq &> /dev/null; then
      local pkg_mgr_field=$(jq -r '.packageManager // ""' "$worktree_path/package.json" 2>/dev/null)
      if [[ "$pkg_mgr_field" == bun* ]]; then
        pkg_manager="bun"
      elif [[ "$pkg_mgr_field" == pnpm* ]]; then
        pkg_manager="pnpm"
      elif [[ "$pkg_mgr_field" == yarn* ]]; then
        pkg_manager="yarn"
      fi
    fi

    # Check for lock files if packageManager field not found
    if [[ "$pkg_manager" == "npm" ]]; then
      if [[ -f "$worktree_path/bun.lockb" ]]; then
        pkg_manager="bun"
      elif [[ -f "$worktree_path/pnpm-lock.yaml" ]]; then
        pkg_manager="pnpm"
      elif [[ -f "$worktree_path/yarn.lock" ]]; then
        pkg_manager="yarn"
      fi
    fi

    # Run the appropriate package manager
    case "$pkg_manager" in
      bun)
        if command -v bun &> /dev/null; then
          if gum spin --spinner dot --title "Running bun install..." -- bun install --cwd "$worktree_path"; then
            gum style --foreground 2 "✓ Dependencies installed (bun)"
          else
            gum style --foreground 3 "⚠ bun install had issues (continuing anyway)"
          fi
        else
          gum style --foreground 3 "⚠ bun not found, skipping dependency installation"
        fi
        ;;
      pnpm)
        if command -v pnpm &> /dev/null; then
          if gum spin --spinner dot --title "Running pnpm install..." -- pnpm install --dir "$worktree_path" --silent; then
            gum style --foreground 2 "✓ Dependencies installed (pnpm)"
          else
            gum style --foreground 3 "⚠ pnpm install had issues (continuing anyway)"
          fi
        else
          gum style --foreground 3 "⚠ pnpm not found, skipping dependency installation"
        fi
        ;;
      yarn)
        if command -v yarn &> /dev/null; then
          if gum spin --spinner dot --title "Running yarn install..." -- sh -c "cd '$worktree_path' && yarn install --silent"; then
            gum style --foreground 2 "✓ Dependencies installed (yarn)"
          else
            gum style --foreground 3 "⚠ yarn install had issues (continuing anyway)"
          fi
        else
          gum style --foreground 3 "⚠ yarn not found, skipping dependency installation"
        fi
        ;;
      *)
        if command -v npm &> /dev/null; then
          if gum spin --spinner dot --title "Running npm install..." -- npm --prefix "$worktree_path" install --silent; then
            gum style --foreground 2 "✓ Dependencies installed (npm)"
          else
            gum style --foreground 3 "⚠ npm install had issues (continuing anyway)"
          fi
        else
          gum style --foreground 3 "⚠ npm not found, skipping dependency installation"
        fi
        ;;
    esac
  fi

  # Python project
  if [[ -f "$worktree_path/requirements.txt" ]] || [[ -f "$worktree_path/pyproject.toml" ]]; then
    setup_ran=true
    echo ""

    # Check if uv is available and configured
    local use_uv=false
    if command -v uv &> /dev/null; then
      # Check for uv.lock or [tool.uv] in pyproject.toml
      if [[ -f "$worktree_path/uv.lock" ]]; then
        use_uv=true
      elif [[ -f "$worktree_path/pyproject.toml" ]] && grep -q '\[tool\.uv\]' "$worktree_path/pyproject.toml" 2>/dev/null; then
        use_uv=true
      fi
    fi

    if [[ "$use_uv" == "true" ]]; then
      gum style --foreground 6 "Detected Python project (uv)"
      if gum spin --spinner dot --title "Running uv sync..." -- sh -c "cd '$worktree_path' && uv sync"; then
        gum style --foreground 2 "✓ Dependencies installed (uv + .venv)"
      else
        gum style --foreground 3 "⚠ uv sync had issues (continuing anyway)"
      fi
    elif [[ -f "$worktree_path/pyproject.toml" ]]; then
      gum style --foreground 6 "Detected Python project (pyproject.toml)"

      if command -v poetry &> /dev/null && [[ -f "$worktree_path/poetry.lock" ]]; then
        # Use poetry if poetry.lock exists
        if gum spin --spinner dot --title "Running poetry install..." -- poetry -C "$worktree_path" install --quiet; then
          gum style --foreground 2 "✓ Dependencies installed (poetry)"
        else
          gum style --foreground 3 "⚠ poetry install had issues (continuing anyway)"
        fi
      elif command -v pip &> /dev/null || command -v pip3 &> /dev/null; then
        # Fall back to pip
        local pip_cmd=$(command -v pip3 &> /dev/null && echo "pip3" || echo "pip")
        if gum spin --spinner dot --title "Installing Python dependencies..." -- $pip_cmd install -q -e "$worktree_path"; then
          gum style --foreground 2 "✓ Dependencies installed (pip)"
        else
          gum style --foreground 3 "⚠ pip install had issues (continuing anyway)"
        fi
      else
        gum style --foreground 3 "⚠ No Python package manager found"
      fi
    elif [[ -f "$worktree_path/requirements.txt" ]]; then
      gum style --foreground 6 "Detected Python project (requirements.txt)"

      if command -v pip &> /dev/null || command -v pip3 &> /dev/null; then
        local pip_cmd=$(command -v pip3 &> /dev/null && echo "pip3" || echo "pip")
        if gum spin --spinner dot --title "Installing Python dependencies..." -- $pip_cmd install -q -r "$worktree_path/requirements.txt"; then
          gum style --foreground 2 "✓ Dependencies installed (pip)"
        else
          gum style --foreground 3 "⚠ pip install had issues (continuing anyway)"
        fi
      else
        gum style --foreground 3 "⚠ pip not found, skipping dependency installation"
      fi
    fi
  fi

  # Ruby project
  if [[ -f "$worktree_path/Gemfile" ]]; then
    setup_ran=true
    echo ""
    gum style --foreground 6 "Detected Ruby project (Gemfile)"

    if command -v bundle &> /dev/null; then
      if gum spin --spinner dot --title "Running bundle install..." -- bundle install --gemfile="$worktree_path/Gemfile" --quiet; then
        gum style --foreground 2 "✓ Dependencies installed"
      else
        gum style --foreground 3 "⚠ bundle install had issues (continuing anyway)"
      fi
    else
      gum style --foreground 3 "⚠ bundle not found, skipping dependency installation"
    fi
  fi

  # Go project
  if [[ -f "$worktree_path/go.mod" ]]; then
    setup_ran=true
    echo ""
    gum style --foreground 6 "Detected Go project (go.mod)"

    if command -v go &> /dev/null; then
      if gum spin --spinner dot --title "Running go mod download..." -- sh -c "cd '$worktree_path' && go mod download"; then
        gum style --foreground 2 "✓ Dependencies downloaded"
      else
        gum style --foreground 3 "⚠ go mod download had issues (continuing anyway)"
      fi
    else
      gum style --foreground 3 "⚠ go not found, skipping dependency installation"
    fi
  fi

  # Rust project
  if [[ -f "$worktree_path/Cargo.toml" ]]; then
    setup_ran=true
    echo ""
    gum style --foreground 6 "Detected Rust project (Cargo.toml)"

    if command -v cargo &> /dev/null; then
      if gum spin --spinner dot --title "Running cargo fetch..." -- sh -c "cd '$worktree_path' && cargo fetch --quiet"; then
        gum style --foreground 2 "✓ Dependencies fetched"
      else
        gum style --foreground 3 "⚠ cargo fetch had issues (continuing anyway)"
      fi
    else
      gum style --foreground 3 "⚠ cargo not found, skipping dependency installation"
    fi
  fi

  if [[ "$setup_ran" == "true" ]]; then
    echo ""
  fi

  return 0
}
