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
- See [GitHub Setup Guide](GITHUB_SETUP.md) for details

## Documentation

- **[Quick Start & README](README.md)** - This file (deployment overview)
- **[GitHub Setup Guide](GITHUB_SETUP.md)** - Complete guide for setting up GitHub Environments and Actions
- **[Architecture Overview](ARCHITECTURE.md)** - Detailed architecture, security, and operational guide
- **[Testing Guide](TESTING.md)** - Comprehensive testing and verification procedures
- **[Quick Reference](QUICK_REFERENCE.md)** - Common commands and quick reference

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
- **App Service Plan**: S1 (Standard) Linux plan with VNet integration, auto-scaling, and deployment slots
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

Follow the detailed guide in [GITHUB_SETUP.md](GITHUB_SETUP.md) to:
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
  --location eastus \
  --template-file bicep/main.bicep \
  --parameters \
    resourceGroupName="vaultwarden-dev" \
    location="eastus" \
    environmentName="dev" \
    domainName="" \
    adminToken="" \
    signupsAllowed=false \
    vaultwardenImageTag="latest"
```

## Configuration Parameters

Parameters are configured through GitHub Environment Variables and Secrets (see [GITHUB_SETUP.md](GITHUB_SETUP.md)).

### Environment Secrets

| Secret Name | Description | Required |
|------------|-------------|----------|
| `AZURE_CLIENT_ID` | Azure service principal client ID | Yes |
| `AZURE_TENANT_ID` | Azure AD tenant ID | Yes |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID | Yes |
| `ADMIN_TOKEN` | Admin panel access token | No (leave empty to disable) |

### Environment Variables

| Variable Name | Description | Default | Example |
|--------------|-------------|---------|---------|
| `RESOURCE_GROUP_NAME` | Name of the resource group | `vaultwarden-dev` | `vaultwarden-prod` |
| `AZURE_LOCATION` | Azure region | `eastus` | `westeurope` |
| `ENVIRONMENT_NAME` | Environment (dev/staging/prod) | `dev` | `prod` |
| `DOMAIN_NAME` | Custom domain name | `""` (uses default) | `https://vault.example.com` |
| `SIGNUPS_ALLOWED` | Allow new user signups | `false` | `true` |
| `VAULTWARDEN_IMAGE_TAG` | Vaultwarden Docker image tag | `latest` | `1.30.1` |

### Configuration per Environment

Each GitHub Environment (dev, staging, prod) should have its own configuration:

**Development:**
- Allow signups for testing: `SIGNUPS_ALLOWED=true`
- Use latest image: `VAULTWARDEN_IMAGE_TAG=latest`
- No admin token required (or use test token)

**Staging:**
- Disable signups: `SIGNUPS_ALLOWED=false`
- Use stable version: `VAULTWARDEN_IMAGE_TAG=1.30.1`
- Optional custom domain

**Production:**
- Disable signups: `SIGNUPS_ALLOWED=false`
- Use pinned version: `VAULTWARDEN_IMAGE_TAG=1.30.1`
- Require custom domain: `DOMAIN_NAME=https://vault.example.com`
- Strong admin token required
- Enable environment protection rules

## Custom Domain Configuration

To use a custom domain:

1. Update the `DOMAIN_NAME` variable in your GitHub Environment to your custom domain (e.g., `https://vault.example.com`)

2. Redeploy via GitHub Actions, or manually:
   ```bash
   az deployment sub create \
     --name vaultwarden-deployment \
     --location eastus \
     --template-file bicep/main.bicep \
     --parameters domainName="https://vault.example.com" \
     --parameters resourceGroupName="vaultwarden-dev" \
     --parameters location="eastus" \
     --parameters environmentName="dev"
   ```

3. After deployment, get the App Service's URL:
   ```bash
   az webapp show \
     --name vaultwarden-dev-app \
     --resource-group vaultwarden-dev-rg \
     --query defaultHostName \
     --output tsv
   ```

4. Create a CNAME record in your DNS pointing to this hostname

5. Add custom domain to App Service:
   ```bash
   az webapp config hostname add \
     --hostname vault.example.com \
     --resource-group vaultwarden-dev-rg \
     --webapp-name vaultwarden-dev-app
   ```

## Security Considerations

### Admin Panel

The admin panel is disabled by default. To enable it:

1. Generate a secure admin token:
   ```bash
   openssl rand -base64 32
   ```

2. Add it to your GitHub Environment secrets as `ADMIN_TOKEN`

3. Redeploy via GitHub Actions or update manually:
   ```bash
   az deployment sub create \
     --name vaultwarden-deployment \
     --location eastus \
     --template-file bicep/main.bicep \
     --parameters adminToken="<your-secure-token>" \
     --parameters resourceGroupName="vaultwarden-dev" \
     --parameters location="eastus" \
     --parameters environmentName="dev"
   ```

4. Access admin panel at `https://<your-url>/admin`

### User Signups

By default, user signups are disabled. To allow signups:

1. Update the `SIGNUPS_ALLOWED` variable in your GitHub Environment to `true`
2. Redeploy via GitHub Actions

Or manually:
```bash
az deployment sub create \
  --name vaultwarden-deployment \
  --location eastus \
  --template-file bicep/main.bicep \
  --parameters signupsAllowed=true \
  --parameters resourceGroupName="vaultwarden-dev" \
  --parameters location="eastus" \
  --parameters environmentName="dev"
```

### HTTPS

The App Service automatically provides HTTPS with Azure-managed certificates. For custom domains, you can:
- Let Azure manage the certificate (free)
- Upload your own certificate

## Data Persistence

Vaultwarden data is stored in an Azure File Share mounted to the container at `/data`. This includes:
- SQLite database (with WAL mode enabled for better performance on network storage)
- Attachments
- Icons cache

The data persists across container restarts and updates.

## Monitoring and Logs

### View App Service Logs

```bash
az webapp log tail \
  --name vaultwarden-dev-app \
  --resource-group vaultwarden-dev-rg
```

### View in Log Analytics

```bash
# Get Log Analytics Workspace ID
az monitor log-analytics workspace show \
  --resource-group vaultwarden-dev-rg \
  --workspace-name vaultwarden-dev-log \
  --query customerId \
  --output tsv
```

Query logs in Azure Portal or using KQL.

## Scaling

The App Service can be scaled manually or automatically (auto-scaling available on Standard tier). To scale the App Service Plan:

1. Update the SKU in `main.bicep` (e.g., from S1 to S2 or P1v2)
2. Or scale manually:
   ```bash
   az appservice plan update \
     --name vaultwarden-dev-asp \
     --resource-group vaultwarden-dev-rg \
     --sku S2
   ```

3. Configure auto-scaling rules:
   ```bash
   az monitor autoscale create \
     --resource-group vaultwarden-dev-rg \
     --resource vaultwarden-dev-asp \
     --resource-type Microsoft.Web/serverFarms \
     --name autoscale-vaultwarden \
     --min-count 1 \
     --max-count 3 \
     --count 1
   ```

## Backup and Recovery

### Automated Daily Backups

The deployment automatically configures Azure Backup for the Vaultwarden file share:

- **Backup Schedule**: Daily at 2:00 AM UTC
- **Retention**: 30 days
- **Backup Location**: Recovery Services Vault in the same resource group
- **Protection**: Storage account has a CanNotDelete lock to prevent accidental deletion

The backup runs automatically and requires no manual intervention. Backups are stored in the Recovery Services Vault and can be restored through the Azure Portal or Azure CLI.

### View Backup Status

Check backup status and history:

```bash
# List backup jobs
az backup job list \
  --resource-group vaultwarden-dev-rg \
  --vault-name vaultwarden-dev-rsv \
  --output table

# Get backup item details
az backup item show \
  --resource-group vaultwarden-dev-rg \
  --vault-name vaultwarden-dev-rsv \
  --backup-management-type AzureStorage \
  --workload-type AzureFileShare \
  --name vaultwarden-data \
  --container-name <storage-account-name>
```

### Restore from Backup

Restore the file share from a backup recovery point:

```bash
# List recovery points
az backup recoverypoint list \
  --resource-group vaultwarden-dev-rg \
  --vault-name vaultwarden-dev-rsv \
  --backup-management-type AzureStorage \
  --workload-type AzureFileShare \
  --container-name <storage-container-name> \
  --item-name vaultwarden-data \
  --output table

# Restore to original location
az backup restore restore-azurefileshare \
  --resource-group vaultwarden-dev-rg \
  --vault-name vaultwarden-dev-rsv \
  --rp-name <recovery-point-name> \
  --container-name <storage-container-name> \
  --item-name vaultwarden-data \
  --resolve-conflict Overwrite
```

### Manual Backup (Alternative)

You can also manually download the file share content:

```bash
# Get storage account key
STORAGE_KEY=$(az storage account keys list \
  --account-name <storage-account-name> \
  --resource-group vaultwarden-dev-rg \
  --query "[0].value" \
  --output tsv)

# Download all files
az storage file download-batch \
  --destination ./backup \
  --source vaultwarden-data \
  --account-name <storage-account-name> \
  --account-key $STORAGE_KEY
```

### Manual Restore (Alternative)

Upload files back to the file share:

```bash
az storage file upload-batch \
  --destination vaultwarden-data \
  --source ./backup \
  --account-name <storage-account-name> \
  --account-key $STORAGE_KEY
```

### Storage Account Protection

The storage account is protected with a **CanNotDelete** resource lock, which prevents accidental deletion of the storage account and its data. To delete the storage account, you must first remove the lock:

```bash
# List locks on the storage account
az lock list \
  --resource-group vaultwarden-dev-rg \
  --resource-name <storage-account-name> \
  --resource-type Microsoft.Storage/storageAccounts

# Remove the lock (if needed)
az lock delete \
  --name storage-lock \
  --resource-group vaultwarden-dev-rg \
  --resource-name <storage-account-name> \
  --resource-type Microsoft.Storage/storageAccounts
```

## Troubleshooting

### Deployment Failed: Role Assignment Permission Error

**Error:**
```
Authorization failed for template resource of type 'Microsoft.Authorization/roleAssignments'. 
The client does not have permission to perform action 'Microsoft.Authorization/roleAssignments/write'
```

**Cause:** The service principal used for deployment doesn't have permission to create role assignments.

**Solution:** Grant the "User Access Administrator" role to your service principal:

```bash
# Get your service principal's Object ID
SP_OBJECT_ID=$(az ad sp list --display-name "github-vaultwarden-deployer" --query [0].id -o tsv)

# Verify the service principal was found
if [ -z "$SP_OBJECT_ID" ]; then
  echo "Error: Service principal 'github-vaultwarden-deployer' not found"
  echo "Please verify the name or create it first"
  exit 1
fi

echo "Found service principal with Object ID: $SP_OBJECT_ID"

# Get your subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Assign User Access Administrator role
az role assignment create \
  --assignee $SP_OBJECT_ID \
  --role "User Access Administrator" \
  --scope /subscriptions/$SUBSCRIPTION_ID
```

After assigning the role, redeploy via GitHub Actions or run the deployment again.

See [GitHub Setup Guide](GITHUB_SETUP.md) for complete service principal setup instructions.

### Container Not Starting

Check App Service logs:
```bash
az webapp log tail \
  --name vaultwarden-dev-app \
  --resource-group vaultwarden-dev-rg
```

### Database Issues

Ensure `ENABLE_DB_WAL` is set to `true` - this is required for SQLite on network storage.

### Cannot Access Admin Panel

1. Verify admin token is set
2. Ensure you're accessing `/admin` endpoint
3. Check App Service logs for authentication errors

## Updating Vaultwarden

To update to a new version:

### Using GitHub Actions

1. Update the `VAULTWARDEN_IMAGE_TAG` variable in your GitHub Environment
2. Run the "Deploy Vaultwarden to Azure" workflow
3. Select the environment to update

### Manual Update

```bash
az deployment sub create \
  --name vaultwarden-deployment \
  --location eastus \
  --template-file bicep/main.bicep \
  --parameters vaultwardenImageTag="1.30.1" \
  --parameters resourceGroupName="vaultwarden-dev" \
  --parameters location="eastus" \
  --parameters environmentName="dev"
```

The update will trigger a new container deployment with minimal downtime.

## Cleanup

To remove all deployed resources, you must manually delete them through Azure Portal or Azure CLI.

### Manual Cleanup via Azure CLI

```bash
az group delete --name vaultwarden-dev-rg --yes --no-wait
```

### Manual Cleanup via Azure Portal

1. Navigate to the Azure Portal
2. Go to Resource Groups
3. Select the Vaultwarden resource group (e.g., `vaultwarden-dev-rg`)
4. Click "Delete resource group"
5. Type the resource group name to confirm
6. Click "Delete"

**Important:** Always backup your data before deleting resources. Once deleted, all data including passwords stored in Vaultwarden will be permanently lost.

**Warning:** This will permanently delete all data. Make sure to backup before destroying.

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

Approximate monthly costs (East US region):
- App Service Plan (S1): ~$70-75
- Storage Account: ~$2-5 (depending on data size)
- Recovery Services Vault + Backup: ~$5-10 (depending on backup size and retention)
- Log Analytics: ~$2-10 (depending on log volume)
- Virtual Network: Free
- Key Vault: < $1

Total: ~$79-101/month

**Benefits of S1 over B1**:
- Full VNet integration support
- Auto-scaling capabilities
- Deployment slots for zero-downtime updates
- Better performance (1 core, 1.75 GB RAM)
- Custom domains with SSL
- Suitable for production workloads

**Backup Protection**:
- Automated daily backups with 30-day retention
- Storage account protected with CanNotDelete lock
- Point-in-time recovery capabilities

**Still more cost-effective than Container Apps** for similar features and performance.

Actual costs may vary based on usage, region, and resource configuration.

## Support and Contributing

For issues with:
- **Vaultwarden**: See [Vaultwarden GitHub](https://github.com/dani-garcia/vaultwarden)
- **Azure Resources**: See [Azure Documentation](https://docs.microsoft.com/azure/)
- **This Deployment**: Open an issue in this repository

## License

This deployment template is provided as-is. Vaultwarden is licensed under the GPL-3.0 license.

## Additional Resources

- [Vaultwarden Wiki](https://github.com/dani-garcia/vaultwarden/wiki)
- [Azure App Service Documentation](https://docs.microsoft.com/azure/app-service/)
- [Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/)
