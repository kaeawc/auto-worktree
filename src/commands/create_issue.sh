#!/bin/bash

# ============================================================================
# Issue creation: template parsing, provider create funcs, AI generation
# ============================================================================
_aw_parse_template() {
  # Parse a markdown template file
  # Args: $1 = template file path
  # Outputs: Template content as-is (for now, just return the content)
  local template_file="$1"

  if [[ ! -f "$template_file" ]]; then
    gum style --foreground 1 "Error: Template file not found: $template_file"
    return 1
  fi

  cat "$template_file"
}

_aw_extract_template_sections() {
  # Extract section headers from a markdown template
  # Args: $1 = template file path
  # Returns: List of section headers (lines starting with # or ##)
  local template_file="$1"

  if [[ ! -f "$template_file" ]]; then
    return 1
  fi

  # Strip YAML frontmatter first, then extract sections
  sed '/^---$/,/^---$/d' "$template_file" | grep -E '^#{1,2} ' | sed 's/^#* //'
}

_aw_extract_section_content() {
  # Extract content for a specific section from template
  # Args: $1 = template file path, $2 = section name
  # Returns: Content between this section header and the next section header
  local template_file="$1"
  local section_name="$2"

  if [[ ! -f "$template_file" ]]; then
    return 1
  fi

  # Strip YAML frontmatter and extract content for this section
  local content=$(sed '/^---$/,/^---$/d' "$template_file" | \
    awk -v section="$section_name" '
      BEGIN { in_section=0; found=0 }
      /^#{1,2} / {
        if (in_section) {
          exit
        }
        section_header = $0
        gsub(/^#* /, "", section_header)
        if (section_header == section) {
          in_section=1
          found=1
          next
        }
      }
      in_section { print }
    ')

  echo "$content"
}

# ============================================================================
# Issue creation helpers
# ============================================================================

_aw_create_issue_github() {
  # Create a GitHub issue
  # Args: $1 = title, $2 = body
  local title="$1"
  local body="$2"

  if [[ -z "$title" ]]; then
    gum style --foreground 1 "Error: Title is required"
    return 1
  fi

  local issue_url=$(gh issue create --title "$title" --body "$body" 2>&1)

  if [[ $? -eq 0 ]]; then
    gum style --foreground 2 "✓ Issue created: $issue_url"
    echo "$issue_url"
    return 0
  else
    gum style --foreground 1 "Error creating issue: $issue_url"
    return 1
  fi
}

_aw_create_issue_gitlab() {
  # Create a GitLab issue
  # Args: $1 = title, $2 = body
  local title="$1"
  local body="$2"

  if [[ -z "$title" ]]; then
    gum style --foreground 1 "Error: Title is required"
    return 1
  fi

  local issue_url=$(glab issue create --title "$title" --description "$body" 2>&1)

  if [[ $? -eq 0 ]]; then
    gum style --foreground 2 "✓ Issue created: $issue_url"
    echo "$issue_url"
    return 0
  else
    gum style --foreground 1 "Error creating issue: $issue_url"
    return 1
  fi
}

_aw_create_issue_jira() {
  # Create a JIRA issue
  # Args: $1 = title, $2 = body
  local title="$1"
  local body="$2"

  if [[ -z "$title" ]]; then
    gum style --foreground 1 "Error: Summary is required"
    return 1
  fi

  # Get default project
  local project=$(_aw_get_jira_project)

  if [[ -z "$project" ]]; then
    echo ""
    gum style --foreground 6 "JIRA Project Key:"
    project=$(gum input --placeholder "PROJ")
    if [[ -z "$project" ]]; then
      gum style --foreground 1 "Error: Project key is required"
      return 1
    fi
  fi

  local issue_key=$(jira issue create --project "$project" --type "Task" \
    --summary "$title" --body "$body" --plain --no-input 2>&1 | grep -oE '[A-Z]+-[0-9]+' | head -1)

  if [[ -n "$issue_key" ]]; then
    gum style --foreground 2 "✓ Issue created: $issue_key"
    echo "$issue_key"
    return 0
  else
    gum style --foreground 1 "Error creating JIRA issue"
    return 1
  fi
}

_aw_create_issue_linear() {
  # Create a Linear issue
  # Args: $1 = title, $2 = body
  local title="$1"
  local body="$2"

  if [[ -z "$title" ]]; then
    gum style --foreground 1 "Error: Title is required"
    return 1
  fi

  # Get default team
  local team=$(_aw_get_linear_team)

  if [[ -z "$team" ]]; then
    echo ""
    gum style --foreground 6 "Linear Team Key:"
    team=$(gum input --placeholder "TEAM")
    if [[ -z "$team" ]]; then
      gum style --foreground 1 "Error: Team key is required"
      return 1
    fi
  fi

  # Create issue using Linear CLI
  # Format: linear issue create -t "title" -d "description" --team TEAM
  local issue_id=$(linear issue create -t "$title" -d "$body" --team "$team" 2>&1 | grep -oE '[A-Z]+-[0-9]+' | head -1)

  if [[ -n "$issue_id" ]]; then
    gum style --foreground 2 "✓ Issue created: $issue_id"
    echo "$issue_id"
    return 0
  else
    gum style --foreground 1 "Error creating Linear issue"
    return 1
  fi
}

_aw_manual_template_walkthrough() {
  # Walk user through template sections manually
  # Args: $1 = template file path
  # Returns: Issue body as markdown
  local template_file="$1"
  local body=""

  # Read template content
  local template_content=$(cat "$template_file")

  # For now, use gum write to let user edit the template
  echo ""
  gum style --foreground 6 "Edit the issue template:"
  gum style --foreground 8 "Fill in the template sections (Ctrl+D when done, Ctrl+C to cancel)"
  echo ""

  body=$(echo "$template_content" | gum write --width 80 --height 20)

  # Check if user cancelled
  if [[ $? -ne 0 ]]; then
    return 1
  fi

  echo "$body"
}

_aw_ai_generate_issue_content() {
  # Use AI to generate issue content from a prompt
  # Args: $1 = user title/prompt, $2 = template file (optional)
  # Returns: Generated issue body content
  local user_prompt="$1"
  local template_file="$2"

  # Check if AI is available
  if [[ "${AI_CMD[1]}" == "skip" ]] || [[ -z "${AI_CMD[*]}" ]]; then
    return 1
  fi

  # Build the prompt for the AI
  local ai_prompt=""
  local template_content=""

  if [[ -n "$template_file" ]] && [[ -f "$template_file" ]]; then
    # Strip YAML frontmatter from template
    template_content=$(sed '/^---$/,/^---$/d' "$template_file")
  fi

  # Create a detailed prompt for the AI
  if [[ -n "$template_content" ]]; then
    ai_prompt="Generate a GitHub issue based on this request: ${user_prompt}

Fill out this template with detailed, helpful content:

${template_content}

Requirements:
- Write in clear, professional language
- Be specific and actionable
- Include relevant examples where applicable
- Fill out ALL sections of the template

Output ONLY the filled template content (no extra commentary)."
  else
    ai_prompt="Generate a detailed GitHub issue description for: ${user_prompt}

Include:
- Clear problem statement or feature request
- Specific details and context
- Expected outcomes or behavior
- Any relevant examples

Output the issue body in markdown format."
  fi

  # Show what we're doing
  echo ""
  gum style --foreground 6 "Generating issue content with ${AI_CMD_NAME}..."
  echo ""

  # Create output file (BSD/macOS compatible)
  # On BSD/macOS, XXXXXX must be at the end of the template, so we create
  # the temp file without .md extension and then rename it
  local output_file=$(mktemp /tmp/aw_issue_XXXXXX)

  # Check if mktemp succeeded
  if [[ -z "$output_file" ]] || [[ ! -f "$output_file" ]]; then
    gum style --foreground 3 "Failed to create temporary file"
    return 1
  fi

  # Add .md extension
  mv "$output_file" "${output_file}.md"
  output_file="${output_file}.md"

  # Execute AI in headless mode with -p flag
  if "${AI_CMD[@]}" -p "$ai_prompt" > "$output_file" 2>&1; then
    # AI completed successfully
    if [[ -s "$output_file" ]]; then
      echo "$output_file"
      return 0
    else
      gum style --foreground 3 "AI generated empty output"
      [[ -n "$output_file" ]] && rm "$output_file"
      return 1
    fi
  else
    # AI failed - unset default AI tool
    gum style --foreground 3 "AI generation failed"
    gum style --foreground 3 "Removing ${AI_CMD_NAME} as default AI tool"
    git config --unset auto-worktree.ai-tool 2>/dev/null || true
    [[ -n "$output_file" ]] && rm "$output_file"
    return 1
  fi
}

_aw_parse_ai_variations() {
  # Parse AI output to extract variations
  # Args: $1 = output file from AI
  # Returns: Displays variations and lets user choose
  local output_file="$1"

  if [[ ! -f "$output_file" ]]; then
    return 1
  fi

  # For now, just return the entire content
  # In a more sophisticated version, we'd parse the variations
  cat "$output_file"
}

_aw_fill_template_section_by_section() {
  # Walk through template sections interactively
  # Args: $1 = template file, $2 = issue title
  local template_file="$1"
  local issue_title="$2"

  # Extract sections from template
  local sections=$(_aw_extract_template_sections "$template_file")

  if [[ -z "$sections" ]]; then
    # No sections found, fall back to full template edit
    _aw_manual_template_walkthrough "$template_file"
    return $?
  fi

  echo ""
  gum style --foreground 6 "Fill out each section of the template:"
  echo ""

  local filled_content=""

  while IFS= read -r section_name; do
    echo ""
    gum style --foreground 4 --bold "## $section_name"
    echo ""

    # Extract the existing content for this section from the template
    local section_template_content=$(_aw_extract_section_content "$template_file" "$section_name")

    # Show template content as context (if it exists)
    if [[ -n "$section_template_content" ]]; then
      # Trim leading/trailing blank lines for display
      local trimmed_content=$(echo "$section_template_content" | sed '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')

      if [[ -n "$trimmed_content" ]]; then
        echo ""
        gum style --foreground 8 "Template guidance:"
        echo "$trimmed_content" | head -20
        echo ""
      fi
    fi

    # Ask user to provide content for this section, pre-populated with template content
    gum style --foreground 6 "Fill in or edit this section (Ctrl+D when done, Ctrl+C to cancel, leave blank to skip):"
    echo ""
    local section_content=$(echo "$section_template_content" | gum write --width 80 --height 15 \
      --char-limit 0)

    # Check if user cancelled
    if [[ $? -ne 0 ]]; then
      return 1
    fi

    # Only add section to filled content if it's not blank
    if [[ -n "$section_content" ]]; then
      filled_content+="## ${section_name}
${section_content}

"
    fi
  done <<< "$sections"

  echo "$filled_content"
}

# shellcheck disable=SC2120
_aw_create_issue() {
  # Create a new issue interactively
  # Supports both interactive mode and CLI flags
  _aw_ensure_git_repo || return 1
  _aw_get_repo_info

  # Parse CLI flags
  local flag_title=""
  local flag_body=""
  local flag_template=""
  local flag_no_template=false
  local flag_no_worktree=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title)
        flag_title="$2"
        shift 2
        ;;
      --body)
        flag_body="$2"
        shift 2
        ;;
      --template)
        flag_template="$2"
        shift 2
        ;;
      --no-template)
        flag_no_template=true
        shift
        ;;
      --no-worktree)
        flag_no_worktree=true
        shift
        ;;
      *)
        gum style --foreground 1 "Unknown option: $1"
        return 1
        ;;
    esac
  done

  # Determine issue provider
  local provider=$(_aw_get_issue_provider)

  # If not configured, prompt user to choose
  if [[ -z "$provider" ]]; then
    _aw_prompt_issue_provider || return 1
    provider=$(_aw_get_issue_provider)
  fi

  # Check for provider-specific dependencies
  _aw_check_issue_provider_deps "$provider" || return 1

  # Variables for issue creation
  local title=""
  local body=""
  local use_template=false
  local template_file=""

  # Non-interactive mode (CLI flags provided)
  if [[ -n "$flag_title" ]]; then
    title="$flag_title"
    body="$flag_body"

    if [[ -n "$flag_template" ]]; then
      if [[ -f "$flag_template" ]]; then
        template_file="$flag_template"
        body=$(_aw_parse_template "$template_file")
      else
        gum style --foreground 1 "Error: Template file not found: $flag_template"
        return 1
      fi
    fi
  else
    # Interactive mode
    # Check if templates are configured
    local templates_disabled=$(_aw_get_issue_templates_disabled)
    local no_prompt=$(_aw_get_issue_templates_prompt_disabled)

    # Show re-enable instructions if templates are disabled
    if [[ "$no_prompt" == "true" ]]; then
      echo ""
      gum style --foreground 8 "Note: Template prompts are disabled."
      gum style --foreground 8 "To re-enable: git config auto-worktree.issue-templates-no-prompt false"
    fi

    # Determine if we should prompt for template configuration
    # If no_prompt is false (or not set), we should always prompt/check templates
    # If no_prompt is true, skip prompting
    if [[ "$no_prompt" != "true" ]] && [[ "$flag_no_template" != true ]]; then
      # Check if templates are actually available
      local detected_templates=$(_aw_detect_issue_templates "$provider")

      # Show one-time notification if templates detected for the first time
      if [[ -n "$detected_templates" ]] && [[ -z "$(_aw_get_issue_templates_detected_flag)" ]]; then
        local template_count=$(echo "$detected_templates" | wc -l | tr -d ' ')
        echo ""
        gum style --foreground 2 "✓ Detected $template_count issue template(s) in $(_aw_get_template_default_dir "$provider")"
        gum style --foreground 8 "Templates will be available when creating issues"
        _aw_set_issue_templates_detected_flag
        echo ""
      fi

      # Prompt for configuration if:
      # - Templates were never configured (templates_disabled is empty)
      # - Templates were previously disabled (templates_disabled is "true")
      # - Templates are enabled but none are detected (need to configure location)
      if [[ -z "$templates_disabled" ]] || [[ "$templates_disabled" == "true" ]] || [[ -z "$detected_templates" ]]; then
        # Ask user to configure templates
        if _aw_configure_issue_templates "$provider"; then
          use_template=true
        fi
      else
        # Templates are configured, enabled, and detected - use them
        use_template=true
      fi
    elif [[ "$templates_disabled" != "true" ]] && [[ "$flag_no_template" != true ]]; then
      # no_prompt is true, but templates are enabled - use them silently if available
      local detected_templates=$(_aw_detect_issue_templates "$provider")
      if [[ -n "$detected_templates" ]]; then
        use_template=true
      fi
    fi

    # Get title/prompt
    echo ""
    gum style --foreground 6 "Enter issue title/prompt:"
    title=$(gum input --placeholder "Issue title or brief description" --width 80)

    if [[ $? -ne 0 ]] || [[ -z "$title" ]]; then
      gum style --foreground 3 "Cancelled"
      return 0
    fi

    # Check if AI is available and offer AI-assisted generation
    local use_ai=false
    local ai_output_file=""

    # Resolve AI command to check availability
    # Only resolve if not already set (to avoid re-prompting)
    if [[ -z "${AI_CMD[*]}" ]] || [[ "${AI_CMD[1]}" == "" ]]; then
      _resolve_ai_command
    fi

    if [[ -n "${AI_CMD[*]}" ]] && [[ "${AI_CMD[1]}" != "skip" ]]; then
      echo ""
      if gum confirm "Use ${AI_CMD_NAME} to help generate the issue?"; then
        use_ai=true
      fi
    fi

    # Handle template-based or simple flow
    if [[ "$use_template" == true ]]; then
      # Get available templates
      local templates=$(_aw_detect_issue_templates "$provider")

      if [[ -n "$templates" ]]; then
        # Let user choose template
        echo ""
        gum style --foreground 6 "Choose an issue template:"
        echo ""

        # Build template choices (show basenames)
        local template_choices=()
        while IFS= read -r tmpl; do
          template_choices+=("$(basename "$tmpl")")
        done <<< "$templates"

        template_choices+=("No template (simple form)")

        local choice=$(printf '%s\n' "${template_choices[@]}" | gum choose --height 10)

        if [[ $? -ne 0 ]] || [[ -z "$choice" ]]; then
          gum style --foreground 3 "Cancelled"
          return 0
        fi

        if [[ "$choice" == "No template (simple form)" ]]; then
          # Simple body input
          if [[ "$use_ai" == true ]]; then
            # Use AI to generate content without template
            ai_output_file=$(_aw_ai_generate_issue_content "$title" "" "")
            if [[ -n "$ai_output_file" ]] && [[ -f "$ai_output_file" ]]; then
              # Let user review and edit the AI-generated content
              echo ""
              gum style --foreground 6 "AI-generated content (review and edit if needed):"
              gum style --foreground 8 "Ctrl+D when done, Ctrl+C to cancel"
              echo ""
              body=$(cat "$ai_output_file" | gum write --width 80 --height 20)
              if [[ $? -ne 0 ]]; then
                rm "$ai_output_file"
                gum style --foreground 3 "Issue creation cancelled"
                return 0
              fi
              rm "$ai_output_file"
            else
              # Fall back to manual input
              echo ""
              gum style --foreground 6 "Enter issue description:"
              gum style --foreground 8 "Ctrl+D to finish, Ctrl+C to cancel"
              echo ""
              body=$(gum write --width 80 --height 15)
              if [[ $? -ne 0 ]]; then
                gum style --foreground 3 "Issue creation cancelled"
                return 0
              fi
            fi
          else
            echo ""
            gum style --foreground 6 "Enter issue description:"
            gum style --foreground 8 "Ctrl+D to finish, Ctrl+C to cancel"
            echo ""
            body=$(gum write --width 80 --height 15)
            if [[ $? -ne 0 ]]; then
              gum style --foreground 3 "Issue creation cancelled"
              return 0
            fi
          fi
        else
          # Find the selected template file
          template_file=$(echo "$templates" | grep "/${choice}$")

          if [[ -f "$template_file" ]]; then
            # Choose how to fill out the template
            if [[ "$use_ai" == true ]]; then
              # AI is available - offer AI generation
              ai_output_file=$(_aw_ai_generate_issue_content "$title" "$template_file")
              if [[ -n "$ai_output_file" ]] && [[ -f "$ai_output_file" ]]; then
                # Let user review and edit AI-generated content
                echo ""
                gum style --foreground 6 "AI-generated content (review and edit if needed):"
                gum style --foreground 8 "Ctrl+D when done, Ctrl+C to cancel"
                echo ""
                body=$(cat "$ai_output_file" | gum write --width 80 --height 20 --char-limit 0)
                if [[ $? -ne 0 ]]; then
                  rm "$ai_output_file"
                  gum style --foreground 3 "Issue creation cancelled"
                  return 0
                fi
                rm "$ai_output_file"
              else
                # AI failed, fall back to section-by-section
                echo ""
                gum style --foreground 3 "AI generation failed, using section-by-section"
                body=$(_aw_fill_template_section_by_section "$template_file" "$title")
                if [[ $? -ne 0 ]]; then
                  gum style --foreground 3 "Issue creation cancelled"
                  return 0
                fi
              fi
            else
              # No AI - offer section-by-section or full edit
              echo ""
              if gum confirm "Fill out template section-by-section? (Recommended)"; then
                body=$(_aw_fill_template_section_by_section "$template_file" "$title")
                if [[ $? -ne 0 ]]; then
                  gum style --foreground 3 "Issue creation cancelled"
                  return 0
                fi
              else
                # Let user edit the whole template at once
                body=$(_aw_manual_template_walkthrough "$template_file")
                if [[ $? -ne 0 ]]; then
                  gum style --foreground 3 "Issue creation cancelled"
                  return 0
                fi
              fi
            fi
          else
            gum style --foreground 1 "Error: Template file not found"
            return 1
          fi
        fi
      else
        # No templates found, fall back to simple input
        if [[ "$use_ai" == true ]]; then
          # Use AI without template
          ai_output_file=$(_aw_ai_generate_issue_content "$title" "" "")
          if [[ -n "$ai_output_file" ]] && [[ -f "$ai_output_file" ]]; then
            echo ""
            gum style --foreground 6 "AI-generated content (review and edit if needed):"
            gum style --foreground 8 "Ctrl+D when done, Ctrl+C to cancel"
            echo ""
            body=$(cat "$ai_output_file" | gum write --width 80 --height 20)
            if [[ $? -ne 0 ]]; then
              rm "$ai_output_file"
              gum style --foreground 3 "Issue creation cancelled"
              return 0
            fi
            rm "$ai_output_file"
          else
            echo ""
            gum style --foreground 6 "Enter issue description:"
            gum style --foreground 8 "Ctrl+D to finish, Ctrl+C to cancel"
            echo ""
            body=$(gum write --width 80 --height 15)
            if [[ $? -ne 0 ]]; then
              gum style --foreground 3 "Issue creation cancelled"
              return 0
            fi
          fi
        else
          echo ""
          gum style --foreground 6 "Enter issue description:"
          gum style --foreground 8 "Ctrl+D to finish"
          echo ""
          body=$(gum write --width 80 --height 15)
          if [[ $? -ne 0 ]]; then
            gum style --foreground 3 "Issue creation cancelled"
            return 0
          fi
        fi
      fi
    else
      # Simple title/body input (no templates)
      if [[ "$use_ai" == true ]]; then
        # Use AI without template
        ai_output_file=$(_aw_ai_generate_issue_content "$title" "" "")
        if [[ -n "$ai_output_file" ]] && [[ -f "$ai_output_file" ]]; then
          echo ""
          gum style --foreground 6 "AI-generated content (review and edit if needed):"
          gum style --foreground 8 "Ctrl+D when done, Ctrl+C to cancel"
          echo ""
          body=$(cat "$ai_output_file" | gum write --width 80 --height 20)
          if [[ $? -ne 0 ]]; then
            rm "$ai_output_file"
            gum style --foreground 3 "Issue creation cancelled"
            return 0
          fi
          rm "$ai_output_file"
        else
          echo ""
          gum style --foreground 6 "Enter issue description:"
          gum style --foreground 8 "Ctrl+D to finish"
          echo ""
          body=$(gum write --width 80 --height 15)
          if [[ $? -ne 0 ]]; then
            gum style --foreground 3 "Issue creation cancelled"
            return 0
          fi
        fi
      else
        echo ""
        gum style --foreground 6 "Enter issue description:"
        gum style --foreground 8 "Ctrl+D to finish"
        echo ""
        body=$(gum write --width 80 --height 15)
        if [[ $? -ne 0 ]]; then
          gum style --foreground 3 "Issue creation cancelled"
          return 0
        fi
      fi
    fi
  fi

  # Show preview and confirm before creating the issue
  echo ""
  gum style --foreground 6 --bold "Issue Preview:"
  echo ""
  gum style --foreground 4 "Title: $title"
  echo ""
  gum style --foreground 8 "Body:"
  echo "$body" | head -20
  if [[ $(echo "$body" | wc -l) -gt 20 ]]; then
    echo ""
    gum style --foreground 8 "(... truncated, full content will be included in issue)"
  fi
  echo ""

  # Confirm before creating
  if ! gum confirm "Create this issue?"; then
    gum style --foreground 3 "Issue creation cancelled"
    return 0
  fi

  # Create the issue
  echo ""
  gum style --foreground 6 "Creating issue..."
  echo ""

  local result=""
  case "$provider" in
    github)
      result=$(_aw_create_issue_github "$title" "$body")
      ;;
    gitlab)
      result=$(_aw_create_issue_gitlab "$title" "$body")
      ;;
    jira)
      result=$(_aw_create_issue_jira "$title" "$body")
      ;;
    linear)
      result=$(_aw_create_issue_linear "$title" "$body")
      ;;
    *)
      gum style --foreground 1 "Error: Unknown provider: $provider"
      return 1
      ;;
  esac

  if [[ $? -ne 0 ]]; then
    return 1
  fi

  # Post-creation options
  if [[ "$flag_no_worktree" != true ]]; then
    echo ""
    if gum confirm "Create worktree for this issue?"; then
      # Extract issue ID from result
      local issue_id=""
      if [[ "$provider" == "github" ]] || [[ "$provider" == "gitlab" ]]; then
        issue_id=$(echo "$result" | grep -oE '#[0-9]+' | tr -d '#' | head -1)
        if [[ -z "$issue_id" ]]; then
          issue_id=$(echo "$result" | grep -oE '/[0-9]+$' | tr -d '/' | head -1)
        fi
      elif [[ "$provider" == "jira" ]] || [[ "$provider" == "linear" ]]; then
        issue_id=$(echo "$result" | grep -oE '[A-Z]+-[0-9]+' | head -1)
      fi

      if [[ -n "$issue_id" ]]; then
        _aw_issue "$issue_id"
      else
        gum style --foreground 3 "Could not extract issue ID from result"
      fi
    fi
  fi

  # Offer to create another issue
  if [[ "$flag_no_worktree" != true ]]; then
    echo ""
    if gum confirm "Create another issue?"; then
      # shellcheck disable=SC2119
      _aw_create_issue
    fi
  fi

  return 0
}

