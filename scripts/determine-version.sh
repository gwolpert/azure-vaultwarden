#!/bin/bash
set -euo pipefail

# Determines the final semantic version by checking PR labels.
# Expects the following environment variables:
#   GITVERSION_MAJOR, GITVERSION_MINOR, GITVERSION_PATCH — base version from GitVersion
#   GH_TOKEN        — GitHub token for API calls
#   GITHUB_REPOSITORY — owner/repo (set automatically by GitHub Actions)
#   GITHUB_OUTPUT     — output file path (set automatically by GitHub Actions)

FINAL_MAJOR=$GITVERSION_MAJOR
FINAL_MINOR=$GITVERSION_MINOR
FINAL_PATCH=$GITVERSION_PATCH

# Find the PR associated with the current commit using the GitHub API
COMMIT_SHA=$(git rev-parse HEAD)
PR_NUMBER=$(gh api "repos/${GITHUB_REPOSITORY}/commits/${COMMIT_SHA}/pulls" \
  --jq '.[0].number' 2>/dev/null || echo "")

if [ -n "$PR_NUMBER" ] && [ "$PR_NUMBER" != "null" ]; then
  echo "Found PR #${PR_NUMBER}, checking labels..."
  LABELS=$(gh pr view "$PR_NUMBER" --json labels --jq '.labels[].name' 2>/dev/null || echo "")

  if echo "$LABELS" | grep -q "version:major"; then
    echo "Major version bump requested via PR label"
    FINAL_MAJOR=$((GITVERSION_MAJOR + 1))
    FINAL_MINOR=0
    FINAL_PATCH=0
  elif echo "$LABELS" | grep -q "version:minor"; then
    echo "Minor version bump requested via PR label"
    FINAL_MINOR=$((GITVERSION_MINOR + 1))
    FINAL_PATCH=0
  else
    echo "No version bump label found, using default patch bump"
  fi
else
  echo "No associated PR found for commit ${COMMIT_SHA}, using GitVersion calculated version"
fi

SEMVER="${FINAL_MAJOR}.${FINAL_MINOR}.${FINAL_PATCH}"
echo "Calculated version: ${SEMVER}"
echo "semVer=${SEMVER}" >> "$GITHUB_OUTPUT"
