# BATS helper: mock_cli.bash
# Provides helpers for creating mock executables for gh, glab, jira, linear.
#
# Mock executables:
#   - Record all invocations to $MOCK_BIN_DIR/${tool}.calls
#   - Return configured responses via environment variables or inline setup
#   - Are placed in a temp PATH directory that shadows the real CLIs
#
# Usage in a test file:
#   load '../helpers/mock_cli'
#
#   setup() {
#     setup_mock_cli
#     mock_cli gh "issue list" '{"issues": []}'
#   }
#
#   teardown() {
#     teardown_mock_cli
#   }
#
#   @test "calls gh issue list" {
#     run gh issue list
#     assert_cli_called gh "issue list"
#   }

setup_mock_cli() {
  MOCK_BIN_DIR="$(mktemp -d "$BATS_TMPDIR/mock-bin-XXXXXX")"
  export MOCK_BIN_DIR
  export PATH="$MOCK_BIN_DIR:$PATH"
}

# Creates a mock for a specific CLI tool.
# The mock will echo the given response and log all invocations.
#
# Usage: mock_cli <tool> <subcommand> <response>
#   tool       - the executable name (e.g. gh, glab, jira, linear)
#   subcommand - informational only; the same response is returned for all calls
#   response   - the text to echo when the mock is invoked
#
# Example:
#   mock_cli gh "issue list" '{"issues": []}'
mock_cli() {
  local tool="$1"
  local subcommand="$2"
  local response="$3"

  cat > "$MOCK_BIN_DIR/$tool" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$MOCK_BIN_DIR/${tool}.calls"
echo '$response'
EOF
  chmod +x "$MOCK_BIN_DIR/$tool"
}

# Assert that a mock CLI was called with the given arguments (substring match).
#
# Usage: assert_cli_called <tool> <expected_args>
#   tool          - the executable name (e.g. gh)
#   expected_args - substring expected to appear in the recorded call log
#
# Fails the test if no matching call is found.
assert_cli_called() {
  local tool="$1"
  local expected_args="$2"
  local calls_file="$MOCK_BIN_DIR/${tool}.calls"

  if [[ ! -f "$calls_file" ]]; then
    fail "Expected $tool to be called with: $expected_args (no calls recorded)"
  fi

  grep -qF "$expected_args" "$calls_file" \
    || fail "Expected $tool to be called with: $expected_args"
}

teardown_mock_cli() {
  rm -rf "$MOCK_BIN_DIR"
}
