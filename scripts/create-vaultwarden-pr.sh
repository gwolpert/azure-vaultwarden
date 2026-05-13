#!/bin/bash
set -euo pipefail

# Creates a pull request to bump the Vaultwarden image tag.
# Expects the following environment variables:
#   GH_TOKEN          — GitHub token for API calls
#   CURRENT_VERSION   — the previously pinned version string
#   LATEST_VERSION    — the new version to set
#   RELEASE_URL       — URL to the upstream release page

BRANCH_NAME="automated/vaultwarden-${LATEST_VERSION}"

# Configure git
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

# Create branch and commit
git checkout -b "$BRANCH_NAME"
git add bicep/main.bicep
git commit -m "chore: bump vaultwarden image tag to ${LATEST_VERSION}"

# Delete stale remote branch if it exists (e.g., from a previously closed PR)
if git ls-remote --exit-code --heads origin "$BRANCH_NAME" >/dev/null 2>&1; then
  git push origin --delete "$BRANCH_NAME"
fi
git push --set-upstream origin "$BRANCH_NAME"

# Build PR body
{
  echo "## Description"
  echo ""
  echo "Automated update of the Vaultwarden container image tag from \`${CURRENT_VERSION}\` to \`${LATEST_VERSION}\`."
  echo ""
  echo "## Upstream Release"
  echo ""
  echo "**Release**: [v${LATEST_VERSION}](${RELEASE_URL})"
  echo ""
  echo "<details>"
  echo "<summary>Release Notes</summary>"
  echo ""
  cat /tmp/release_body.md
  echo ""
  echo "</details>"
  echo ""
  echo "## Changes"
  echo ""
  echo "- Updated \`vaultwardenImageTag\` default value in \`bicep/main.bicep\` from \`${CURRENT_VERSION}\` to \`${LATEST_VERSION}\`"
  echo ""
  echo "## Checklist"
  echo ""
  echo "- [ ] I have tested my changes locally (e.g., ran \`./validate.sh\`)"
  echo "- [ ] I have updated documentation if needed"
  echo "- [x] My changes follow the existing code style"
} >/tmp/pr_body.md

# Create pull request
gh pr create \
  --title "chore: bump vaultwarden to ${LATEST_VERSION}" \
  --body-file /tmp/pr_body.md \
  --label "dependencies" \
  --base main
