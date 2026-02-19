#!/bin/bash
# ========================================
# Enable Azure Backup Protection for File Share
# ========================================
# This script enables backup protection for the Vaultwarden file share
# after the main Bicep deployment completes.
#
# Use this script as a fallback if the Bicep-based backup protection
# deployment fails with "BMSUserErrorInvalidSourceResourceId".
#
# Usage: ./enable-backup-protection.sh <resource-group-name> <storage-account-name> <recovery-vault-name> <file-share-name>
# Example: ./enable-backup-protection.sh vaultwarden-dev-rg vaultwardendevst vaultwarden-dev-rsv vaultwarden-data

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if required arguments are provided
if [ $# -lt 4 ]; then
    print_error "Missing required arguments"
    echo "Usage: $0 <resource-group-name> <storage-account-name> <recovery-vault-name> <file-share-name>"
    echo "Example: $0 vaultwarden-dev-rg vaultwardendevst vaultwarden-dev-rsv vaultwarden-data"
    exit 1
fi

RESOURCE_GROUP=$1
STORAGE_ACCOUNT=$2
RECOVERY_VAULT=$3
FILE_SHARE=$4

print_info "Starting backup protection setup..."
print_info "Resource Group: $RESOURCE_GROUP"
print_info "Storage Account: $STORAGE_ACCOUNT"
print_info "Recovery Vault: $RECOVERY_VAULT"
print_info "File Share: $FILE_SHARE"

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed. Please install it first."
    exit 1
fi

# Check if logged in to Azure
if ! az account show &> /dev/null; then
    print_error "Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

print_info "Checking if storage account exists..."
if ! az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
    print_error "Storage account '$STORAGE_ACCOUNT' not found in resource group '$RESOURCE_GROUP'"
    exit 1
fi

print_info "Checking if recovery vault exists..."
if ! az backup vault show --name "$RECOVERY_VAULT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
    print_error "Recovery vault '$RECOVERY_VAULT' not found in resource group '$RESOURCE_GROUP'"
    exit 1
fi

print_info "Checking if file share exists..."
STORAGE_ACCOUNT_KEY=$(az storage account keys list \
    --account-name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query "[0].value" \
    --output tsv)

if ! az storage share show \
    --name "$FILE_SHARE" \
    --account-name "$STORAGE_ACCOUNT" \
    --account-key "$STORAGE_ACCOUNT_KEY" &> /dev/null; then
    print_error "File share '$FILE_SHARE' not found in storage account '$STORAGE_ACCOUNT'"
    exit 1
fi

print_info "Enabling backup protection for file share..."

# Register the storage account with the recovery vault
print_info "Step 1/2: Registering storage account with recovery vault..."
CONTAINER_NAME=$(az backup container show \
    --resource-group "$RESOURCE_GROUP" \
    --vault-name "$RECOVERY_VAULT" \
    --name "storagecontainer;Storage;${RESOURCE_GROUP};${STORAGE_ACCOUNT}" \
    --backup-management-type AzureStorage \
    --query name \
    --output tsv 2>/dev/null || echo "")

if [ -z "$CONTAINER_NAME" ]; then
    print_info "Storage account not yet registered. Registering now..."
    
    # Get the storage account resource ID
    STORAGE_ACCOUNT_ID=$(az storage account show \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query id \
        --output tsv)
    
    # Register the storage account (this creates the protection container)
    az backup container register \
        --resource-group "$RESOURCE_GROUP" \
        --vault-name "$RECOVERY_VAULT" \
        --backup-management-type AzureStorage \
        --workload-type AzureFileShare \
        --storage-account "$STORAGE_ACCOUNT_ID"
    
    print_info "Storage account registered successfully"
    
    # Wait a bit for registration to complete
    print_info "Waiting for registration to complete..."
    sleep 10
    
    # Get container name after registration
    CONTAINER_NAME=$(az backup container show \
        --resource-group "$RESOURCE_GROUP" \
        --vault-name "$RECOVERY_VAULT" \
        --name "storagecontainer;Storage;${RESOURCE_GROUP};${STORAGE_ACCOUNT}" \
        --backup-management-type AzureStorage \
        --query name \
        --output tsv)
else
    print_info "Storage account is already registered"
fi

print_info "Container name: $CONTAINER_NAME"

# Enable protection for the file share
print_info "Step 2/2: Enabling protection for file share..."

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
    print_warning "File share is already protected"
    print_info "Backup protection is already enabled for '$FILE_SHARE'"
else
    # Get the backup policy ID
    POLICY_ID=$(az backup policy show \
        --resource-group "$RESOURCE_GROUP" \
        --vault-name "$RECOVERY_VAULT" \
        --name "vaultwarden-daily-backup-policy" \
        --query id \
        --output tsv)
    
    if [ -z "$POLICY_ID" ]; then
        print_error "Backup policy 'vaultwarden-daily-backup-policy' not found"
        exit 1
    fi
    
    print_info "Using backup policy: vaultwarden-daily-backup-policy"
    
    # Enable protection
    az backup protection enable-for-azurefileshare \
        --resource-group "$RESOURCE_GROUP" \
        --vault-name "$RECOVERY_VAULT" \
        --policy-name "vaultwarden-daily-backup-policy" \
        --storage-account "$STORAGE_ACCOUNT" \
        --azure-file-share "$FILE_SHARE"
    
    print_info "Backup protection enabled successfully for '$FILE_SHARE'"
fi

# Verify the backup protection status
print_info "Verifying backup protection status..."
PROTECTION_STATUS=$(az backup item show \
    --resource-group "$RESOURCE_GROUP" \
    --vault-name "$RECOVERY_VAULT" \
    --container-name "$CONTAINER_NAME" \
    --name "AzureFileShare;${FILE_SHARE}" \
    --backup-management-type AzureStorage \
    --workload-type AzureFileShare \
    --query properties.protectionStatus \
    --output tsv 2>/dev/null || echo "Unknown")

if [ "$PROTECTION_STATUS" = "Protected" ]; then
    print_info "✓ Backup protection is active and working correctly"
    print_info "✓ Daily backups will run at 2:00 AM UTC"
    print_info "✓ Backups will be retained for 30 days"
else
    print_warning "Backup protection status: $PROTECTION_STATUS"
    print_warning "This may take a few minutes to become active"
fi

print_info "Backup protection setup complete!"
