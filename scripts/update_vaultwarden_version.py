"""Update the vaultwardenImageTag default value in bicep/main.bicep.

Replaces the current version string with the latest version and verifies
the replacement was applied successfully.

Expected env vars:
    CURRENT_VERSION: The current version string to replace
    LATEST_VERSION: The new version string to set
"""

import os
import sys


def main():
    current_version = os.environ["CURRENT_VERSION"]
    latest_version = os.environ["LATEST_VERSION"]

    bicep_path = "bicep/main.bicep"

    with open(bicep_path, "r") as f:
        content = f.read()

    old = f"param vaultwardenImageTag string = '{current_version}'"
    new = f"param vaultwardenImageTag string = '{latest_version}'"
    content = content.replace(old, new)

    with open(bicep_path, "w") as f:
        f.write(content)

    # Verify the replacement
    with open(bicep_path, "r") as f:
        verify = f.read()

    if new not in verify:
        print(
            f"::error::Replacement failed — vaultwardenImageTag was not updated "
            f"to {latest_version} in bicep/main.bicep"
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
