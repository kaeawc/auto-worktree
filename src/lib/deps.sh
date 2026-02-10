#!/bin/bash

# ============================================================================
# Dependencies check
# ============================================================================

_aw_check_deps() {
  local missing=()

  if ! command -v gum &> /dev/null; then
    missing+=("gum (install with: brew install gum)")
  fi

  if ! command -v jq &> /dev/null; then
    missing+=("jq (install with: brew install jq)")
  fi

  # Note: gh and jira are optional based on project configuration
  # We'll check for them when needed based on the issue provider setting

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing required dependencies:"
    for dep in "${missing[@]}"; do
      echo "  - $dep"
    done
    return 1
  fi

  return 0
}

_aw_check_issue_provider_deps() {
  # Check for issue provider specific dependencies
  local provider="$1"

  case "$provider" in
    "github")
      if ! command -v gh &> /dev/null; then
        gum style --foreground 1 "Error: GitHub CLI (gh) is required for GitHub issue integration"
        echo "Install with: brew install gh"
        return 1
      fi
      ;;
    "gitlab")
      if ! command -v glab &> /dev/null; then
        gum style --foreground 1 "Error: GitLab CLI (glab) is required for GitLab issue integration"
        echo ""
        echo "Install with:"
        echo "  • macOS:     brew install glab"
        echo "  • Linux:     See https://gitlab.com/gitlab-org/cli#installation"
        echo "  • Windows:   scoop install glab"
        echo ""
        echo "After installation, authenticate with GitLab:"
        echo "  glab auth login"
        return 1
      fi
      ;;
    "jira")
      if ! command -v jira &> /dev/null; then
        gum style --foreground 1 "Error: JIRA CLI is required for JIRA issue integration"
        echo ""
        echo "Install with:"
        echo "  • macOS:     brew install ankitpokhrel/jira-cli/jira-cli"
        echo "  • Linux:     See https://github.com/ankitpokhrel/jira-cli#installation"
        echo "  • Docker:    docker pull ghcr.io/ankitpokhrel/jira-cli:latest"
        echo ""
        echo "After installation, configure JIRA:"
        echo "  jira init"
        return 1
      fi
      ;;
    "linear")
      if ! command -v linear &> /dev/null; then
        gum style --foreground 1 "Error: Linear CLI is required for Linear issue integration"
        echo ""
        echo "Install with:"
        echo "  • macOS:     brew install schpet/tap/linear"
        echo "  • Deno:      deno install -A --reload -f -g -n linear jsr:@schpet/linear-cli"
        echo "  • Other:     See https://github.com/schpet/linear-cli#installation"
        echo ""
        echo "After installation, configure Linear:"
        echo "  1. Create an API key at https://linear.app/settings/account/security"
        echo "  2. Set environment variable: export LINEAR_API_KEY=your_key_here"
        return 1
      fi
      ;;
  esac

  return 0
}
