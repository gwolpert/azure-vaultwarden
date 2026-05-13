#!/bin/bash
set -euo pipefail

# Updates the vaultwardenImageTag default value in bicep/main.bicep.
# Expects the following environment variables:
#   CURRENT_VERSION — the currently pinned version string
#   LATEST_VERSION  — the new version to set

# Update the default version in bicep/main.bicep
sed -i "s/param vaultwardenImageTag string = '${CURRENT_VERSION}'/param vaultwardenImageTag string = '${LATEST_VERSION}'/" bicep/main.bicep

# Verify the change was actually applied
if ! grep -q "param vaultwardenImageTag string = '${LATEST_VERSION}'" bicep/main.bicep; then
  echo "::error::sed replacement failed — vaultwardenImageTag was not updated to ${LATEST_VERSION} in bicep/main.bicep"
  exit 1
fi
