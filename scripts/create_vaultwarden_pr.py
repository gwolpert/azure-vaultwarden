"""Create a pull request to bump the Vaultwarden image tag.

Creates a branch, commits the updated bicep/main.bicep, and opens a PR
with formatted release notes and a checklist.

Expected env vars:
    GH_TOKEN: GitHub token for API access
    CURRENT_VERSION: The current version being replaced
    LATEST_VERSION: The new version being set
    RELEASE_URL: URL to the upstream release page
"""

import os
import subprocess
import sys


def run(cmd, **kwargs):
    """Run a command, raising on failure."""
    subprocess.run(cmd, check=True, **kwargs)


def main():
    latest_version = os.environ["LATEST_VERSION"]
    current_version = os.environ["CURRENT_VERSION"]
    release_url = os.environ["RELEASE_URL"]

    branch_name = f"automated/vaultwarden-{latest_version}"

    run(["git", "config", "user.name", "github-actions[bot]"])
    run(["git", "config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com"])
    run(["git", "checkout", "-b", branch_name])
    run(["git", "add", "bicep/main.bicep"])
    run(["git", "commit", "-m", f"chore: bump vaultwarden image tag to {latest_version}"])

    # Delete remote branch if it already exists
    result = subprocess.run(
        ["git", "ls-remote", "--exit-code", "--heads", "origin", branch_name],
        capture_output=True,
    )
    if result.returncode == 0:
        run(["git", "push", "origin", "--delete", branch_name])

    run(["git", "push", "--set-upstream", "origin", branch_name])

    # Read release body
    release_body = ""
    try:
        with open("release_body.md", "r") as f:
            release_body = f.read()
    except FileNotFoundError:
        pass

    pr_body = f"""\
## Description

Automated update of the Vaultwarden container image tag from `{current_version}` to `{latest_version}`.

## Upstream Release

**Release**: [v{latest_version}]({release_url})

<details>
<summary>Release Notes</summary>

{release_body}

</details>

## Changes

- Updated `vaultwardenImageTag` default value in `bicep/main.bicep` from `{current_version}` to `{latest_version}`

## Checklist

- [ ] I have tested my changes locally (e.g., ran `python validate.py`)
- [ ] I have updated documentation if needed
- [x] My changes follow the existing code style
"""

    pr_body_path = "pr_body.md"
    with open(pr_body_path, "w") as f:
        f.write(pr_body)

    run([
        "gh", "pr", "create",
        "--title", f"chore: bump vaultwarden to {latest_version}",
        "--body-file", pr_body_path,
        "--label", "dependencies",
        "--base", "main",
    ])

    # Clean up temp files
    for path in ("pr_body.md", "release_body.md"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


if __name__ == "__main__":
    main()
