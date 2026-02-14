# Azure Vaultwarden Deployment

This repository contains Bicep templates for deploying [Vaultwarden](https://github.com/dani-garcia/vaultwarden) (an unofficial Bitwarden-compatible server) on Azure Container Apps with all necessary supporting infrastructure.

**Deployment is managed through GitHub Actions with GitHub Environments** for secure and reproducible deployments across dev, staging, and production environments.

## Documentation

- **[Quick Start & README](README.md)** - This file (deployment overview)
- **[GitHub Setup Guide](GITHUB_SETUP.md)** - Complete guide for setting up GitHub Environments and Actions
- **[Architecture Overview](ARCHITECTURE.md)** - Detailed architecture, security, and operational guide
- **[Testing Guide](TESTING.md)** - Comprehensive testing and verification procedures

## Architecture

The deployment creates the following Azure resources:

- **Resource Group**: Container for all resources
- **Virtual Network**: Isolated network with dedicated subnet for Container Apps
- **Storage Account**: Azure Files storage for persistent Vaultwarden data
- **Log Analytics Workspace**: Monitoring and logging
- **Container App Environment**: Managed environment for container apps
- **Container App**: Vaultwarden application container

## Prerequisites

- Azure subscription
- Azure CLI installed ([Install guide](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli))
- Bicep CLI installed (comes with Azure CLI 2.20.0+)
- Appropriate permissions to create resources in your Azure subscription

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
    resourceGroupName="rg-vaultwarden-dev" \
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
| `RESOURCE_GROUP_NAME` | Name of the resource group | `rg-vaultwarden-dev` | `rg-vaultwarden-prod` |
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

1. Update the `domainName` parameter in `main.parameters.json`:
   ```json
   "domainName": {
     "value": "https://vault.example.com"
   }
   ```

2. After deployment, get the Container App's FQDN:
   ```bash
   az containerapp show \
     --name vw-dev-app \
     --resource-group rg-vaultwarden-dev \
     --query properties.configuration.ingress.fqdn \
     --output tsv
   ```

3. Create a CNAME record in your DNS pointing to this FQDN

4. Add custom domain to Container App:
   ```bash
   az containerapp hostname add \
     --hostname vault.example.com \
     --resource-group rg-vaultwarden-dev \
     --name vw-dev-app
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
     --parameters resourceGroupName="rg-vaultwarden-dev" \
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
  --parameters resourceGroupName="rg-vaultwarden-dev" \
  --parameters location="eastus" \
  --parameters environmentName="dev"
```

### HTTPS

The Container App automatically provides HTTPS with Azure-managed certificates. For custom domains, you can:
- Let Azure manage the certificate (free)
- Upload your own certificate

## Data Persistence

Vaultwarden data is stored in an Azure File Share mounted to the container at `/data`. This includes:
- SQLite database (with WAL mode enabled for better performance on network storage)
- Attachments
- Icons cache

The data persists across container restarts and updates.

## Monitoring and Logs

### View Container Logs

```bash
az containerapp logs show \
  --name vw-dev-app \
  --resource-group rg-vaultwarden-dev \
  --follow
```

### View in Log Analytics

```bash
# Get Log Analytics Workspace ID
az monitor log-analytics workspace show \
  --resource-group rg-vaultwarden-dev \
  --workspace-name vw-dev-logs \
  --query customerId \
  --output tsv
```

Query logs in Azure Portal or using KQL.

## Scaling

The Container App is configured to scale between 1-3 replicas based on load. To adjust:

1. Update the `scaleMinReplicas` and `scaleMaxReplicas` parameters in `main.bicep`
2. Redeploy the template

## Backup and Recovery

### Backup Data

Download the file share content:

```bash
# Get storage account key
STORAGE_KEY=$(az storage account keys list \
  --account-name <storage-account-name> \
  --resource-group rg-vaultwarden-dev \
  --query "[0].value" \
  --output tsv)

# Download all files
az storage file download-batch \
  --destination ./backup \
  --source vaultwarden-data \
  --account-name <storage-account-name> \
  --account-key $STORAGE_KEY
```

### Restore Data

Upload files back to the file share:

```bash
az storage file upload-batch \
  --destination vaultwarden-data \
  --source ./backup \
  --account-name <storage-account-name> \
  --account-key $STORAGE_KEY
```

## Troubleshooting

### Container Not Starting

Check container logs:
```bash
az containerapp logs show \
  --name vw-dev-app \
  --resource-group rg-vaultwarden-dev \
  --tail 100
```

### Database Issues

Ensure `ENABLE_DB_WAL` is set to `true` - this is required for SQLite on network storage.

### Cannot Access Admin Panel

1. Verify admin token is set
2. Ensure you're accessing `/admin` endpoint
3. Check container logs for authentication errors

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
  --parameters resourceGroupName="rg-vaultwarden-dev" \
  --parameters location="eastus" \
  --parameters environmentName="dev"
```

The update will trigger a new container deployment with zero downtime (rolling update).

## Cleanup

To remove all deployed resources:

### Using GitHub Actions

1. Go to the "Actions" tab
2. Select "Destroy Vaultwarden Infrastructure" workflow
3. Click "Run workflow"
4. Select the environment to destroy
5. Type the environment name to confirm deletion
6. Click "Run workflow"

### Manual Cleanup

```bash
az group delete --name rg-vaultwarden-dev --yes --no-wait
```

**Warning:** This will permanently delete all data. Make sure to backup before destroying.

## Cost Estimation

Approximate monthly costs (East US region):
- Container App: ~$10-30 (depending on usage)
- Storage Account: ~$2-5 (depending on data size)
- Log Analytics: ~$2-10 (depending on log volume)
- Virtual Network: Free

Total: ~$14-45/month

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
- [Azure Container Apps Documentation](https://docs.microsoft.com/azure/container-apps/)
- [Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/)
