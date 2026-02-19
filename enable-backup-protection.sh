#!/bin/bash
# ========================================
# Enable Azure Backup Protection for File Share
# ========================================
# This script enables backup protection for the Vaultwarden file share
# after the Bicep deployment completes.
#
# Usage: ./enable-backup-protection.sh <resource-group-name> <storage-account-name> <recovery-vault-name> <file-share-name>
# Example: ./enable-backup-protection.sh vaultwarden-dev-rg vaultwardendevst vaultwarden-dev-rsv vaultwarden-data

set -euo pipefail

# Check if required arguments are provided
if [ $# -lt 4 ]; then
    echo "Error: Missing required arguments"
    echo "Usage: $0 <resource-group-name> <storage-account-name> <recovery-vault-name> <file-share-name>"
    echo "Example: $0 vaultwarden-dev-rg vaultwardendevst vaultwarden-dev-rsv vaultwarden-data"
    exit 1
fi

RESOURCE_GROUP=$1
STORAGE_ACCOUNT=$2
RECOVERY_VAULT=$3
FILE_SHARE=$4

echo "Enabling backup protection for file share..."
echo "Resource Group: $RESOURCE_GROUP"
echo "Storage Account: $STORAGE_ACCOUNT"
echo "Recovery Vault: $RECOVERY_VAULT"
echo "File Share: $FILE_SHARE"

# Check if container already exists
CONTAINER_NAME=$(az backup container show \
  --resource-group "$RESOURCE_GROUP" \
  --vault-name "$RECOVERY_VAULT" \
  --name "storagecontainer;Storage;${RESOURCE_GROUP};${STORAGE_ACCOUNT}" \
  --backup-management-type AzureStorage \
  --query name \
  --output tsv 2>/dev/null || echo "")

if [ -z "$CONTAINER_NAME" ]; then
  echo "Registering storage account with recovery vault..."
  
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
  
  echo "Storage account registered successfully"
  
  # Wait for registration to complete with retry logic
  MAX_RETRIES=12
  SLEEP_SECONDS=10
  RETRY=1
  
  while [ "$RETRY" -le "$MAX_RETRIES" ]; do
    echo "Checking for backup container (attempt ${RETRY}/${MAX_RETRIES})..."
    
    CONTAINER_NAME=$(az backup container show \
      --resource-group "$RESOURCE_GROUP" \
      --vault-name "$RECOVERY_VAULT" \
      --name "storagecontainer;Storage;${RESOURCE_GROUP};${STORAGE_ACCOUNT}" \
      --backup-management-type AzureStorage \
      --query name \
      --output tsv 2>/dev/null || echo "")
    
    if [ -n "$CONTAINER_NAME" ]; then
      echo "Backup container is now available"
      break
    fi
    
    if [ "$RETRY" -eq "$MAX_RETRIES" ]; then
      echo "Error: Backup container did not become available after ${MAX_RETRIES} attempts"
      exit 1
    fi
    
    sleep "$SLEEP_SECONDS"
    RETRY=$((RETRY + 1))
  done
else
  echo "Storage account is already registered"
fi

# Check if file share is already protected
PROTECTED_ITEM=$(az backup item show \
  --resource-group "$RESOURCE_GROUP" \
  --vault-name "$RECOVERY_VAULT" \
  --container-name "$CONTAINER_NAME" \
  --name "AzureFileShare;${FILE_SHARE}" \
  --backup-management-type AzureStorage \
  --workload-type AzureFileShare \
  --query name \
  --output tsv 2>/dev/null || echo "")

if [ -n "$PROTECTED_ITEM" ]; then
  echo "File share is already protected"
else
  # Verify backup policy exists
  if ! az backup policy show \
    --resource-group "$RESOURCE_GROUP" \
    --vault-name "$RECOVERY_VAULT" \
    --name "vaultwarden-daily-backup-policy" \
    --query id \
    --output tsv >/dev/null 2>&1; then
    echo "Error: Backup policy 'vaultwarden-daily-backup-policy' not found"
    exit 1
  fi
  
  # Enable protection
  az backup protection enable-for-azurefileshare \
    --resource-group "$RESOURCE_GROUP" \
    --vault-name "$RECOVERY_VAULT" \
    --policy-name "vaultwarden-daily-backup-policy" \
    --storage-account "$STORAGE_ACCOUNT" \
    --azure-file-share "$FILE_SHARE"
  
  echo "Backup protection enabled successfully"
fi

# Verify protection status
PROTECTION_STATUS=$(az backup item show \
  --resource-group "$RESOURCE_GROUP" \
  --vault-name "$RECOVERY_VAULT" \
  --container-name "$CONTAINER_NAME" \
  --name "AzureFileShare;${FILE_SHARE}" \
  --backup-management-type AzureStorage \
  --workload-type AzureFileShare \
  --query properties.protectionStatus \
  --output tsv 2>/dev/null || echo "Unknown")

echo ""
echo "Backup Protection Status: $PROTECTION_STATUS"
if [ "$PROTECTION_STATUS" = "Protected" ]; then
  echo "✅ Backup protection is active"
  echo "- Daily backups at 2:00 AM UTC"
  echo "- 30-day retention"
else
  echo "⚠️ Backup protection status: $PROTECTION_STATUS"
fi
