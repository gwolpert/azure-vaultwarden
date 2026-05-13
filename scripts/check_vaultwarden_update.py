"""Check for new Vaultwarden releases upstream.

Compares the latest release from dani-garcia/vaultwarden with the current
version pinned in bicep/main.bicep. If an update is available and no PR
already exists, outputs release metadata for downstream steps.

Expected env vars:
    GH_TOKEN: GitHub token for API access
    GITHUB_OUTPUT: Path to GitHub Actions output file
    GITHUB_REPOSITORY: Owner/repo string (e.g. 'user/repo')
"""

import os
import re
import subprocess
import sys


def run(cmd, **kwargs):
    """Run a command and return its stdout, raising on failure."""
    result = subprocess.run(cmd, capture_output=True, text=True, check=True, **kwargs)
    return result.stdout.strip()


def append_output(name, value):
    """Append a key=value pair to the GITHUB_OUTPUT file."""
    output_file = os.environ["GITHUB_OUTPUT"]
    with open(output_file, "a") as f:
        f.write(f"{name}={value}\n")


def main():
    # Get latest release tag from upstream
    latest_release = run(
        ["gh", "api", "repos/dani-garcia/vaultwarden/releases/latest", "--jq", ".tag_name"]
    )
    latest_version = latest_release.lstrip("v")

    # Extract current version from bicep/main.bicep
    with open("bicep/main.bicep", "r") as f:
        content = f.read()

    match = re.search(r"param vaultwardenImageTag string = '([^']+)'", content)
    if not match:
        print("::error::Failed to extract current vaultwardenImageTag from bicep/main.bicep")
        sys.exit(1)

    current_version = match.group(1)

    append_output("current", current_version)
    append_output("latest", latest_version)

    if current_version == latest_version:
        append_output("update_available", "false")
        print(f"Already on latest version ({current_version}). No update needed.")
    else:
        # Check for existing PR
        github_repository = os.environ["GITHUB_REPOSITORY"]
        existing_pr = subprocess.run(
            [
                "gh", "pr", "list",
                "--repo", github_repository,
                "--head", f"automated/vaultwarden-{latest_version}",
                "--json", "number",
                "--jq", ".[0].number // empty",
            ],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()

        if existing_pr:
            append_output("update_available", "false")
            print(f"PR #{existing_pr} already exists for version {latest_version}. Skipping.")
        else:
            append_output("update_available", "true")
            print(f"New version available: {current_version} -> {latest_version}")

            release_url = run(
                ["gh", "api", "repos/dani-garcia/vaultwarden/releases/latest", "--jq", ".html_url"]
            )
            release_body = run(
                ["gh", "api", "repos/dani-garcia/vaultwarden/releases/latest", "--jq", ".body"]
            )

            append_output("release_url", release_url)

            with open("release_body.md", "w") as f:
                f.write(release_body)


if __name__ == "__main__":
    main()
