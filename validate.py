"""Vaultwarden Deployment Validation Script.

Validates the repository structure, Bicep templates, GitHub workflows,
documentation, Azure resource providers, and existing deployments.

Expected env vars: None required (Azure CLI login optional for full checks).
Usage: python validate.py [resource_group_name]
"""

import os
import re
import shutil
import subprocess
import sys

# --- Color support ---

_use_color = (
    sys.platform != "win32"
    or os.environ.get("TERM") not in (None, "", "dumb")
    or "WT_SESSION" in os.environ
)

RED = "\033[0;31m" if _use_color else ""
GREEN = "\033[0;32m" if _use_color else ""
YELLOW = "\033[1;33m" if _use_color else ""
BLUE = "\033[0;34m" if _use_color else ""
NC = "\033[0m" if _use_color else ""

# --- Counters ---

pass_count = 0
fail_count = 0
warn_count = 0


def print_header(title):
    print(f"\n{BLUE}=== {title} ==={NC}")


def print_pass(msg):
    global pass_count
    print(f"{GREEN}✓{NC} {msg}")
    pass_count += 1


def print_fail(msg):
    global fail_count
    print(f"{RED}✗{NC} {msg}")
    fail_count += 1


def print_warn(msg):
    global warn_count
    print(f"{YELLOW}⚠{NC} {msg}")
    warn_count += 1


def print_info(msg):
    print(f"{BLUE}ℹ{NC} {msg}")


def _run_quiet(cmd):
    """Run a command silently, returning (returncode, stdout, stderr)."""
    r = subprocess.run(cmd, capture_output=True, text=True)
    return r.returncode, r.stdout.strip(), r.stderr.strip()


def _has_cmd(name):
    return shutil.which(name) is not None


def _az_logged_in():
    rc, _, _ = _run_quiet(["az", "account", "show"])
    return rc == 0


# --- Checks ---


def check_prerequisites():
    print_header("Checking Prerequisites")

    # Azure CLI
    if _has_cmd("az"):
        rc, out, _ = _run_quiet(["az", "version", "--query", '"azure-cli"', "-o", "tsv"])
        print_pass(f"Azure CLI installed (version {out})" if rc == 0 else "Azure CLI installed")
    else:
        print_fail("Azure CLI is not installed")
        print("  Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli")

    # Bicep
    if _has_cmd("az"):
        rc, out, _ = _run_quiet(["az", "bicep", "version"])
        if rc == 0:
            m = re.search(r"Bicep CLI version (\S+)", out + _run_quiet(["az", "bicep", "version"])[1])
            ver = m.group(1) if m else "unknown"
            print_pass(f"Bicep CLI available (version {ver})")
        else:
            print_warn("Bicep CLI is not available (will be installed automatically if needed)")
            print("  Or install manually with: az bicep install")

    # Azure login
    if _has_cmd("az") and _az_logged_in():
        rc, name, _ = _run_quiet(["az", "account", "show", "--query", "name", "-o", "tsv"])
        rc2, sub_id, _ = _run_quiet(["az", "account", "show", "--query", "id", "-o", "tsv"])
        print_pass("Logged in to Azure")
        print_info(f"  Subscription: {name}")
        print_info(f"  ID: {sub_id}")
    elif _has_cmd("az"):
        print_warn("Not logged in to Azure (run 'az login' to check Azure-specific validations)")

    # Git
    if _has_cmd("git"):
        rc, out, _ = _run_quiet(["git", "--version"])
        m = re.search(r"git version (\S+)", out)
        ver = m.group(1) if m else "unknown"
        print_pass(f"Git installed (version {ver})")
    else:
        print_warn("Git is not installed (optional for local development)")


def check_bicep_template():
    print_header("Checking Bicep Template")

    if not os.path.isfile("bicep/main.bicep"):
        print_fail("Main Bicep template not found at bicep/main.bicep")
        return

    print_pass("Main Bicep template exists")

    if _has_cmd("az"):
        rc_bv, _, _ = _run_quiet(["az", "bicep", "version"])
        if rc_bv == 0:
            print_info("Validating Bicep template with Azure CLI...")

            r = subprocess.run(
                ["az", "bicep", "build", "--file", "bicep/main.bicep", "--stdout"],
                capture_output=True, text=True,
            )
            bicep_output = r.stdout + r.stderr

            # Filter warnings (exclude network errors)
            warning_lines = [
                line for line in bicep_output.splitlines()
                if "warning" in line.lower() and "BCP192" not in line and "Unable to restore" not in line
            ]

            if r.returncode == 0:
                print_pass("Bicep template validation passed")
            elif "BCP192" in bicep_output:
                print_warn("Bicep template has network dependencies (expected without internet access)")
                print_info("  Template syntax appears valid, but modules cannot be downloaded")
            else:
                print_fail("Bicep template validation failed")
                for line in bicep_output.splitlines()[:20]:
                    print(line)

            if warning_lines:
                print_warn("Bicep linter warnings found:")
                for line in warning_lines:
                    print(line)
            else:
                print_pass("No linter warnings found")
        else:
            print_warn("Azure CLI or Bicep not available, skipping proper validation")
            print_info("  Install Azure CLI and run 'az bicep install' for full validation")

            with open("bicep/main.bicep", "r") as f:
                content = f.read()
            if (
                "targetScope = 'resourceGroup'" in content
                and "param " in content
                and "module " in content
            ):
                print_pass("Bicep template has valid structure (basic check)")
            else:
                print_warn("Bicep template structure may be incomplete")
    else:
        print_warn("Azure CLI or Bicep not available, skipping proper validation")
        print_info("  Install Azure CLI and run 'az bicep install' for full validation")

    # Check for AVM usage
    found_avm = False
    for root, _dirs, files in os.walk("bicep"):
        for fname in files:
            fpath = os.path.join(root, fname)
            try:
                with open(fpath, "r") as f:
                    if "br/public:avm" in f.read():
                        found_avm = True
                        break
            except (OSError, UnicodeDecodeError):
                pass
        if found_avm:
            break

    if found_avm:
        print_pass("Uses Azure Verified Modules (AVM)")
    else:
        print_warn("Does not use Azure Verified Modules")


def check_github_workflows():
    print_header("Checking GitHub Workflows")

    if os.path.isfile(".github/workflows/validate-bicep.yml"):
        print_pass("Bicep validation workflow exists")
    else:
        print_warn("Bicep validation workflow not found")

    if os.path.isfile(".github/workflows/pages.yml"):
        print_pass("GitHub Pages workflow exists (publishes ARM template for one-click deploy)")
    else:
        print_warn("GitHub Pages workflow not found")


def check_documentation():
    print_header("Checking Documentation")

    docs = [
        "README.md",
        "docs/ARCHITECTURE.md",
        "docs/BACKUP_PROTECTION.md",
        "docs/TESTING.md",
        "docs/QUICK_REFERENCE.md",
    ]
    for doc in docs:
        if os.path.isfile(doc):
            print_pass(f"{doc} exists")
        else:
            print_warn(f"{doc} not found")


def check_file_structure():
    print_header("Checking File Structure")

    required = ["bicep/main.bicep", "README.md"]
    for f in required:
        if os.path.isfile(f):
            print_pass(f"{f} exists")
        else:
            print_fail(f"{f} is missing")

    optional = [".gitignore"]
    for f in optional:
        if os.path.isfile(f):
            print_pass(f"{f} exists")
        else:
            print_warn(f"{f} not found (optional)")


def check_azure_providers():
    print_header("Checking Azure Resource Providers")

    if not _has_cmd("az") or not _az_logged_in():
        print_warn("Not logged in to Azure, skipping provider check")
        return

    providers = [
        "Microsoft.Web",
        "Microsoft.OperationalInsights",
        "Microsoft.DBforPostgreSQL",
        "Microsoft.Network",
        "Microsoft.KeyVault",
    ]
    for provider in providers:
        rc, status, _ = _run_quiet(
            ["az", "provider", "show", "--namespace", provider, "--query", "registrationState", "-o", "tsv"]
        )
        if rc != 0:
            status = "Unknown"

        if status == "Registered":
            print_pass(f"{provider} is registered")
        elif status == "Registering":
            print_warn(f"{provider} is registering (in progress)")
        else:
            print_warn(f"{provider} is not registered")
            print(f"  Register with: az provider register --namespace {provider}")


def check_existing_deployment(rg_name="vaultwarden-dev-rg"):
    print_header("Checking for Existing Deployment")

    if not _has_cmd("az") or not _az_logged_in():
        print_warn("Not logged in to Azure, skipping deployment check")
        return

    rc, exists_out, _ = _run_quiet(["az", "group", "exists", "--name", rg_name])
    if "true" not in exists_out:
        print_info(f"No deployment found at '{rg_name}'")
        return

    print_info(f"Resource group '{rg_name}' exists")

    rc, app_name, _ = _run_quiet(
        ["az", "webapp", "list", "--resource-group", rg_name, "--query", "[0].name", "-o", "tsv"]
    )
    if rc == 0 and app_name:
        print_info(f"  App Service: {app_name}")
        rc2, hostname, _ = _run_quiet(
            ["az", "webapp", "show", "--name", app_name, "--resource-group", rg_name,
             "--query", "defaultHostName", "-o", "tsv"]
        )
        if rc2 == 0 and hostname:
            print_info(f"  URL: https://{hostname}")
    else:
        print_info("  No app services found")


def print_summary():
    print_header("Validation Summary")

    print(f"Passed:   {GREEN}{pass_count}{NC}")
    print(f"Failed:   {RED}{fail_count}{NC}")
    print(f"Warnings: {YELLOW}{warn_count}{NC}")
    print()

    if fail_count == 0:
        print_pass("All critical checks passed! ✨")
        print()
        print("Next steps:")
        print("1. Review parameters in bicep/main.bicep")
        print("2. Deploy with Azure CLI (az deployment group create) or the Deploy to Azure button")
        return 0
    else:
        print_fail("Some critical checks failed. Please fix the issues above.")
        return 1


def main():
    print("======================================")
    print("Vaultwarden Deployment Validation")
    print("======================================")

    if not os.path.isfile("bicep/main.bicep") and not os.path.isfile("../bicep/main.bicep"):
        print_fail("Not in repository root directory")
        print("Please run this script from the repository root")
        sys.exit(1)

    rg_name = sys.argv[1] if len(sys.argv) > 1 else "vaultwarden-dev-rg"

    check_prerequisites()
    check_file_structure()
    check_bicep_template()
    check_github_workflows()
    check_documentation()
    check_azure_providers()
    check_existing_deployment(rg_name)

    result = print_summary()
    sys.exit(result)


if __name__ == "__main__":
    main()
