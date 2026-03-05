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
  TEST_REPO_DIR="$(mktemp -d "$BATS_TMPDIR/aw-test-XXXXXX")"
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
