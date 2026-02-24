---
layout: default
title: Home
---

# Azure Vaultwarden

Deploy [Vaultwarden](https://github.com/dani-garcia/vaultwarden) (an unofficial Bitwarden-compatible server) on Azure App Service with all necessary supporting infrastructure.

## Quick Deploy

Deploy directly to Azure with one click:

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fgwolpert.github.io%2Fazure-vaultwarden%2Farm%2Fmain.json)
[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3A%2F%2Fgwolpert.github.io%2Fazure-vaultwarden%2Farm%2Fmain.json)

## Documentation

- [GitHub Setup Guide]({% link GITHUB_SETUP.md %}) — GitHub Environments, secrets, and variables configuration
- [Architecture Overview]({% link ARCHITECTURE.md %}) — Architecture, security, scaling, and cost details
- [Backup Protection Setup]({% link BACKUP_PROTECTION.md %}) — Backup setup and restore procedures
- [Testing Guide]({% link TESTING.md %}) — Post-deployment verification procedures
- [Quick Reference]({% link QUICK_REFERENCE.md %}) — Common commands for day-to-day operations

## Deployment Methods

### 1. One-Click Deploy (Quick Start)
- Uses the ARM template compiled from Bicep and hosted on this site
- Best for quick testing, demos, and personal use
- Deploy with the button above or via Azure Portal

### 2. GitHub Actions with Bicep (Recommended for Production)
- Uses `bicep/main.bicep` with Azure Verified Modules
- Best for production, team environments, and CI/CD
- Environment-specific configurations and approval workflows
- See [GitHub Setup Guide]({% link GITHUB_SETUP.md %}) for details

## Source Code

Visit the [GitHub repository](https://github.com/gwolpert/azure-vaultwarden) for the full source code, Bicep templates, and contribution guidelines.
