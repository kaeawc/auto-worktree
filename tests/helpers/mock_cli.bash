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

# Creates a mock that returns different responses based on argument matching.
# Responses are checked in order — first matching pattern wins.
#
# Usage: mock_cli_conditional <tool> <pattern1> <response1> [<pattern2> <response2> ...]
#   tool     - the executable name (e.g. gh)
#   patternN - a substring to match against "$*"
#   responseN - the text to echo when the pattern matches
#
# Example:
#   mock_cli_conditional gh \
#     "issue list"    '{"issues": []}' \
#     "issue view"    '{"title": "Bug"}' \
#     "pr list"       '{"prs": []}'
mock_cli_conditional() {
  local tool="$1"
  shift

  # Build case arms from pattern/response pairs
  local case_arms=""
  while [[ $# -ge 2 ]]; do
    local pattern="$1"
    local response="$2"
    shift 2
    case_arms+="    *\"${pattern}\"*) echo '${response}' ;;"$'\n'
  done

  cat > "$MOCK_BIN_DIR/$tool" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$MOCK_BIN_DIR/${tool}.calls"
case "\$*" in
${case_arms}    *) echo "" ;;
esac
EOF
  chmod +x "$MOCK_BIN_DIR/$tool"
}

# Assert that a mock CLI was called exactly N times.
#
# Usage: assert_cli_call_count <tool> <expected_count>
assert_cli_call_count() {
  local tool="$1"
  local expected="$2"
  local calls_file="$MOCK_BIN_DIR/${tool}.calls"

  local actual=0
  if [[ -f "$calls_file" ]]; then
    actual=$(wc -l < "$calls_file" | tr -d ' ')
  fi

  if [[ "$actual" -ne "$expected" ]]; then
    fail "Expected $tool to be called $expected time(s), but was called $actual time(s)"
  fi
}

# Assert that a mock CLI was NOT called.
#
# Usage: refute_cli_called <tool>
refute_cli_called() {
  local tool="$1"
  local calls_file="$MOCK_BIN_DIR/${tool}.calls"

  if [[ -f "$calls_file" ]] && [[ -s "$calls_file" ]]; then
    fail "Expected $tool NOT to be called, but it was called:"$'\n'"$(cat "$calls_file")"
  fi
}

teardown_mock_cli() {
  rm -rf "$MOCK_BIN_DIR"
}
