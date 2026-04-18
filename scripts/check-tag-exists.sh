#!/bin/bash
set -euo pipefail

# Checks whether a git tag already exists for the given version.
# Expects the following environment variables:
#   VERSION_TAG     — the tag to check (e.g. "v0.1.0")
#   GH_TOKEN        — GitHub token for API calls
#   GITHUB_REPOSITORY — owner/repo (set automatically by GitHub Actions)
#   GITHUB_OUTPUT     — output file path (set automatically by GitHub Actions)

if gh api "repos/${GITHUB_REPOSITORY}/git/ref/tags/${VERSION_TAG}" >/dev/null 2>&1; then
  echo "exists=true" >> "$GITHUB_OUTPUT"
  echo "Tag ${VERSION_TAG} already exists, skipping release"
else
  echo "exists=false" >> "$GITHUB_OUTPUT"
fi
