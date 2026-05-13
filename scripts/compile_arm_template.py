"""Compile the Bicep template into an ARM JSON template.

Creates the output directory and runs az bicep build to produce
docs/arm/main.json from bicep/main.bicep.

Expected env vars: None required.
"""

import os
import subprocess


def main():
    os.makedirs("docs/arm", exist_ok=True)
    subprocess.run(
        ["az", "bicep", "build", "--file", "bicep/main.bicep", "--outfile", "docs/arm/main.json"],
        check=True,
    )
    print("ARM template compiled successfully")


if __name__ == "__main__":
    main()
