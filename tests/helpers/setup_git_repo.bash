# BATS helper: setup_git_repo.bash
# Provides helpers for creating and tearing down an isolated temp git repo.
#
# Usage in a test file:
#   load '../helpers/setup_git_repo'
#
#   setup() {
#     setup_git_repo
#   }
#
#   teardown() {
#     teardown_git_repo
#   }

setup_git_repo() {
  # BATS_TEST_TMPDIR is unique per test case and auto-cleaned by bats-core 1.5+.
  # Fall back to BATS_TMPDIR for older versions.
  local base="${BATS_TEST_TMPDIR:-$BATS_TMPDIR}"
  TEST_REPO_DIR="$(mktemp -d "$base/aw-test-XXXXXX")"
  # Resolve symlinks so paths match git's canonical view (macOS /var -> /private/var).
  TEST_REPO_DIR="$(cd "$TEST_REPO_DIR" && pwd -P)"
  export TEST_REPO_DIR

  cd "$TEST_REPO_DIR"

  git init
  git config user.email "test@example.com"
  git config user.name "Test User"

  # Create an initial commit so HEAD exists
  git commit --allow-empty -m "initial commit"
}

teardown_git_repo() {
  cd /
  rm -rf "$TEST_REPO_DIR"
}
