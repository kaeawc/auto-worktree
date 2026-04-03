#!/usr/bin/env bats
# Tests for src/lib/deps.sh
#
# Coverage:
#   - _aw_check_deps: detects missing gum and jq
#   - _aw_check_issue_provider_deps: per-provider dependency checks (gh, glab, jira, linear)

load 'test_helper/common-setup'
load 'helpers/setup_git_repo'
load 'helpers/stub_gum'

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

setup() {
  _common_setup
  setup_git_repo
  setup_stub_gum

  # shellcheck source=../src/lib/deps.sh
  source "${REPO_ROOT}/src/lib/deps.sh"
}

teardown() {
  teardown_stub_gum
  teardown_git_repo
}

# ============================================================================
# _aw_check_deps
# ============================================================================

@test "_aw_check_deps: returns 0 when gum and jq are available" {
  # Both gum and jq should be available in the test environment
  # (gum is stubbed by stub_gum, and jq is typically installed)
  if ! command -v jq &>/dev/null; then
    skip "jq not installed in test environment"
  fi
  run _aw_check_deps
  assert_success
}

@test "_aw_check_deps: returns 1 and lists missing deps when gum is missing" {
  # Unset the stub to simulate missing gum
  unset -f gum

  # Shadow gum with a non-existent path so command -v fails
  local restricted_path="$BATS_TEST_TMPDIR/restricted-bin"
  mkdir -p "$restricted_path"
  # Create a fake jq so only gum is missing
  printf '#!/usr/bin/env bash\necho "jq"\n' > "$restricted_path/jq"
  chmod +x "$restricted_path/jq"

  PATH="$restricted_path" run _aw_check_deps
  assert_failure
  assert_output --partial "gum"
}

@test "_aw_check_deps: returns 1 and lists jq when jq is missing" {
  local restricted_path="$BATS_TEST_TMPDIR/restricted-bin"
  mkdir -p "$restricted_path"
  # Only provide gum
  printf '#!/usr/bin/env bash\n' > "$restricted_path/gum"
  chmod +x "$restricted_path/gum"

  # Need to unset the gum function so command -v finds the PATH one
  unset -f gum
  PATH="$restricted_path" run _aw_check_deps
  assert_failure
  assert_output --partial "jq"
}

# ============================================================================
# _aw_check_issue_provider_deps
# ============================================================================

@test "_aw_check_issue_provider_deps: returns 0 for github when gh is installed" {
  if ! command -v gh &>/dev/null; then
    skip "gh not installed"
  fi
  run _aw_check_issue_provider_deps "github"
  assert_success
}

@test "_aw_check_issue_provider_deps: returns 1 for github when gh is missing" {
  local restricted_path="$BATS_TEST_TMPDIR/restricted-bin"
  mkdir -p "$restricted_path"
  PATH="$restricted_path" run _aw_check_issue_provider_deps "github"
  assert_failure
  assert_output --partial "gh"
}

@test "_aw_check_issue_provider_deps: returns 1 for gitlab when glab is missing" {
  local restricted_path="$BATS_TEST_TMPDIR/restricted-bin"
  mkdir -p "$restricted_path"
  PATH="$restricted_path" run _aw_check_issue_provider_deps "gitlab"
  assert_failure
  assert_output --partial "glab"
}

@test "_aw_check_issue_provider_deps: returns 1 for jira when jira CLI is missing" {
  local restricted_path="$BATS_TEST_TMPDIR/restricted-bin"
  mkdir -p "$restricted_path"
  PATH="$restricted_path" run _aw_check_issue_provider_deps "jira"
  assert_failure
  assert_output --partial "jira"
}

@test "_aw_check_issue_provider_deps: returns 1 for linear when linear CLI is missing" {
  local restricted_path="$BATS_TEST_TMPDIR/restricted-bin"
  mkdir -p "$restricted_path"
  PATH="$restricted_path" run _aw_check_issue_provider_deps "linear"
  assert_failure
  assert_output --partial "linear"
}

@test "_aw_check_issue_provider_deps: returns 0 for unknown provider (no deps to check)" {
  run _aw_check_issue_provider_deps "unknown_provider"
  assert_success
}

@test "_aw_check_issue_provider_deps: error message for github mentions brew install" {
  local restricted_path="$BATS_TEST_TMPDIR/restricted-bin"
  mkdir -p "$restricted_path"
  PATH="$restricted_path" run _aw_check_issue_provider_deps "github"
  assert_output --partial "brew install gh"
}

@test "_aw_check_issue_provider_deps: error message for jira mentions jira-cli" {
  local restricted_path="$BATS_TEST_TMPDIR/restricted-bin"
  mkdir -p "$restricted_path"
  PATH="$restricted_path" run _aw_check_issue_provider_deps "jira"
  assert_output --partial "jira-cli"
}
