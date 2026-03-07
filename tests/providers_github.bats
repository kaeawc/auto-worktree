#!/usr/bin/env bats
# Tests for src/providers/github.sh

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

load 'helpers/mock_cli'

setup() {
  setup_mock_cli

  # Source the provider under test
  # shellcheck source=../src/providers/github.sh
  source "${REPO_ROOT}/src/providers/github.sh"
}

teardown() {
  teardown_mock_cli
}

# ============================================================================
# _aw_github_list_issues
# ============================================================================

@test "_aw_github_list_issues: formats output correctly" {
  # The function uses --template so gh outputs formatted text directly.
  # Mock gh to emit the expected formatted output.
  mock_cli gh "" '#42 | Fix bug | [bug]'

  run _aw_github_list_issues
  [ "$status" -eq 0 ]
  [[ "$output" == *"#42"* ]]
  [[ "$output" == *"Fix bug"* ]]
}

@test "_aw_github_list_issues: includes label in output" {
  mock_cli gh "" '#10 | Add feature | [enhancement]'

  run _aw_github_list_issues
  [ "$status" -eq 0 ]
  [[ "$output" == *"[enhancement]"* ]]
}

@test "_aw_github_list_issues: works with no labels" {
  mock_cli gh "" '#7 | Simple issue'

  run _aw_github_list_issues
  [ "$status" -eq 0 ]
  [[ "$output" == *"#7"* ]]
  [[ "$output" == *"Simple issue"* ]]
}

@test "_aw_github_list_issues: empty output when gh returns nothing" {
  mock_cli gh "" ''

  run _aw_github_list_issues
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_aw_github_list_issues: calls gh issue list" {
  mock_cli gh "" '#1 | Test'

  run _aw_github_list_issues
  assert_cli_called gh "issue list"
}

# ============================================================================
# _aw_github_get_issue_details
# ============================================================================

@test "_aw_github_get_issue_details: extracts title and body from JSON" {
  local json='{"number":42,"title":"Fix the login bug","body":"Steps to reproduce...","state":"OPEN","labels":[]}'
  mock_cli gh "" "$json"

  # Source in current shell so title/body variables are set
  _aw_github_get_issue_details "42"
  [ "$title" = "Fix the login bug" ]
  [ "$body" = "Steps to reproduce..." ]
}

@test "_aw_github_get_issue_details: strips leading # from issue ID" {
  local json='{"number":99,"title":"Hash prefixed issue","body":"Body text","state":"OPEN","labels":[]}'
  mock_cli gh "" "$json"

  _aw_github_get_issue_details "#99"
  [ "$title" = "Hash prefixed issue" ]
}

@test "_aw_github_get_issue_details: returns 0 on success" {
  local json='{"number":5,"title":"Some issue","body":"Some body","state":"OPEN","labels":[]}'
  mock_cli gh "" "$json"

  run _aw_github_get_issue_details "5"
  [ "$status" -eq 0 ]
}

@test "_aw_github_get_issue_details: returns 1 for empty issue ID" {
  run _aw_github_get_issue_details ""
  [ "$status" -eq 1 ]
}

@test "_aw_github_get_issue_details: returns 1 when gh returns empty output" {
  mock_cli gh "" ''

  run _aw_github_get_issue_details "42"
  [ "$status" -eq 1 ]
}

@test "_aw_github_get_issue_details: handles null body gracefully" {
  local json='{"number":10,"title":"No body issue","body":null,"state":"OPEN","labels":[]}'
  mock_cli gh "" "$json"

  _aw_github_get_issue_details "10"
  [ "$title" = "No body issue" ]
  # jq renders null as empty string via // ""
  [ "$body" = "" ]
}

# ============================================================================
# _aw_github_check_closed
# ============================================================================

@test "_aw_github_check_closed: returns 0 when issue state is CLOSED" {
  # gh outputs the raw jq result: just the state string
  mock_cli gh "" 'CLOSED'

  run _aw_github_check_closed "42"
  [ "$status" -eq 0 ]
}

@test "_aw_github_check_closed: returns 1 when issue state is OPEN" {
  mock_cli gh "" 'OPEN'

  run _aw_github_check_closed "42"
  [ "$status" -eq 1 ]
}

@test "_aw_github_check_closed: strips leading # from issue ID" {
  mock_cli gh "" 'CLOSED'

  run _aw_github_check_closed "#42"
  [ "$status" -eq 0 ]
}

@test "_aw_github_check_closed: returns 1 for empty issue ID" {
  run _aw_github_check_closed ""
  [ "$status" -eq 1 ]
}

@test "_aw_github_check_closed: returns 1 when gh returns empty output" {
  mock_cli gh "" ''

  run _aw_github_check_closed "42"
  [ "$status" -eq 1 ]
}

@test "_aw_github_check_closed: sets _AW_ISSUE_HAS_PR=true when open PR count > 0" {
  # Use a call-count-aware mock: first call returns CLOSED (issue state),
  # second call returns 1 (open PR count).
  local mock_bin="$MOCK_BIN_DIR"
  cat > "$MOCK_BIN_DIR/gh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "${mock_bin}/gh.calls"
CALL_COUNT_FILE="${mock_bin}/gh.count"
count=\$(cat "\$CALL_COUNT_FILE" 2>/dev/null || echo 0)
count=\$((count + 1))
echo "\$count" > "\$CALL_COUNT_FILE"
if [ "\$count" -eq 1 ]; then
  echo "CLOSED"
else
  echo "1"
fi
EOF
  chmod +x "$MOCK_BIN_DIR/gh"

  _aw_github_check_closed "42"
  [ "$_AW_ISSUE_HAS_PR" = "true" ]
}

@test "_aw_github_check_closed: sets _AW_ISSUE_HAS_PR=false when no open PRs" {
  # First call returns CLOSED, second returns 0 (no PRs)
  local mock_bin="$MOCK_BIN_DIR"
  cat > "$MOCK_BIN_DIR/gh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "${mock_bin}/gh.calls"
CALL_COUNT_FILE="${mock_bin}/gh.count"
count=\$(cat "\$CALL_COUNT_FILE" 2>/dev/null || echo 0)
count=\$((count + 1))
echo "\$count" > "\$CALL_COUNT_FILE"
if [ "\$count" -eq 1 ]; then
  echo "CLOSED"
else
  echo "0"
fi
EOF
  chmod +x "$MOCK_BIN_DIR/gh"

  _aw_github_check_closed "42"
  [ "$_AW_ISSUE_HAS_PR" = "false" ]
}

# ============================================================================
# Edge cases: gh command failure
# ============================================================================

@test "_aw_github_list_issues: succeeds even when gh exits non-zero (2>/dev/null)" {
  # The function redirects stderr and relies on output; a failing gh produces
  # empty output, which is acceptable (exit 0 from the function itself).
  cat > "$MOCK_BIN_DIR/gh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$MOCK_BIN_DIR/gh"

  run _aw_github_list_issues
  # Function itself should not propagate gh's non-zero due to 2>/dev/null + pipeline
  # The template output will be empty but status is 0 (pipeline)
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_aw_github_get_issue_details: returns 1 when gh fails" {
  cat > "$MOCK_BIN_DIR/gh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$MOCK_BIN_DIR/gh"

  run _aw_github_get_issue_details "42"
  [ "$status" -eq 1 ]
}
