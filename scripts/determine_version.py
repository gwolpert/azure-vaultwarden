"""Determine the final semantic version from GitVersion and PR labels.

Uses the GitVersion-calculated major/minor/patch as a baseline, then checks
the associated PR for version:major or version:minor labels to bump
accordingly.

Expected env vars:
    GH_TOKEN: GitHub token for API access
    GITHUB_OUTPUT: Path to GitHub Actions output file
    GITHUB_REPOSITORY: Owner/repo string (e.g. 'user/repo')
    GITVERSION_MAJOR: Major version from GitVersion
    GITVERSION_MINOR: Minor version from GitVersion
    GITVERSION_PATCH: Patch version from GitVersion
"""

import os
import subprocess


def main():
    final_major = int(os.environ["GITVERSION_MAJOR"])
    final_minor = int(os.environ["GITVERSION_MINOR"])
    final_patch = int(os.environ["GITVERSION_PATCH"])
    github_repository = os.environ["GITHUB_REPOSITORY"]
    output_file = os.environ["GITHUB_OUTPUT"]

    commit_sha = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()

    # Find associated PR
    pr_result = subprocess.run(
        ["gh", "api", f"repos/{github_repository}/commits/{commit_sha}/pulls",
         "--jq", ".[0].number"],
        capture_output=True, text=True,
    )
    pr_number = pr_result.stdout.strip() if pr_result.returncode == 0 else ""

    if pr_number and pr_number != "null":
        print(f"Found PR #{pr_number}, checking labels...")

        labels_result = subprocess.run(
            ["gh", "pr", "view", pr_number, "--json", "labels", "--jq", ".labels[].name"],
            capture_output=True, text=True,
        )
        labels = labels_result.stdout if labels_result.returncode == 0 else ""

        if "version:major" in labels:
            print("Major version bump requested via PR label")
            final_major = int(os.environ["GITVERSION_MAJOR"]) + 1
            final_minor = 0
            final_patch = 0
        elif "version:minor" in labels:
            print("Minor version bump requested via PR label")
            final_minor = int(os.environ["GITVERSION_MINOR"]) + 1
            final_patch = 0
        else:
            print("No version bump label found, using default patch bump")
    else:
        print(f"No associated PR found for commit {commit_sha}, using GitVersion calculated version")

    semver = f"{final_major}.{final_minor}.{final_patch}"
    print(f"Calculated version: {semver}")

    with open(output_file, "a") as f:
        f.write(f"semVer={semver}\n")


if __name__ == "__main__":
    main()
