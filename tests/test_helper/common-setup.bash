# Common setup for all BATS test files.
#
# Usage in a test file:
#   setup() {
#     load 'test_helper/common-setup'
#     _common_setup
#   }

_common_setup() {
  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
  load 'test_helper/bats-file/load'

  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export PROJECT_ROOT
}
