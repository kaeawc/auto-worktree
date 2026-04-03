# BATS helper: stub_gum.bash
# Provides a reusable gum fake with sequenced responses and call recording.
#
# Usage in a test file:
#   load '../helpers/stub_gum'
#
#   setup() {
#     setup_stub_gum
#   }
#
#   teardown() {
#     teardown_stub_gum
#   }
#
#   @test "menu selection" {
#     gum_respond "Claude Code" "true"
#     run my_function_that_calls_gum
#     assert_gum_called "choose"
#   }

setup_stub_gum() {
  GUM_STUB_DIR="$(mktemp -d "$BATS_TMPDIR/gum-stub-XXXXXX")"
  export GUM_STUB_DIR
  # Response queue file — one response per line, consumed in order
  export GUM_RESPONSES_FILE="$GUM_STUB_DIR/responses"
  # Call log — each invocation appends "subcommand args..." on a line
  export GUM_CALLS_FILE="$GUM_STUB_DIR/calls"
  touch "$GUM_RESPONSES_FILE" "$GUM_CALLS_FILE"

  # Define the gum stub function
  eval 'gum() {
    local subcmd="${1:-}"
    echo "$*" >> "$GUM_CALLS_FILE"

    case "$subcmd" in
      style)
        # style just passes through its text arguments (skip flags)
        shift
        local text=""
        while [[ $# -gt 0 ]]; do
          case "$1" in
            --*) shift ;; # skip flags like --foreground
            *)  text+="$1 "; shift ;;
          esac
        done
        echo "${text% }"
        ;;
      spin)
        # spin runs a command after -- ; extract and execute it
        shift
        while [[ $# -gt 0 ]] && [[ "$1" != "--" ]]; do shift; done
        shift  # skip the --
        "$@"
        ;;
      choose|confirm|input|write|filter)
        # Return next queued response
        if [[ -s "$GUM_RESPONSES_FILE" ]]; then
          local response
          response=$(head -1 "$GUM_RESPONSES_FILE")
          sed -i.bak "1d" "$GUM_RESPONSES_FILE" && rm -f "${GUM_RESPONSES_FILE}.bak"

          if [[ "$subcmd" == "confirm" ]]; then
            # For confirm: "true" -> exit 0, anything else -> exit 1
            [[ "$response" == "true" ]] && return 0 || return 1
          fi
          echo "$response"
        else
          # No queued response — confirm defaults to failure, others return empty
          [[ "$subcmd" == "confirm" ]] && return 1
          echo ""
        fi
        ;;
      *)
        echo ""
        ;;
    esac
  }'
  export -f gum
}

# Queue responses that gum choose/confirm/input will return in order.
#
# Usage: gum_respond "first choice" "second choice" "true"
gum_respond() {
  for response in "$@"; do
    echo "$response" >> "$GUM_RESPONSES_FILE"
  done
}

# Assert that gum was called with a specific subcommand (substring match on calls log).
#
# Usage: assert_gum_called "choose"
#        assert_gum_called "confirm"
assert_gum_called() {
  local expected="$1"
  if [[ ! -f "$GUM_CALLS_FILE" ]]; then
    fail "Expected gum to be called with: $expected (no calls recorded)"
  fi
  grep -qF "$expected" "$GUM_CALLS_FILE" \
    || fail "Expected gum to be called with: $expected"$'\n'"Actual calls:"$'\n'"$(cat "$GUM_CALLS_FILE")"
}

# Assert that gum was NOT called with a specific subcommand.
#
# Usage: refute_gum_called "confirm"
refute_gum_called() {
  local unexpected="$1"
  if [[ -f "$GUM_CALLS_FILE" ]] && grep -qF "$unexpected" "$GUM_CALLS_FILE"; then
    fail "Expected gum NOT to be called with: $unexpected"$'\n'"Actual calls:"$'\n'"$(cat "$GUM_CALLS_FILE")"
  fi
}

# Get the number of times gum was called.
#
# Usage: count=$(gum_call_count)
gum_call_count() {
  if [[ -f "$GUM_CALLS_FILE" ]]; then
    wc -l < "$GUM_CALLS_FILE" | tr -d ' '
  else
    echo "0"
  fi
}

teardown_stub_gum() {
  rm -rf "$GUM_STUB_DIR"
  unset -f gum 2>/dev/null || true
}
