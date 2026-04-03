#!/usr/bin/env bats
# Tests for src/commands/create_issue.sh
#
# Coverage:
#   - _aw_validate_required: empty vs non-empty validation
#   - _aw_parse_template: file existence check and content return
#   - _aw_extract_template_sections: markdown header extraction, frontmatter stripping
#   - _aw_extract_section_content: section content extraction between headers

load 'test_helper/common-setup'
load 'helpers/setup_git_repo'
load 'helpers/stub_gum'

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

setup() {
  _common_setup
  setup_git_repo
  setup_stub_gum

  # shellcheck source=../src/commands/create_issue.sh
  source "${REPO_ROOT}/src/commands/create_issue.sh"
}

teardown() {
  teardown_stub_gum
  teardown_git_repo
}

# ============================================================================
# _aw_validate_required
# ============================================================================

@test "_aw_validate_required: returns 0 for non-empty value" {
  run _aw_validate_required "hello" "field_name"
  assert_success
}

@test "_aw_validate_required: returns 1 for empty value" {
  run _aw_validate_required "" "Title"
  assert_failure
  assert_output --partial "Title"
  assert_output --partial "required"
}

@test "_aw_validate_required: returns 0 for whitespace-only value" {
  # The function uses -n which treats whitespace as non-empty
  run _aw_validate_required "  " "field"
  assert_success
}

# ============================================================================
# _aw_parse_template
# ============================================================================

@test "_aw_parse_template: returns file content for existing template" {
  local template="$BATS_TEST_TMPDIR/template.md"
  cat > "$template" <<'EOF'
# Bug Report

## Description
Describe the bug here.

## Steps to Reproduce
1. Step one
2. Step two
EOF

  run _aw_parse_template "$template"
  assert_success
  assert_output --partial "Bug Report"
  assert_output --partial "Steps to Reproduce"
}

@test "_aw_parse_template: returns 1 for non-existent file" {
  run _aw_parse_template "/nonexistent/path/template.md"
  assert_failure
  assert_output --partial "Template file not found"
}

# ============================================================================
# _aw_extract_template_sections
# ============================================================================

@test "_aw_extract_template_sections: extracts h1 and h2 headers" {
  local template="$BATS_TEST_TMPDIR/template.md"
  cat > "$template" <<'EOF'
# Bug Report

## Description
Some content here.

## Steps to Reproduce
More content.

## Expected Behavior
What you expected.
EOF

  run _aw_extract_template_sections "$template"
  assert_success
  assert_line --index 0 "Bug Report"
  assert_line --index 1 "Description"
  assert_line --index 2 "Steps to Reproduce"
  assert_line --index 3 "Expected Behavior"
}

@test "_aw_extract_template_sections: strips YAML frontmatter" {
  local template="$BATS_TEST_TMPDIR/template.md"
  cat > "$template" <<'EOF'
---
name: bug_report
about: Report a bug
---

# Bug Report

## Description
Content here.
EOF

  run _aw_extract_template_sections "$template"
  assert_success
  assert_line --index 0 "Bug Report"
  assert_line --index 1 "Description"
  # Should NOT contain frontmatter fields
  refute_output --partial "name:"
  refute_output --partial "about:"
}

@test "_aw_extract_template_sections: returns 1 for non-existent file" {
  run _aw_extract_template_sections "/nonexistent/template.md"
  assert_failure
}

@test "_aw_extract_template_sections: returns empty for file with no headers" {
  local template="$BATS_TEST_TMPDIR/noheaders.md"
  echo "Just some plain text without headers." > "$template"

  run _aw_extract_template_sections "$template"
  assert_output ""
}

# ============================================================================
# _aw_extract_section_content
# ============================================================================

@test "_aw_extract_section_content: extracts content between two section headers" {
  local template="$BATS_TEST_TMPDIR/template.md"
  cat > "$template" <<'EOF'
## Description
This is the bug description.
It spans multiple lines.

## Steps to Reproduce
1. Step one
2. Step two
EOF

  run _aw_extract_section_content "$template" "Description"
  assert_success
  assert_output --partial "This is the bug description"
  assert_output --partial "multiple lines"
  # Should NOT include content from next section
  refute_output --partial "Step one"
}

@test "_aw_extract_section_content: extracts last section content" {
  local template="$BATS_TEST_TMPDIR/template.md"
  cat > "$template" <<'EOF'
## First Section
First content.

## Last Section
Last content here.
Final line.
EOF

  run _aw_extract_section_content "$template" "Last Section"
  assert_success
  assert_output --partial "Last content here"
  assert_output --partial "Final line"
}

@test "_aw_extract_section_content: returns empty for non-existent section" {
  local template="$BATS_TEST_TMPDIR/template.md"
  cat > "$template" <<'EOF'
## Description
Some content.
EOF

  run _aw_extract_section_content "$template" "Nonexistent Section"
  assert_success
  # Output should be empty (or whitespace only)
  [[ -z "$(echo "$output" | tr -d '[:space:]')" ]]
}

@test "_aw_extract_section_content: returns 1 for non-existent file" {
  run _aw_extract_section_content "/nonexistent/template.md" "Description"
  assert_failure
}

@test "_aw_extract_section_content: strips YAML frontmatter before extraction" {
  local template="$BATS_TEST_TMPDIR/template.md"
  cat > "$template" <<'EOF'
---
name: template
---

## Description
The actual description.
EOF

  run _aw_extract_section_content "$template" "Description"
  assert_success
  assert_output --partial "The actual description"
  refute_output --partial "name: template"
}
