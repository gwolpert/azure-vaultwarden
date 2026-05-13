#!/bin/bash
set -euo pipefail

# Checks whether a newer Vaultwarden release is available upstream.
# If an update is found and no PR already exists, writes release metadata
# to /tmp/release_body.md for the PR creation step.
# Expects the following environment variables:
#   GH_TOKEN            — GitHub token for API calls
#   GITHUB_REPOSITORY   — owner/repo (set automatically by GitHub Actions)
#   GITHUB_OUTPUT       — output file path (set automatically by GitHub Actions)

# Get the latest release from vaultwarden upstream
LATEST_RELEASE=$(gh api repos/dani-garcia/vaultwarden/releases/latest --jq '.tag_name')
LATEST_VERSION="${LATEST_RELEASE#v}" # Strip leading 'v' if present

# Get the currently pinned version from bicep/main.bicep
CURRENT_VERSION=$(grep -oP "param vaultwardenImageTag string = '\K[^']+" bicep/main.bicep)

if [ -z "$CURRENT_VERSION" ]; then
  echo "::error::Failed to extract current vaultwardenImageTag from bicep/main.bicep"
  exit 1
fi

echo "current=$CURRENT_VERSION" >>"$GITHUB_OUTPUT"
echo "latest=$LATEST_VERSION" >>"$GITHUB_OUTPUT"

if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
  echo "update_available=false" >>"$GITHUB_OUTPUT"
  echo "Already on latest version ($CURRENT_VERSION). No update needed."
else
  # Check if a PR already exists for this version
  EXISTING_PR=$(gh pr list --repo "$GITHUB_REPOSITORY" --head "automated/vaultwarden-${LATEST_VERSION}" --json number --jq '.[0].number // empty')
  if [ -n "$EXISTING_PR" ]; then
    echo "update_available=false" >>"$GITHUB_OUTPUT"
    echo "PR #${EXISTING_PR} already exists for version ${LATEST_VERSION}. Skipping."
  else
    echo "update_available=true" >>"$GITHUB_OUTPUT"
    echo "New version available: $CURRENT_VERSION -> $LATEST_VERSION"

    # Fetch the release body for the PR description
    RELEASE_URL=$(gh api repos/dani-garcia/vaultwarden/releases/latest --jq '.html_url')
    RELEASE_BODY=$(gh api repos/dani-garcia/vaultwarden/releases/latest --jq '.body')
    echo "release_url=$RELEASE_URL" >>"$GITHUB_OUTPUT"

    # Write multi-line release body to a file for later use
    echo "$RELEASE_BODY" >/tmp/release_body.md
  fi
fi
