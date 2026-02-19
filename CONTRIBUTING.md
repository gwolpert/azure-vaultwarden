# Contributing to Azure Vaultwarden

Thank you for your interest in contributing! This guide will help you get started.

## How to Contribute

### Reporting Bugs

If you find a bug, please [open an issue](https://github.com/gwolpert/azure-vaultwarden/issues/new?template=bug_report.md) and include:

- A clear description of the problem
- Steps to reproduce the issue
- Expected vs actual behavior
- Your environment details (OS, Azure CLI version, etc.)

### Suggesting Features

Feature requests are welcome! Please [open an issue](https://github.com/gwolpert/azure-vaultwarden/issues/new?template=feature_request.md) describing the feature and why it would be useful.

### Submitting Changes

1. **Fork** the repository
2. **Create a branch** from `main` for your changes
3. **Make your changes** — keep them focused and minimal
4. **Test your changes** by running the validation script:
   ```bash
   ./validate.sh
   ```
5. **Submit a pull request** with a clear description of what you changed and why

### What to Work On

- Check the [open issues](https://github.com/gwolpert/azure-vaultwarden/issues) for things that need attention
- Issues labeled `good first issue` are a great place to start
- If you want to work on something, comment on the issue to let others know

## Development Setup

### Prerequisites

- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) (2.20.0+)
- [Bicep CLI](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install) (included with Azure CLI)
- A text editor with Bicep support (VS Code with the Bicep extension is recommended)

### Validation

Before submitting a PR, run the validation script:

```bash
./validate.sh
```

This checks Bicep templates, file structure, and workflow configuration.

## Guidelines

- **Keep changes small** — smaller PRs are easier to review and merge
- **Follow existing patterns** — match the style and conventions already in the codebase
- **Update documentation** if your change affects how users deploy or configure the project
- **One concern per PR** — avoid mixing unrelated changes

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## Questions?

If you have questions, feel free to [open an issue](https://github.com/gwolpert/azure-vaultwarden/issues) and we'll be happy to help.
