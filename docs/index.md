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

- [Architecture Overview]({% link ARCHITECTURE.md %}) — Architecture, security, scaling, and cost details
- [Backup and Recovery]({% link BACKUP_PROTECTION.md %}) — PostgreSQL backup and restore procedures
- [Testing Guide]({% link TESTING.md %}) — Post-deployment verification procedures
- [Quick Reference]({% link QUICK_REFERENCE.md %}) — Common commands for day-to-day operations

## Deployment Methods

### 1. One-Click Deploy (Quick Start)
- Uses the ARM template compiled from Bicep and hosted on this site
- Best for quick testing, demos, and personal use
- Deploy with the button above or via Azure Portal

### 2. Azure CLI with Bicep (Recommended for Production)
- Uses `bicep/main.bicep` with Azure Verified Modules
- Best for production, scripted/repeatable deployments
- See the [GitHub repository](https://github.com/gwolpert/azure-vaultwarden) README for the `az deployment group create` command and full parameter list

## Source Code

Visit the [GitHub repository](https://github.com/gwolpert/azure-vaultwarden) for the full source code, Bicep templates, and contribution guidelines.
