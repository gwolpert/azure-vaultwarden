# Backup Protection Setup

This document explains how to enable backup protection for the Vaultwarden file share.

## Overview

Azure Backup protection for file shares must be configured post-deployment using Azure CLI or Portal. This is because the backup protection container registration requires the storage account to be fully provisioned and accessible, which is better handled as a post-deployment step.

## Why Post-Deployment?

Azure Backup API has strict requirements for resource IDs and timing that are not fully compatible with ARM/Bicep deployment. The backup protection container registration can fail during infrastructure-as-code deployments due to:
- Timing issues between storage account creation and backup registration
- Resource ID format expectations that differ between Bicep and Azure CLI
- Azure Backup service propagation delays

Therefore, the recommended approach is to deploy all infrastructure via Bicep, then enable backup protection using Azure CLI.

## Setup Instructions

### Step 1: Deploy Infrastructure

Deploy the Bicep template normally. This creates:
- Recovery Services Vault with backup policy
- Storage account with file share
- All other Vaultwarden infrastructure

```bash
az deployment sub create \
  --name vaultwarden-deployment \
  --location eastus \
  --template-file bicep/main.bicep \
  --parameters resourceGroupName="vaultwarden-dev"
```

### Step 2: Enable Backup Protection

After the deployment completes successfully, run the provided script:

```bash
# Login to Azure if not already logged in
az login

# Set your subscription
az account set --subscription "<your-subscription-id>"

# Run the script
./scripts/enable-backup-protection.sh \
  vaultwarden-dev-rg \
  vaultwardendevst \
  vaultwarden-dev-rsv \
  vaultwarden-data
```

**Script parameters:**
1. Resource group name (with -rg suffix): `vaultwarden-dev-rg`
2. Storage account name: `vaultwardendevst` (baseName without dashes + 'st')
3. Recovery vault name: `vaultwarden-dev-rsv` (baseName + '-rsv')
4. File share name: `vaultwarden-data`

### Step 3: Verify backup protection

Check that backup protection is enabled:

```bash
az backup item show \
  --resource-group vaultwarden-dev-rg \
  --vault-name vaultwarden-dev-rsv \
  --backup-management-type AzureStorage \
  --workload-type AzureFileShare \
  --container-name "storagecontainer;Storage;vaultwarden-dev-rg;vaultwardendevst" \
  --name "AzureFileShare;vaultwarden-data" \
  --query "properties.protectionStatus"
```

Expected output: `"Protected"`

## What the Script Does

The script automates the post-deployment backup protection setup:

1. **Validates Prerequisites**: Checks for Azure CLI and login status
2. **Validates Resources**: Ensures storage account, recovery vault, and file share exist
3. **Registers Storage Account**: Creates a backup protection container in the recovery vault
4. **Waits for Registration**: Polls for container availability (up to 2 minutes with retries)
5. **Enables Protection**: Configures backup protection for the file share using the daily backup policy
6. **Verifies Status**: Confirms that protection is active

## Why Use This Approach?

The Azure CLI post-deployment approach is more reliable because:
1. **Timing Control**: Script validates that required resources exist and polls for registration completion before proceeding
2. **Better Error Handling**: Azure CLI provides clearer error messages
3. **Proven Method**: Azure CLI backup commands are well-tested and stable
4. **Flexibility**: Easy to retry or troubleshoot if issues occur
5. **No Deployment Failure**: Main infrastructure deployment always succeeds

## Backup Configuration

The backup operates with the following settings:
- **Schedule**: Daily at 2:00 AM UTC
- **Retention**: 30 days
- **Policy**: `vaultwarden-daily-backup-policy`
- **Protected Resource**: `vaultwarden-data` file share

## Troubleshooting

### Issue: Script reports "Storage account not found"

**Solution**: Ensure you're using the correct storage account name. The name is constructed as `{baseName without dashes}st`.

Example: `vaultwarden-dev` → `vaultwardendevst`

### Issue: Script reports "Recovery vault not found"

**Solution**: Ensure you're using the correct recovery vault name. The name is constructed as `{baseName}-rsv`.

Example: `vaultwarden-dev` → `vaultwarden-dev-rsv`

### Issue: "File share is already protected" warning

**Solution**: This is not an error. The file share is already protected and backups are enabled.

### Issue: Protection status shows "Unknown"

**Solution**: Wait a few minutes and check again. Azure Backup may take time to fully activate protection after registration.

## Verifying Backups

Once backup protection is enabled, you can:

### View backup jobs

```bash
az backup job list \
  --resource-group vaultwarden-dev-rg \
  --vault-name vaultwarden-dev-rsv \
  --output table
```

### View recovery points

```bash
az backup recoverypoint list \
  --resource-group vaultwarden-dev-rg \
  --vault-name vaultwarden-dev-rsv \
  --backup-management-type AzureStorage \
  --workload-type AzureFileShare \
  --container-name "storagecontainer;Storage;vaultwarden-dev-rg;vaultwardendevst" \
  --item-name "AzureFileShare;vaultwarden-data" \
  --output table
```

### Restore from backup

```bash
# List recovery points to get the recovery point name
az backup recoverypoint list \
  --resource-group vaultwarden-dev-rg \
  --vault-name vaultwarden-dev-rsv \
  --backup-management-type AzureStorage \
  --workload-type AzureFileShare \
  --container-name "storagecontainer;Storage;vaultwarden-dev-rg;vaultwardendevst" \
  --item-name "AzureFileShare;vaultwarden-data" \
  --output table

# Restore to original location
az backup restore restore-azurefileshare \
  --resource-group vaultwarden-dev-rg \
  --vault-name vaultwarden-dev-rsv \
  --rp-name <recovery-point-name> \
  --container-name "storagecontainer;Storage;vaultwarden-dev-rg;vaultwardendevst" \
  --item-name "AzureFileShare;vaultwarden-data" \
  --resolve-conflict Overwrite
```

## Recommendation

**For production deployments**, we recommend:
1. Try the automatic Bicep deployment first (default behavior)
2. If it fails with `BMSUserErrorInvalidSourceResourceId`, redeploy with `enableBackupProtection=false`
3. Then run the Azure CLI script to enable backup protection
4. This hybrid approach ensures your deployment succeeds while still getting backup protection

## See Also

- [Azure Backup documentation](https://docs.microsoft.com/azure/backup/)
- [Azure Files backup documentation](https://docs.microsoft.com/azure/backup/backup-azure-files)
- [Recovery Services Vault documentation](https://docs.microsoft.com/azure/backup/backup-azure-recovery-services-vault-overview)
