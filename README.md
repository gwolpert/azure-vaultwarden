# Azure Vaultwarden Deployment

This repository contains Bicep templates for deploying [Vaultwarden](https://github.com/dani-garcia/vaultwarden) (an unofficial Bitwarden-compatible server) on Azure App Service with all necessary supporting infrastructure.

**Deployment is managed through GitHub Actions with GitHub Environments** for secure and reproducible deployments across dev, staging, and production environments.

## Quick Deploy

Deploy directly to Azure with one click:

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fgwolpert.github.io%2Fazure-vaultwarden%2Farm%2Fmain.json)
[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3A%2F%2Fgwolpert.github.io%2Fazure-vaultwarden%2Farm%2Fmain.json)

**Note:** The "Deploy to Azure" button uses the ARM template compiled from Bicep and hosted on [GitHub Pages](https://gwolpert.github.io/azure-vaultwarden/). For production deployments, we recommend using GitHub Actions with the Bicep templates and Azure Verified Modules.

## Deployment Methods

This repository supports two deployment approaches:

### 1. One-Click Deploy (Quick Start)
- **File:** ARM template compiled from Bicep (hosted on [GitHub Pages](https://gwolpert.github.io/azure-vaultwarden/arm/main.json))
- **Best for:** Quick testing, demos, personal use
- Uses direct Azure resource definitions
- Deploy with the button above or via Azure Portal
- Template is automatically compiled from `bicep/main.bicep` and published to GitHub Pages

### 2. GitHub Actions with Bicep (Recommended for Production)
- **Files:** `bicep/main.bicep` (using Azure Verified Modules)
- **Best for:** Production, team environments, CI/CD
- Environment-specific configurations
- Approval workflows for production
- More maintainable and follows Azure best practices
- See [GitHub Setup Guide](docs/GITHUB_SETUP.md) for details

## Documentation

Full documentation is available on [GitHub Pages](https://gwolpert.github.io/azure-vaultwarden/).

- **[GitHub Setup Guide](docs/GITHUB_SETUP.md)** - GitHub Environments, secrets, and variables configuration
- **[Architecture Overview](docs/ARCHITECTURE.md)** - Architecture, security, scaling, and cost details
- **[Backup and Recovery](docs/BACKUP_PROTECTION.md)** - PostgreSQL backup and restore procedures
- **[Testing Guide](docs/TESTING.md)** - Post-deployment verification procedures
- **[Quick Reference](docs/QUICK_REFERENCE.md)** - Common commands for day-to-day operations

## Validation

Before deploying, run the validation script to check your setup:

```bash
./validate.sh
```

This will check:
- Prerequisites (Azure CLI, Bicep, Git)
- File structure and Bicep templates
- GitHub workflow configuration
- Documentation completeness
- Azure resource providers (if logged in)

## Architecture

The deployment creates the following Azure resources:

- **Resource Group**: Container for all resources
- **Virtual Network**: Isolated network with dedicated subnets for App Service and PostgreSQL VNet integration
- **Azure Database for PostgreSQL Flexible Server**: Burstable B1MS with VNet integration for persistent Vaultwarden data
- **Log Analytics Workspace**: Monitoring and logging
- **App Service Plan**: B1 (Basic) Linux plan with VNet integration (upgradable to Standard/Premium for auto-scaling and deployment slots)
- **App Service**: Web App for Containers running Vaultwarden
- **Key Vault**: Secure storage for secrets (admin token, database connection string)

## Prerequisites

- Azure subscription
- Azure CLI installed ([Install guide](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli))
- Bicep CLI installed (comes with Azure CLI 2.20.0+)
- Appropriate permissions to create resources in your Azure subscription (including the `Microsoft.DBforPostgreSQL` resource provider registered)
- Service principal with **Contributor** and **User Access Administrator** roles (for GitHub Actions deployment) or **Owner** role (which includes both)

## Quick Start

### Deployment Method: GitHub Actions (Recommended)

This repository uses GitHub Actions with GitHub Environments for deployment. This approach provides:
- Environment-specific configuration management
- Secure secrets handling
- Approval workflows for production
- Deployment history and rollback capabilities

### 1. Set Up GitHub Environments

Follow the detailed guide in [GITHUB_SETUP.md](docs/GITHUB_SETUP.md) to:
1. Create Azure service principal
2. Configure GitHub Environments (dev, staging, prod)
3. Set up secrets and variables for each environment

### 2. Deploy via GitHub Actions

#### Option A: Manual Deployment
1. Go to your repository's "Actions" tab
2. Select "Deploy Vaultwarden to Azure" workflow
3. Click "Run workflow"
4. Select the environment (dev/staging/prod)
5. Click "Run workflow"

#### Option B: Automatic Deployment
Push changes to the `main` branch:
```bash
git add .
git commit -m "Update configuration"
git push origin main
```

The workflow automatically deploys to the `dev` environment.

### 3. Access Your Vaultwarden Instance

After deployment completes:
1. Check the GitHub Actions workflow summary
2. Find the "Vaultwarden URL" in the deployment outputs
3. Visit the URL in your browser

### Alternative: Manual Deployment via Azure CLI

If you prefer not to use GitHub Actions, you can deploy manually:

```bash
# Login to Azure
az login
az account set --subscription "<your-subscription-id>"

# Deploy
az deployment sub create \
  --name vaultwarden-deployment \
  --location westeurope \
  --template-file bicep/main.bicep \
  --parameters \
    resourceGroupName="vaultwarden-dev" \
    location="westeurope" \
    environmentName="dev" \
    domainName="" \
    adminToken="" \
    postgresqlAdminPassword="<your-secure-password>" \
    signupsAllowed=false \
    vaultwardenImageTag="latest"
```

## Configuration

Parameters are configured through GitHub Environment Variables and Secrets. The `POSTGRESQL_ADMIN_PASSWORD` secret is required for database authentication. See [GITHUB_SETUP.md](docs/GITHUB_SETUP.md) for complete configuration details including secrets, variables, and per-environment settings.

## Security

- **Admin panel** is disabled by default. Enable it by setting the `ADMIN_TOKEN` secret and redeploying.
- **Admin token hashing**: The `ADMIN_TOKEN` is automatically hashed using **argon2id** during Bicep deployment before being stored in Azure Key Vault. This ensures the plaintext token is never persisted — only the PHC-format hash is stored. This works across all deployment methods (GitHub Actions, Deploy to Azure button, and Azure CLI).
- **User signups** are disabled by default. Enable via the `SIGNUPS_ALLOWED` variable.
- **HTTPS** is enforced automatically with Azure-managed certificates.
- **Secrets** are stored in Azure Key Vault, accessed via managed identity.
- **PostgreSQL** is VNet-integrated with private access only (no public endpoint).

See [Architecture Overview](docs/ARCHITECTURE.md) for full security details.

## Backup and Recovery

Azure Database for PostgreSQL Flexible Server includes built-in automated backups with 7-day retention. No additional backup configuration is required.

See [Architecture Overview](docs/ARCHITECTURE.md) for full details on backup and restore procedures.

## Updating Vaultwarden

1. Update the `VAULTWARDEN_IMAGE_TAG` variable in your GitHub Environment
2. Run the "Deploy Vaultwarden to Azure" workflow
3. Select the environment to update

## Cleanup

**Important:** Always backup your data before deleting resources.

```bash
az group delete --name vaultwarden-dev-rg --yes --no-wait
```

## Cost Estimation

Approximate monthly costs (West Europe region, B1 default):

| Resource | Estimated Cost |
|----------|---------------|
| App Service Plan (B1) | ~$13-15 |
| PostgreSQL Flexible Server (B1MS) | ~$12-15 |
| Log Analytics | ~$2-10 |
| Virtual Network | Free |
| Key Vault | < $1 |
| Private DNS Zone | < $1 |
| **Total** | **~$28-42/month** |

See [Architecture Overview](docs/ARCHITECTURE.md) for upgrade options and detailed cost breakdown.

## Support and Contributing

For issues with:
- **Vaultwarden**: See [Vaultwarden GitHub](https://github.com/dani-garcia/vaultwarden)
- **Azure Resources**: See [Azure Documentation](https://docs.microsoft.com/azure/)
- **This Deployment**: Open an issue in this repository

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

This project is licensed under the [MIT License](LICENSE). Vaultwarden itself is licensed under the [GNU Affero General Public License v3.0](https://github.com/dani-garcia/vaultwarden/blob/main/LICENSE.txt).

## Additional Resources

- [Vaultwarden Wiki](https://github.com/dani-garcia/vaultwarden/wiki)
- [Azure App Service Documentation](https://docs.microsoft.com/azure/app-service/)
- [Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/)
