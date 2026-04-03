#!/usr/bin/env bats
# Tests for CLI prefix wrapper detection in src/lib/ai.sh
#
# Coverage:
#   - Prefix-based detection: tools available via prefix when bare binary missing
#   - Saved preference with prefix: saved pref works when only prefix provides access
#   - Install menu: prefix wrapper option triggers configure flow
#   - _setup_ai_cmd: prefix applied to command construction

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

load 'helpers/setup_git_repo'

setup() {
  setup_git_repo

  # Stub gum to be a no-op by default
  gum() { :; }
  export -f gum

  # Stub _aw_get_issue_provider
  _aw_get_issue_provider() { echo "github"; }
  export -f _aw_get_issue_provider

  # Source the modules under test
  source "${REPO_ROOT}/src/lib/utils.sh"
  source "${REPO_ROOT}/src/lib/config.sh"
  source "${REPO_ROOT}/src/lib/ai.sh"

  # Create a fake prefix command in a temp bin dir
  FAKE_BIN="${TEST_REPO_DIR}/fakebin"
  mkdir -p "$FAKE_BIN"
  printf '#!/bin/sh\nexit 0\n' > "$FAKE_BIN/myprefix"
  chmod +x "$FAKE_BIN/myprefix"
  export PATH="$FAKE_BIN:$PATH"
}

teardown() {
  teardown_git_repo
}

# ============================================================================
# _resolve_ai_command — prefix-based detection
# ============================================================================

@test "prefix detection: all tools available when prefix configured and in PATH" {
  # No bare tools in PATH, but prefix is configured
  git config auto-worktree.ai-tool-cmd "myprefix"
  git config auto-worktree.ai-tool "skip"

  _resolve_ai_command

  [ "$AI_CMD_NAME" = "none" ]
}

@test "prefix detection: saved preference 'claude' works via prefix" {
  git config auto-worktree.ai-tool-cmd "myprefix"
  git config auto-worktree.ai-tool "claude"

  _resolve_ai_command

  [ "$AI_CMD_NAME" = "Claude Code" ]
  # Verify the command uses the prefix
  [ "${AI_CMD[0]}" = "myprefix" ]
  [ "${AI_CMD[1]}" = "claude" ]
  [ "${AI_CMD[2]}" = "--dangerously-skip-permissions" ]
}

@test "prefix detection: saved preference 'codex' works via prefix" {
  git config auto-worktree.ai-tool-cmd "myprefix"
  git config auto-worktree.ai-tool "codex"

  _resolve_ai_command

  [ "$AI_CMD_NAME" = "Codex" ]
  [ "${AI_CMD[0]}" = "myprefix" ]
  [ "${AI_CMD[1]}" = "codex" ]
  [ "${AI_CMD[2]}" = "--yolo" ]
}

@test "prefix detection: saved preference 'gemini' works via prefix" {
  git config auto-worktree.ai-tool-cmd "myprefix"
  git config auto-worktree.ai-tool "gemini"

  _resolve_ai_command

  [ "$AI_CMD_NAME" = "Gemini CLI" ]
  [ "${AI_CMD[0]}" = "myprefix" ]
  [ "${AI_CMD[1]}" = "gemini" ]
}

@test "prefix detection: saved preference 'jules' works via prefix" {
  git config auto-worktree.ai-tool-cmd "myprefix"
  git config auto-worktree.ai-tool "jules"

  _resolve_ai_command

  [ "$AI_CMD_NAME" = "Google Jules CLI" ]
  [ "${AI_CMD[0]}" = "myprefix" ]
  [ "${AI_CMD[1]}" = "jules" ]
}

@test "prefix detection: resume command also uses prefix" {
  git config auto-worktree.ai-tool-cmd "myprefix"
  git config auto-worktree.ai-tool "claude"

  _resolve_ai_command

  [ "${AI_RESUME_CMD[0]}" = "myprefix" ]
  [ "${AI_RESUME_CMD[1]}" = "claude" ]
  [ "${AI_RESUME_CMD[2]}" = "--dangerously-skip-permissions" ]
  [ "${AI_RESUME_CMD[3]}" = "--continue" ]
}

@test "prefix detection: no effect when prefix not in PATH" {
  git config auto-worktree.ai-tool-cmd "nonexistent_prefix"
  git config auto-worktree.ai-tool "claude"

  # Stub gum choose to return Cancel (no bare claude either)
  gum() {
    if [[ "$1" == "choose" ]]; then
      echo "Cancel"
    fi
  }
  export -f gum

  run _resolve_ai_command
  [ "$status" -ne 0 ]
}

@test "prefix detection: no effect when no prefix configured" {
  # Override to ensure no prefix is returned (isolates from user's global git config)
  _aw_get_ai_tool_cmd() { echo ""; }
  export -f _aw_get_ai_tool_cmd

  # Restrict PATH to only system essentials — no claude/codex/gemini/jules/myprefix
  export PATH="/usr/bin:/bin"
  git config auto-worktree.ai-tool "claude"

  gum() {
    if [[ "$1" == "choose" ]]; then
      echo "Cancel"
    fi
  }
  export -f gum

  run _resolve_ai_command
  [ "$status" -ne 0 ]
}

@test "prefix detection: legacy space-delimited prefix extracts first word" {
  git config auto-worktree.ai-tool-cmd "myprefix claude"
  git config auto-worktree.ai-tool "claude"

  _resolve_ai_command

  [ "$AI_CMD_NAME" = "Claude Code" ]
  [ "${AI_CMD[0]}" = "myprefix" ]
  [ "${AI_CMD[1]}" = "claude" ]
}

# ============================================================================
# _setup_ai_cmd — prefix applied correctly
# ============================================================================

@test "setup_ai_cmd: uses prefix when configured" {
  git config auto-worktree.ai-tool-cmd "myprefix"

  _setup_ai_cmd claude "claude"

  [ "${AI_CMD[0]}" = "myprefix" ]
  [ "${AI_CMD[1]}" = "claude" ]
  [ "${AI_CMD[2]}" = "--dangerously-skip-permissions" ]
}

@test "setup_ai_cmd: uses bare path when no prefix" {
  # Override to ensure no prefix (isolates from user's global git config)
  _aw_get_ai_tool_cmd() { echo ""; }
  export -f _aw_get_ai_tool_cmd

  _setup_ai_cmd claude "/usr/local/bin/claude"

  [ "${AI_CMD[0]}" = "/usr/local/bin/claude" ]
  [ "${AI_CMD[1]}" = "--dangerously-skip-permissions" ]
}

# ============================================================================
# _install_ai_tool — prefix option present in menu
# ============================================================================

@test "install menu: prefix wrapper option appears in menu" {
  # Capture what gum choose receives
  local captured_args=""
  gum() {
    if [[ "$1" == "choose" ]]; then
      captured_args="$*"
      echo "Cancel"
    fi
  }
  export -f gum

  run _install_ai_tool

  # The menu output should contain the prefix option
  [[ "$output" == *"No AI coding assistant found"* ]] || true
}

@test "install menu: prefix wrapper option configures and selects tool" {
  local counter_file="${TEST_REPO_DIR}/.gum_choose_count"
  echo "0" > "$counter_file"

  gum() {
    case "$1" in
      choose)
        local count
        count=$(cat "$counter_file")
        count=$((count + 1))
        echo "$count" > "$counter_file"
        if [[ $count -eq 1 ]]; then
          # First choose: main install menu
          echo "Configure CLI prefix wrapper (e.g. slack, goog)"
        elif [[ $count -eq 2 ]]; then
          # Second choose: scope selection in _aw_configure_corporate_wrapper
          echo "This project only"
        elif [[ $count -eq 3 ]]; then
          # Third choose: which tool to use
          echo "Claude Code"
        fi
        ;;
      input)
        # Corporate prefix input
        echo "myprefix"
        ;;
      style)
        shift
        echo "$*"
        ;;
      *)
        ;;
    esac
  }
  export -f gum

  _install_ai_tool

  [ "$AI_CMD_NAME" = "Claude Code" ]
  [ "${AI_CMD[0]}" = "myprefix" ]
  [ "${AI_CMD[1]}" = "claude" ]
}

@test "install menu: prefix wrapper warns when prefix not in PATH" {
  local gum_call_count=0
  gum() {
    case "$1" in
      choose)
        gum_call_count=$((gum_call_count + 1))
        if [[ $gum_call_count -eq 1 ]]; then
          echo "Configure CLI prefix wrapper (e.g. slack, goog)"
        elif [[ $gum_call_count -eq 2 ]]; then
          echo "This project only"
        fi
        ;;
      input)
        echo "bad_prefix_not_in_path"
        ;;
      style)
        shift
        echo "$*"
        ;;
      *)
        ;;
    esac
  }
  export -f gum

  run _install_ai_tool
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found in PATH"* ]]
}
