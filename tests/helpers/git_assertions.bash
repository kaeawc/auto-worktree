# BATS helper: git_assertions.bash
# Assertion helpers for git/worktree state.
#
# Usage in a test file:
#   load '../helpers/git_assertions'
#
#   @test "worktree is created" {
#     assert_worktree_exists "/path/to/worktree"
#   }

# Assert that a git worktree exists at the given path.
#
# Usage: assert_worktree_exists <path>
assert_worktree_exists() {
  local path="$1"
  git worktree list --porcelain | grep -q "^worktree $path$" \
    || fail "Expected worktree to exist at: $path"
}

# Assert that a git branch exists.
#
# Usage: assert_branch_exists <branch>
assert_branch_exists() {
  local branch="$1"
  git branch --list "$branch" | grep -q "$branch" \
    || fail "Expected branch to exist: $branch"
}

# Assert that no git worktree exists at the given path.
#
# Usage: assert_no_worktree <path>
assert_no_worktree() {
  local path="$1"
  if git worktree list --porcelain | grep -q "^worktree $path$"; then
    fail "Expected no worktree at: $path"
  fi
}

# Assert that a git branch does not exist.
#
# Usage: assert_branch_not_exists <branch>
assert_branch_not_exists() {
  local branch="$1"
  if git branch --list "$branch" | grep -q "$branch"; then
    fail "Expected branch to not exist: $branch"
  fi
}
