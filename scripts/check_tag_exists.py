"""Check whether a git tag already exists for a given version.

Queries the GitHub API and outputs exists=true or exists=false
to GITHUB_OUTPUT.

Expected env vars:
    GH_TOKEN: GitHub token for API access
    GITHUB_OUTPUT: Path to GitHub Actions output file
    GITHUB_REPOSITORY: Owner/repo string (e.g. 'user/repo')
    VERSION_TAG: The tag to check (e.g. 'v1.0.0')
"""

import os
import subprocess


def main():
    github_repository = os.environ["GITHUB_REPOSITORY"]
    version_tag = os.environ["VERSION_TAG"]
    output_file = os.environ["GITHUB_OUTPUT"]

    result = subprocess.run(
        ["gh", "api", f"repos/{github_repository}/git/ref/tags/{version_tag}"],
        capture_output=True,
    )

    with open(output_file, "a") as f:
        if result.returncode == 0:
            f.write("exists=true\n")
            print(f"Tag {version_tag} already exists, skipping release")
        else:
            f.write("exists=false\n")


if __name__ == "__main__":
    main()
