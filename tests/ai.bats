#!/usr/bin/env bats
# Tests for src/lib/ai.sh
#
# Coverage:
#   - _aw_check_tool_installed: tool detection via PATH
#   - _ai_has_resumable_session: session directory detection
#   - _load_ai_preference / _save_ai_preference: git config round-trip
#   - _setup_ai_cmd: AI_CMD array construction for each tool type
#   - _setup_ai_cmd: corporate prefix wrapping via ai-tool-cmd
#   - _aw_get_config_bool / _aw_set_config_bool: git config bool helpers
#   - _aw_get_issue_autoselect / _aw_get_pr_autoselect: default-to-true behavior

load 'test_helper/common-setup'
load 'helpers/setup_git_repo'
load 'helpers/stub_gum'

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

setup() {
  _common_setup
  setup_git_repo
  setup_stub_gum

  # Source the module under test (ai.sh depends on config.sh for _aw_get_ai_tool_cmd)
  # shellcheck source=../src/lib/config.sh
  source "${REPO_ROOT}/src/lib/config.sh"
  # shellcheck source=../src/lib/ai.sh
  source "${REPO_ROOT}/src/lib/ai.sh"

  # Override to prevent global git config from leaking into tests
  _aw_get_ai_tool_cmd() { echo ""; }
  export -f _aw_get_ai_tool_cmd
}

teardown() {
  teardown_stub_gum
  teardown_git_repo
}

# ============================================================================
# _aw_check_tool_installed
# ============================================================================

@test "_aw_check_tool_installed: returns 0 for a tool that exists (bash)" {
  run _aw_check_tool_installed "bash"
  assert_success
}

@test "_aw_check_tool_installed: returns 1 for a tool that does not exist" {
  run _aw_check_tool_installed "nonexistent_tool_abc123"
  assert_failure
}

# ============================================================================
# _ai_has_resumable_session
# ============================================================================

@test "_ai_has_resumable_session: returns 0 when .claude dir exists for Claude Code" {
  AI_CMD_NAME="Claude Code"
  mkdir -p .claude
  run _ai_has_resumable_session
  assert_success
}

@test "_ai_has_resumable_session: returns 1 when .claude dir does not exist for Claude Code" {
  AI_CMD_NAME="Claude Code"
  run _ai_has_resumable_session
  assert_failure
}

@test "_ai_has_resumable_session: returns 0 when .codex dir exists for Codex" {
  AI_CMD_NAME="Codex"
  mkdir -p .codex
  run _ai_has_resumable_session
  assert_success
}

@test "_ai_has_resumable_session: returns 1 when .codex dir missing for Codex" {
  AI_CMD_NAME="Codex"
  run _ai_has_resumable_session
  assert_failure
}

@test "_ai_has_resumable_session: returns 0 when .gemini dir exists for Gemini CLI" {
  AI_CMD_NAME="Gemini CLI"
  mkdir -p .gemini
  run _ai_has_resumable_session
  assert_success
}

@test "_ai_has_resumable_session: returns 1 for unknown AI tool" {
  AI_CMD_NAME="Unknown Tool"
  run _ai_has_resumable_session
  assert_failure
}

# ============================================================================
# _load_ai_preference / _save_ai_preference
# ============================================================================

@test "_load_ai_preference: returns empty string when no preference is set" {
  run _load_ai_preference
  assert_success
  assert_output ""
}

@test "_save_ai_preference: saves and loads 'claude' preference" {
  _save_ai_preference "claude"
  run _load_ai_preference
  assert_success
  assert_output "claude"
}

@test "_save_ai_preference: saves and loads 'codex' preference" {
  _save_ai_preference "codex"
  run _load_ai_preference
  assert_success
  assert_output "codex"
}

@test "_save_ai_preference: unsets preference when given empty value" {
  _save_ai_preference "gemini"
  _save_ai_preference ""
  run _load_ai_preference
  assert_success
  assert_output ""
}

# ============================================================================
# _setup_ai_cmd
# ============================================================================

@test "_setup_ai_cmd: sets AI_CMD for claude with dangerously-skip-permissions" {
  # Override any global prefix so cmd_parts uses the default_path directly
  _setup_ai_cmd "claude" "/usr/local/bin/claude"
  [[ "${AI_CMD[0]}" == "/usr/local/bin/claude" ]]
  [[ "${AI_CMD[1]}" == "--dangerously-skip-permissions" ]]
  [[ "$AI_CMD_NAME" == "Claude Code" ]]
}

@test "_setup_ai_cmd: sets AI_RESUME_CMD for claude with --continue" {
  _setup_ai_cmd "claude" "/usr/local/bin/claude"
  [[ "${AI_RESUME_CMD[0]}" == "/usr/local/bin/claude" ]]
  [[ "${AI_RESUME_CMD[1]}" == "--dangerously-skip-permissions" ]]
  [[ "${AI_RESUME_CMD[2]}" == "--continue" ]]
}

@test "_setup_ai_cmd: sets AI_CMD for codex with --yolo" {
  _setup_ai_cmd "codex" "/usr/local/bin/codex"
  [[ "${AI_CMD[0]}" == "/usr/local/bin/codex" ]]
  [[ "${AI_CMD[1]}" == "--yolo" ]]
  [[ "$AI_CMD_NAME" == "Codex" ]]
}

@test "_setup_ai_cmd: sets AI_CMD for gemini with --yolo" {
  _setup_ai_cmd "gemini" "/usr/local/bin/gemini"
  [[ "${AI_CMD[0]}" == "/usr/local/bin/gemini" ]]
  [[ "${AI_CMD[1]}" == "--yolo" ]]
  [[ "$AI_CMD_NAME" == "Gemini CLI" ]]
}

@test "_setup_ai_cmd: sets AI_CMD for jules without extra flags" {
  _setup_ai_cmd "jules" "/usr/local/bin/jules"
  [[ "${AI_CMD[0]}" == "/usr/local/bin/jules" ]]
  [[ "${#AI_CMD[@]}" -eq 1 ]]
  [[ "$AI_CMD_NAME" == "Google Jules CLI" ]]
}

@test "_setup_ai_cmd: applies corporate prefix when configured and available" {
  # Create a mock corporate prefix command
  local mock_bin="$BATS_TEST_TMPDIR/mock-bin"
  mkdir -p "$mock_bin"
  printf '#!/usr/bin/env bash\nexec "$@"\n' > "$mock_bin/corp"
  chmod +x "$mock_bin/corp"
  PATH="$mock_bin:$PATH"

  # Override the stub to return "corp"
  _aw_get_ai_tool_cmd() { echo "corp"; }
  export -f _aw_get_ai_tool_cmd

  _setup_ai_cmd "claude" "/usr/local/bin/claude"

  [[ "${AI_CMD[0]}" == "corp" ]]
  [[ "${AI_CMD[1]}" == "claude" ]]
  [[ "${AI_CMD[2]}" == "--dangerously-skip-permissions" ]]
}

@test "_setup_ai_cmd: ignores corporate prefix when command not found" {
  _aw_get_ai_tool_cmd() { echo "nonexistent_corp_wrapper"; }
  export -f _aw_get_ai_tool_cmd

  _setup_ai_cmd "claude" "/usr/local/bin/claude"

  [[ "${AI_CMD[0]}" == "/usr/local/bin/claude" ]]
}

# ============================================================================
# _aw_get_config_bool / _aw_set_config_bool
# ============================================================================

@test "_aw_get_config_bool: returns 'false' for unset key" {
  run _aw_get_config_bool "some-unset-key"
  assert_success
  assert_output "false"
}

@test "_aw_set_config_bool: sets and retrieves a boolean config" {
  _aw_set_config_bool "test-bool" "true"
  run _aw_get_config_bool "test-bool"
  assert_success
  assert_output "true"
}

# ============================================================================
# _aw_get_issue_autoselect / _aw_get_pr_autoselect
# ============================================================================

@test "_aw_get_issue_autoselect: defaults to 'true' when not configured" {
  run _aw_get_issue_autoselect
  assert_success
  assert_output "true"
}

@test "_aw_get_issue_autoselect: returns 'false' when explicitly disabled" {
  git config --bool auto-worktree.issue-autoselect false
  run _aw_get_issue_autoselect
  assert_success
  assert_output "false"
}

@test "_aw_get_pr_autoselect: defaults to 'true' when not configured" {
  run _aw_get_pr_autoselect
  assert_success
  assert_output "true"
}

@test "_aw_get_pr_autoselect: returns 'false' when explicitly disabled" {
  git config --bool auto-worktree.pr-autoselect false
  run _aw_get_pr_autoselect
  assert_success
  assert_output "false"
}

@test "_is_autoselect_disabled: returns 1 (false) by default" {
  run _is_autoselect_disabled
  assert_failure
}

@test "_is_autoselect_disabled: returns 0 (true) when disabled" {
  git config --bool auto-worktree.issue-autoselect false
  run _is_autoselect_disabled
  assert_success
}

@test "_disable_autoselect: disables issue autoselect" {
  _disable_autoselect
  run _aw_get_issue_autoselect
  assert_output "false"
}

@test "_enable_autoselect: re-enables issue autoselect after disabling" {
  _disable_autoselect
  _enable_autoselect
  run _aw_get_issue_autoselect
  assert_output "true"
}

@test "_disable_pr_autoselect: disables PR autoselect" {
  _disable_pr_autoselect
  run _aw_get_pr_autoselect
  assert_output "false"
}

@test "_enable_pr_autoselect: re-enables PR autoselect after disabling" {
  _disable_pr_autoselect
  _enable_pr_autoselect
  run _aw_get_pr_autoselect
  assert_output "true"
}
