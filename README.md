# Azure Vaultwarden Deployment

This repository contains Bicep templates for deploying [Vaultwarden](https://github.com/dani-garcia/vaultwarden) (an unofficial Bitwarden-compatible server) on Azure App Service with all necessary supporting infrastructure.

**Deployment is performed with the Azure CLI or the published ARM template** (e.g. via the "Deploy to Azure" button) for simple, reproducible infrastructure rollouts.

## Quick Deploy

Deploy directly to Azure with one click:

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fgwolpert.github.io%2Fazure-vaultwarden%2Farm%2Fmain.json)
[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3A%2F%2Fgwolpert.github.io%2Fazure-vaultwarden%2Farm%2Fmain.json)

**Note:** The "Deploy to Azure" button uses the ARM template compiled from Bicep and hosted on [GitHub Pages](https://gwolpert.github.io/azure-vaultwarden/). The template is automatically compiled from `bicep/main.bicep` and published to GitHub Pages.

## Deployment Methods

This repository supports two deployment approaches:

### 1. One-Click Deploy (Quick Start)
- **File:** ARM template compiled from Bicep (hosted on [GitHub Pages](https://gwolpert.github.io/azure-vaultwarden/arm/main.json))
- **Best for:** Quick testing, demos, personal use
- Deploy with the button above or via Azure Portal
- Template is automatically compiled from `bicep/main.bicep` and published to GitHub Pages

### 2. Azure CLI with Bicep (Recommended for Production)
- **Files:** `bicep/main.bicep` (using Azure Verified Modules)
- **Best for:** Production, scripted/repeatable deployments
- Full control over parameters, naming, and per-environment configuration
- Uses the Azure Verified Modules and follows Azure best practices

## Documentation

Full documentation is available on [GitHub Pages](https://gwolpert.github.io/azure-vaultwarden/).

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
- **Storage Account**: StorageV2 account hosting an Azure Files share for persistent Vaultwarden data (attachments and Send files). Provisioned with **geo-redundant storage (GRS)** — data is replicated to the Azure paired region for disaster recovery. The public endpoint is **disabled** (`publicNetworkAccess: 'Disabled'`); the App Service reaches the file share over the VNet through a private endpoint in the dedicated `private-endpoints-snet` subnet, with name resolution via the linked `privatelink.file.${environment().suffixes.storage}` private DNS zone. Diagnostic metrics flow to Log Analytics. The container mounts the share at `/data` so that both `ATTACHMENTS_FOLDER` (`/data/attachments`) and `SENDS_FOLDER` (`/data/sends`) are persisted to durable storage. `USER_ATTACHMENT_LIMIT` is set to 1000 MiB per user, `ORG_ATTACHMENT_LIMIT` is set to 250 GiB per organization, and `USER_SEND_LIMIT` is set to 100 MiB per user. The file share quota defaults to 250 GB.

## Prerequisites

- Azure subscription
- Azure CLI installed ([Install guide](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli))
- Bicep CLI installed (comes with Azure CLI 2.20.0+)
- Appropriate permissions to create resources in your Azure subscription (including the `Microsoft.DBforPostgreSQL` resource provider registered)
- An identity with **Contributor** and **User Access Administrator** roles (or **Owner**, which includes both) on the target subscription. The User Access Administrator role is required because the deployment grants the App Service's managed identity access to Key Vault secrets.

## Quick Start

### Deploy with Azure CLI

```bash
# Login to Azure
az login
az account set --subscription "<your-subscription-id>"

# Create the target resource group (skip if it already exists)
az group create --name vaultwarden-dev-rg --location northeurope

# Deploy
az deployment group create \
  --name vaultwarden-deployment \
  --resource-group vaultwarden-dev-rg \
  --template-file bicep/main.bicep \
  --parameters \
    domainName="" \
    adminToken="" \
    postgresqlAdminPassword="<your-secure-password>" \
    signupsAllowed=false \
    vaultwardenImageTag="1.35.7"
```

> Vaultwarden image tags are pinned to a specific version. Bump only after reviewing the upstream release notes at [vaultwarden/releases](https://github.com/dani-garcia/vaultwarden/releases).

### Deploy with the ARM Template ("Deploy to Azure" button)

Click the **Deploy to Azure** button at the top of this README to deploy the published ARM template through the Azure Portal. The portal asks you to pick (or create) the **subscription** and **resource group** — the deployment region is inherited from the resource group, so there is no separate `location` parameter. The remaining template parameters are the same ones documented in `bicep/main.bicep` (`baseName`, `postgresqlAdminPassword`, `domainName`, `adminToken`, `signupsAllowed`, `vaultwardenImageTag`, `appServicePlanSkuName`, the VNet/subnet CIDRs, and `adminAllowedIpAddresses`). Only `postgresqlAdminPassword` is required.

### Access Your Vaultwarden Instance

After deployment completes:
1. Note the `vaultwardenUrl` value from the deployment outputs (visible in the CLI output or the Azure Portal deployment view)
2. Visit the URL in your browser

## Configuration

All deployment inputs are passed as parameters to the Bicep/ARM template. The `postgresqlAdminPassword` parameter is required for database authentication. See `bicep/main.bicep` for the full list of available parameters and their descriptions.

## Security

- **Admin panel** is disabled by default. Enable it by providing an `adminToken` parameter and redeploying.
- **Admin token hashing**: The `adminToken` is automatically hashed using **argon2id** during Bicep deployment before being stored in Azure Key Vault. This ensures the plaintext token is never persisted — only the PHC-format hash is stored. This works across all deployment methods (Deploy to Azure button and Azure CLI).
- **User signups** are disabled by default. Enable via the `signupsAllowed` parameter.
- **HTTPS** is enforced automatically with Azure-managed certificates.
- **Secrets** are stored in Azure Key Vault, accessed via managed identity.
- **PostgreSQL** is VNet-integrated with private access only (no public endpoint).
- **Network Security Groups** lock the VNet down: only inbound `TCP/443` from the internet is allowed to the App Service subnet, and only `TCP/5432` from the App Service subnet is allowed to the PostgreSQL subnet.
- **Customisable VNet address range**: `vnetAddressPrefix`, `appServiceSubnetAddressPrefix`, `postgresqlSubnetAddressPrefix`, and `privateEndpointsSubnetAddressPrefix` parameters let you avoid conflicts when peering with other networks.
- **Key Vault network isolation**: the vault has `publicNetworkAccess: 'Disabled'` and is reached exclusively over the VNet through a private endpoint in the dedicated `private-endpoints-snet` subnet. Name resolution is provided by the linked `privatelink.vaultcore.azure.net` private DNS zone, which is what App Service Key Vault references (`DATABASE_URL`, `ADMIN_TOKEN`) use to resolve the vault to its private IP at runtime. The previous `Microsoft.KeyVault` service endpoint + `virtualNetworkRules` allow-list is no longer required and has been removed.
- **Key Vault monitoring**: audit and policy evaluation logs plus all metrics are sent to the Log Analytics workspace.
- **PostgreSQL monitoring**: server, query, and audit logs (`allLogs` category group) plus all metrics are sent to the Log Analytics workspace.
- **Pinned Vaultwarden version**: the default `vaultwardenImageTag` is pinned to a specific upstream release (`1.35.7`) instead of `latest`. Update only after reading the [release notes](https://github.com/dani-garcia/vaultwarden/releases).
- **Admin / SCM (Kudu) IP allow-list**: `adminAllowedIpAddresses` restricts the App Service management surface (Kudu / SCM site) to a list of operator CIDRs.
  - **Limitation:** Azure App Service on Linux does **not** support per-URL-path IP restrictions (the `path` field is not part of the `IpSecurityRestriction` ARM schema as of API `2024-11-01`). The Vaultwarden `/admin` web route therefore relies on the argon2id-hashed `ADMIN_TOKEN`. For per-path IP restrictions, front the App Service with Azure Front Door + WAF and apply path-scoped rules there.

See [Architecture Overview](docs/ARCHITECTURE.md) for full security details.

## Backup and Recovery

Azure Database for PostgreSQL Flexible Server is provisioned with **geo-redundant automated backups** and a **35-day retention period**. Backups are replicated to the Azure paired region so the database can be restored to a different geography for disaster-recovery scenarios. No additional backup configuration is required.

> **Note:** geo-redundant backup is set at server creation time and cannot be toggled on an existing PostgreSQL Flexible Server — changing this on an already-deployed environment requires recreating the server (and migrating data).

See [Architecture Overview](docs/ARCHITECTURE.md) for full details on backup and restore procedures.

## Updating Vaultwarden

1. Update the `vaultwardenImageTag` parameter to the desired upstream release
2. Re-run the deployment (Azure CLI or the Deploy to Azure button)

## Cleanup

**Important:** Always backup your data before deleting resources.

```bash
az group delete --name vaultwarden-dev-rg --yes --no-wait
```

## Cost Estimation

Approximate monthly costs (North Europe region, B1 default):

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
