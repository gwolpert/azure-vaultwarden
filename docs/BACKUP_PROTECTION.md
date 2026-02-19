# Backup Protection Setup

This document explains how to enable backup protection for the Vaultwarden file share.

## Overview

Azure Backup protection for file shares can be configured in two ways:
1. **Automatic (Bicep)**: Enabled during the main Bicep deployment (default)
2. **Manual (Azure CLI)**: Enabled after deployment using a script (fallback)

## Problem

When enabling backup protection via Bicep, you may encounter this error:

```
SourceResourceId must be a fully qualified ARM Id of source storage account. None. 
(Code: BMSUserErrorInvalidSourceResourceId)
```

This error occurs due to:
- Timing issues between storage account creation and backup registration
- Azure Backup API requirements that may not be fully compatible with ARM/Bicep deployment
- Resource ID format expectations that differ between Bicep and Azure CLI

## Solution 1: Automatic Bicep Deployment (Default)

By default, the Bicep template attempts to enable backup protection automatically during deployment.

**Improvements made:**
- Pass the fully qualified storage account resource ID from the storage module
- Ensure proper dependency chain between modules
- Use resource outputs instead of reconstructing IDs

**To use this method:**

Deploy normally - backup protection is enabled by default:

```bash
az deployment sub create \
  --name vaultwarden-deployment \
  --location eastus \
  --template-file bicep/main.bicep \
  --parameters resourceGroupName="vaultwarden-dev"
```

## Solution 2: Manual Azure CLI Script (Fallback)

If the Bicep deployment fails with the `BMSUserErrorInvalidSourceResourceId` error, use the Azure CLI script to enable backup protection after the main deployment completes.

### Step 1: Deploy without backup protection

Disable automatic backup protection during deployment:

```bash
az deployment sub create \
  --name vaultwarden-deployment \
  --location eastus \
  --template-file bicep/main.bicep \
  --parameters \
    resourceGroupName="vaultwarden-dev" \
    enableBackupProtection=false
```

Or if using GitHub Actions, set the environment variable:
```
ENABLE_BACKUP_PROTECTION=false
```

### Step 2: Run the backup protection script

After the deployment completes successfully, run the script:

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

## Why Use the Azure CLI Script?

The Azure CLI approach is more reliable because:
1. **Timing Control**: Script waits for resources to be fully ready
2. **Better Error Handling**: Azure CLI provides clearer error messages
3. **Proven Method**: Azure CLI backup commands are well-tested and stable
4. **Flexibility**: Easy to retry or troubleshoot if issues occur
5. **No Deployment Failure**: Main deployment succeeds even if backup setup needs attention

## Backup Configuration

Both methods configure backup with the same settings:
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
