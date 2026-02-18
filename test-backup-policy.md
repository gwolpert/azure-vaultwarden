# Testing Backup Policy Implementation

This document describes how to test the backup policy and storage lock implementation.

## Prerequisites

- Azure CLI installed and logged in
- Appropriate Azure subscription permissions
- Access to the repository

## 1. Validate Bicep Template

```bash
# Build the Bicep template to check for syntax errors
az bicep build --file bicep/main.bicep

# Run what-if analysis to see what resources will be created
az deployment sub what-if \
  --name vaultwarden-backup-test \
  --location eastus \
  --template-file bicep/main.bicep \
  --parameters resourceGroupName="vaultwarden-test" \
  --parameters location="eastus" \
  --parameters environmentName="dev"
```

## 2. Deploy to Test Environment

```bash
# Deploy the infrastructure
az deployment sub create \
  --name vaultwarden-backup-deployment \
  --location eastus \
  --template-file bicep/main.bicep \
  --parameters resourceGroupName="vaultwarden-test" \
  --parameters location="eastus" \
  --parameters environmentName="dev" \
  --parameters signupsAllowed=false \
  --parameters vaultwardenImageTag="1.32.5"
```

## 3. Enable Backup Protection

After deployment, enable backup protection for the file share:

```bash
# Get storage account name and resource ID
STORAGE_ACCOUNT=$(az storage account list \
  --resource-group vaultwarden-test-rg \
  --query "[0].name" -o tsv)

STORAGE_ACCOUNT_ID=$(az storage account show \
  --name $STORAGE_ACCOUNT \
  --resource-group vaultwarden-test-rg \
  --query id -o tsv)

# Register the storage account with the Recovery Services Vault
az backup container register \
  --resource-group vaultwarden-test-rg \
  --vault-name vaultwarden-test-rsv \
  --backup-management-type AzureStorage \
  --workload-type AzureFileShare \
  --storage-account $STORAGE_ACCOUNT_ID

# Wait a few seconds for registration to complete
sleep 10

# Enable backup protection for the file share
az backup protection enable-for-azurefileshare \
  --resource-group vaultwarden-test-rg \
  --vault-name vaultwarden-test-rsv \
  --policy-name vaultwarden-daily-backup-policy \
  --storage-account $STORAGE_ACCOUNT \
  --azure-file-share vaultwarden-data
```

## 4. Verify Backup Configuration

### Check Recovery Services Vault

```bash
# List Recovery Services Vaults
az backup vault list \
  --resource-group vaultwarden-test-rg \
  --output table

# Get vault details
az backup vault show \
  --name vaultwarden-test-rsv \
  --resource-group vaultwarden-test-rg
```

### Check Backup Policy

```bash
# List backup policies
az backup policy list \
  --resource-group vaultwarden-test-rg \
  --vault-name vaultwarden-test-rsv \
  --output table

# Get specific policy details
az backup policy show \
  --name vaultwarden-daily-backup-policy \
  --resource-group vaultwarden-test-rg \
  --vault-name vaultwarden-test-rsv
```

### Check Protected Items

```bash
# List protected items
az backup item list \
  --resource-group vaultwarden-test-rg \
  --vault-name vaultwarden-test-rsv \
  --backup-management-type AzureStorage \
  --workload-type AzureFileShare \
  --output table
```

## 5. Verify Storage Lock

```bash
# Get storage account name from deployment output
STORAGE_ACCOUNT=$(az storage account list \
  --resource-group vaultwarden-test-rg \
  --query "[0].name" -o tsv)

# List locks on the storage account
az lock list \
  --resource-group vaultwarden-test-rg \
  --resource-name $STORAGE_ACCOUNT \
  --resource-type Microsoft.Storage/storageAccounts \
  --output table

# Try to delete the storage account (should fail)
az storage account delete \
  --name $STORAGE_ACCOUNT \
  --resource-group vaultwarden-test-rg \
  --yes
# Expected: Error message about CanNotDelete lock
```

## 6. Test Backup Functionality

### Trigger On-Demand Backup

```bash
# Trigger an immediate backup
az backup protection backup-now \
  --resource-group vaultwarden-test-rg \
  --vault-name vaultwarden-test-rsv \
  --backup-management-type AzureStorage \
  --workload-type AzureFileShare \
  --container-name <storage-container-name> \
  --item-name vaultwarden-data \
  --retain-until $(date -u -d '30 days' +%d-%m-%Y)
```

### Monitor Backup Job

```bash
# List recent backup jobs
az backup job list \
  --resource-group vaultwarden-test-rg \
  --vault-name vaultwarden-test-rsv \
  --output table

# Get job details
az backup job show \
  --resource-group vaultwarden-test-rg \
  --vault-name vaultwarden-test-rsv \
  --name <job-id>
```

### Verify Backup Completed

```bash
# List recovery points
az backup recoverypoint list \
  --resource-group vaultwarden-test-rg \
  --vault-name vaultwarden-test-rsv \
  --backup-management-type AzureStorage \
  --workload-type AzureFileShare \
  --container-name <storage-container-name> \
  --item-name vaultwarden-data \
  --output table
```

## 7. Test Restore (Optional)

```bash
# Create test data in the file share first
# ... upload test files ...

# Restore from the most recent recovery point
az backup restore restore-azurefileshare \
  --resource-group vaultwarden-test-rg \
  --vault-name vaultwarden-test-rsv \
  --rp-name <recovery-point-name> \
  --container-name <storage-container-name> \
  --item-name vaultwarden-data \
  --resolve-conflict Overwrite

# Monitor restore job
az backup job list \
  --resource-group vaultwarden-test-rg \
  --vault-name vaultwarden-test-rsv \
  --operation Restore \
  --output table
```

## 8. Cleanup

```bash
# First, remove the storage lock
az lock delete \
  --name storage-lock \
  --resource-group vaultwarden-test-rg \
  --resource-name $STORAGE_ACCOUNT \
  --resource-type Microsoft.Storage/storageAccounts

# Then delete the resource group
az group delete \
  --name vaultwarden-test-rg \
  --yes \
  --no-wait
```

## Expected Results

1. ✅ Recovery Services Vault is created
2. ✅ Backup policy is configured with daily schedule at 2 AM UTC
3. ✅ File share is registered as a protected item
4. ✅ Storage account has CanNotDelete lock
5. ✅ Backup can be triggered manually
6. ✅ Backup jobs complete successfully
7. ✅ Recovery points are created and accessible
8. ✅ Restore functionality works as expected
9. ✅ Storage account cannot be deleted without removing lock

## Notes

- The first scheduled backup will run at the configured time (2 AM UTC)
- On-demand backups can be triggered at any time
- Recovery points are retained for 30 days by default
- Storage lock prevents accidental deletion but can be removed by authorized users
- Backup costs are based on storage size and retention period
