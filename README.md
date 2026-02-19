# Azure Vaultwarden Deployment

This repository contains Bicep templates for deploying [Vaultwarden](https://github.com/dani-garcia/vaultwarden) (an unofficial Bitwarden-compatible server) on Azure App Service with all necessary supporting infrastructure.

**Deployment is managed through GitHub Actions with GitHub Environments** for secure and reproducible deployments across dev, staging, and production environments.

## Quick Deploy

Deploy directly to Azure with one click using the latest release:

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fgithub.com%2Fgwolpert%2Fazure-vaultwarden%2Freleases%2Flatest%2Fdownload%2Fmain.json)
[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3A%2F%2Fgithub.com%2Fgwolpert%2Fazure-vaultwarden%2Freleases%2Flatest%2Fdownload%2Fmain.json)

**Note:** The "Deploy to Azure" button uses the ARM template compiled from Bicep and published in releases. For production deployments, we recommend using GitHub Actions with the Bicep templates and Azure Verified Modules.

## Deployment Methods

This repository supports two deployment approaches:

### 1. One-Click Deploy (Quick Start)
- **File:** ARM template compiled from Bicep (available in releases)
- **Best for:** Quick testing, demos, personal use
- Uses direct Azure resource definitions
- Deploy with the button above or via Azure Portal
- Template is automatically compiled from `bicep/main.bicep` on each release

### 2. GitHub Actions with Bicep (Recommended for Production)
- **Files:** `bicep/main.bicep` (using Azure Verified Modules)
- **Best for:** Production, team environments, CI/CD
- Environment-specific configurations
- Approval workflows for production
- More maintainable and follows Azure best practices
- See [GitHub Setup Guide](docs/GITHUB_SETUP.md) for details

## Documentation

- **[GitHub Setup Guide](docs/GITHUB_SETUP.md)** - GitHub Environments, secrets, and variables configuration
- **[Architecture Overview](docs/ARCHITECTURE.md)** - Architecture, security, scaling, and cost details
- **[Backup Protection Setup](docs/BACKUP_PROTECTION.md)** - Backup setup and restore procedures
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
- **Virtual Network**: Isolated network with dedicated subnet for App Service VNet integration
- **Storage Account**: Azure Files storage for persistent Vaultwarden data (with CanNotDelete lock)
- **Recovery Services Vault**: Backup vault for automated daily backups of Vaultwarden data
- **Backup Policy**: Daily backup schedule with 30-day retention for file share protection
- **Log Analytics Workspace**: Monitoring and logging
- **App Service Plan**: B1 (Basic) Linux plan with VNet integration (upgradable to Standard/Premium for auto-scaling and deployment slots)
- **App Service**: Web App for Containers running Vaultwarden
- **Key Vault**: Secure storage for secrets (admin token)

## Prerequisites

- Azure subscription
- Azure CLI installed ([Install guide](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli))
- Bicep CLI installed (comes with Azure CLI 2.20.0+)
- Appropriate permissions to create resources in your Azure subscription
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
    signupsAllowed=false \
    vaultwardenImageTag="latest"
```

## Configuration

Parameters are configured through GitHub Environment Variables and Secrets. See [GITHUB_SETUP.md](docs/GITHUB_SETUP.md) for complete configuration details including secrets, variables, and per-environment settings.

## Security

- **Admin panel** is disabled by default. Enable it by setting the `ADMIN_TOKEN` secret and redeploying.
- **User signups** are disabled by default. Enable via the `SIGNUPS_ALLOWED` variable.
- **HTTPS** is enforced automatically with Azure-managed certificates.
- **Secrets** are stored in Azure Key Vault, accessed via managed identity.
- **Storage** is secured with Private Endpoint (public access disabled) and a CanNotDelete lock.

See [Architecture Overview](docs/ARCHITECTURE.md) for full security details.

## Backup and Recovery

The deployment creates a Recovery Services Vault with daily backups at 2:00 AM UTC and 30-day retention.

- **GitHub Actions**: Backup protection is enabled automatically during deployment.
- **Manual deployments**: Run `./enable-backup-protection.sh` after deployment.

See [Backup Protection Setup](docs/BACKUP_PROTECTION.md) for detailed instructions, restore procedures, and troubleshooting.

## Updating Vaultwarden

1. Update the `VAULTWARDEN_IMAGE_TAG` variable in your GitHub Environment
2. Run the "Deploy Vaultwarden to Azure" workflow
3. Select the environment to update

## Cleanup

**Important:** Always backup your data before deleting resources.

```bash
az group delete --name vaultwarden-dev-rg --yes --no-wait
```

## Creating Releases

To create a new release with the compiled ARM template:

### Automatic Release (Recommended)

1. Create and push a new tag:
   ```bash
   git tag -a v1.0.0 -m "Release v1.0.0"
   git push origin v1.0.0
   ```

2. The `release.yml` workflow will automatically:
   - Compile `bicep/main.bicep` to `main.json`
   - Generate `main.parameters.json` and `metadata.json`
   - Create a GitHub release with these files attached
   - Update the Deploy to Azure button to use the new release

### Manual Release

1. Go to Actions > "Create Release with ARM Template"
2. Click "Run workflow"
3. Enter the release tag (e.g., `v1.0.0`)
4. Click "Run workflow"

The ARM template is compiled from the Bicep source, ensuring consistency between deployment methods.

## Cost Estimation

Approximate monthly costs (East US region, B1 default):

| Resource | Estimated Cost |
|----------|---------------|
| App Service Plan (B1) | ~$13-15 |
| Storage Account | ~$2-5 |
| Recovery Services Vault + Backup | ~$5-10 |
| Log Analytics | ~$2-10 |
| Virtual Network | Free |
| Key Vault | < $1 |
| **Total** | **~$22-41/month** |

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
