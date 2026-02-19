# Backup Protection Setup

This document explains how to enable backup protection for the Vaultwarden file share.

## Overview

Azure Backup protection for file shares must be configured post-deployment using Azure CLI or Portal. This is because the backup protection container registration requires the storage account to be fully provisioned and accessible, which is better handled as a post-deployment step.

### Automatic Setup via GitHub Actions

When deploying via GitHub Actions, backup protection is **automatically configured** as part of the deployment workflow. No manual steps are required.

### Manual Setup

If you're deploying manually (not using GitHub Actions), follow the steps below to enable backup protection after your infrastructure deployment completes.

## Why Post-Deployment?

Azure Backup API has strict requirements for resource IDs and timing that are not fully compatible with ARM/Bicep deployment. The backup protection container registration can fail during infrastructure-as-code deployments due to:
- Timing issues between storage account creation and backup registration
- Resource ID format expectations that differ between Bicep and Azure CLI
- Azure Backup service propagation delays

Therefore, backup protection is enabled post-deployment using Azure CLI commands.

## Manual Setup Instructions

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

### Step 2: Enable Backup Protection Manually

After the deployment completes successfully, run the following commands:

#### 2.1 Register the storage account with the Recovery Services Vault

```bash
# Set variables
RESOURCE_GROUP="vaultwarden-dev-rg"
STORAGE_ACCOUNT="vaultwardendevst"
RECOVERY_VAULT="vaultwarden-dev-rsv"
FILE_SHARE="vaultwarden-data"

# Get the storage account resource ID
STORAGE_ACCOUNT_ID=$(az storage account show \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --query id \
  --output tsv)

# Register the storage account
az backup container register \
  --resource-group "$RESOURCE_GROUP" \
  --vault-name "$RECOVERY_VAULT" \
  --backup-management-type AzureStorage \
  --workload-type AzureFileShare \
  --storage-account "$STORAGE_ACCOUNT_ID"
```

**Note**: Registration may take a few minutes to propagate. Wait 1-2 minutes before proceeding to the next step.

#### 2.2 Enable protection for the file share

```bash
# Enable backup protection
az backup protection enable-for-azurefileshare \
  --resource-group "$RESOURCE_GROUP" \
  --vault-name "$RECOVERY_VAULT" \
  --policy-name "vaultwarden-daily-backup-policy" \
  --storage-account "$STORAGE_ACCOUNT" \
  --azure-file-share "$FILE_SHARE"
```

### Step 3: Verify backup protection

Check that backup protection is enabled:

```bash
az backup item show \
  --resource-group "$RESOURCE_GROUP" \
  --vault-name "$RECOVERY_VAULT" \
  --backup-management-type AzureStorage \
  --workload-type AzureFileShare \
  --container-name "storagecontainer;Storage;${RESOURCE_GROUP};${STORAGE_ACCOUNT}" \
  --name "AzureFileShare;${FILE_SHARE}" \
  --query "properties.protectionStatus"
```

Expected output: `"Protected"`

## Backup Configuration

The backup operates with the following settings:
- **Schedule**: Daily at 2:00 AM UTC
- **Retention**: 30 days
- **Policy**: `vaultwarden-daily-backup-policy`
- **Protected Resource**: `vaultwarden-data` file share

## Deployment Methods Comparison

| Method | Backup Protection Setup | When to Use |
|--------|------------------------|-------------|
| **GitHub Actions** | Automatic (part of workflow) | Recommended for all deployments |
| **Manual Bicep** | Manual (follow steps above) | When not using GitHub Actions |

## Why This Approach Works

The post-deployment approach is more reliable because:
1. **Timing Control**: Ensures storage account is fully provisioned before registration
2. **Better Error Handling**: Azure CLI provides clearer error messages
3. **Proven Method**: Azure CLI backup commands are well-tested and stable
4. **Flexibility**: Easy to retry or troubleshoot if issues occur

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
