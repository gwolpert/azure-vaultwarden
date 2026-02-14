#!/bin/bash

# ========================================
# Vaultwarden Azure Deployment Script
# ========================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
LOCATION="eastus"
ENVIRONMENT="dev"
DEPLOYMENT_NAME="vaultwarden-deployment"

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        print_info "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        print_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if current user/service principal has required permissions
    print_info "Checking Azure permissions..."
    SUBSCRIPTION_ID=$(az account show --query id -o tsv 2>/dev/null)
    
    # Try to check role assignments (this will fail gracefully if not authorized)
    HAS_CONTRIBUTOR=$(az role assignment list --assignee "$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo '')" --role "Contributor" --scope "/subscriptions/$SUBSCRIPTION_ID" --query "[].roleDefinitionName" -o tsv 2>/dev/null | grep -q "Contributor" && echo "yes" || echo "no")
    HAS_UAA=$(az role assignment list --assignee "$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo '')" --role "User Access Administrator" --scope "/subscriptions/$SUBSCRIPTION_ID" --query "[].roleDefinitionName" -o tsv 2>/dev/null | grep -q "User Access Administrator" && echo "yes" || echo "no")
    HAS_OWNER=$(az role assignment list --assignee "$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo '')" --role "Owner" --scope "/subscriptions/$SUBSCRIPTION_ID" --query "[].roleDefinitionName" -o tsv 2>/dev/null | grep -q "Owner" && echo "yes" || echo "no")
    
    if [[ "$HAS_OWNER" == "yes" ]]; then
        print_info "✓ User has Owner role (includes all required permissions)"
    elif [[ "$HAS_CONTRIBUTOR" == "yes" && "$HAS_UAA" == "yes" ]]; then
        print_info "✓ User has Contributor and User Access Administrator roles"
    else
        print_warning "WARNING: Could not verify all required Azure permissions"
        print_warning "Required roles: Contributor AND User Access Administrator (or Owner)"
        print_warning ""
        print_warning "The deployment creates role assignments for the Container App's managed identity."
        print_warning "If you don't have User Access Administrator role, the deployment will fail."
        print_warning ""
        print_warning "To grant the required role, an administrator can run:"
        echo -e "${YELLOW}  az role assignment create \\${NC}"
        echo -e "${YELLOW}    --assignee \"\$(az ad signed-in-user show --query id -o tsv)\" \\${NC}"
        echo -e "${YELLOW}    --role \"User Access Administrator\" \\${NC}"
        echo -e "${YELLOW}    --scope \"/subscriptions/$SUBSCRIPTION_ID\"${NC}"
        echo ""
        read -p "Do you want to continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_warning "Deployment cancelled."
            exit 0
        fi
    fi
    
    print_info "Prerequisites check passed!"
}

# Function to display help
show_help() {
    cat << EOF
Usage: ./deploy.sh [OPTIONS]

Deploy Vaultwarden to Azure Container Apps

OPTIONS:
    -l, --location LOCATION       Azure region (default: eastus)
    -e, --environment ENV         Environment name: dev, staging, prod (default: dev)
    -n, --name NAME              Deployment name (default: vaultwarden-deployment)
    -h, --help                   Display this help message

EXAMPLES:
    # Deploy with default settings
    ./deploy.sh

    # Deploy to West Europe in production
    ./deploy.sh --location westeurope --environment prod

EOF
}

# Parse command line arguments

while [[ $# -gt 0 ]]; do
    case $1 in
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -n|--name)
            DEPLOYMENT_NAME="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main deployment
main() {
    print_info "Starting Vaultwarden deployment..."
    print_info "Location: $LOCATION"
    print_info "Environment: $ENVIRONMENT"
    print_info "Deployment Name: $DEPLOYMENT_NAME"
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Get current subscription
    SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    print_info "Deploying to subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
    echo ""
    
    # Confirm deployment
    read -p "Do you want to proceed with the deployment? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Deployment cancelled."
        exit 0
    fi
    
    # Start deployment
    print_info "Starting deployment..."
    print_info "This may take several minutes..."
    echo ""
    
    # Deploy the Bicep template
    if az deployment sub create \
        --name "$DEPLOYMENT_NAME" \
        --location "$LOCATION" \
        --template-file bicep/main.bicep \
        --parameters resourceGroupName="vaultwarden-$ENVIRONMENT" \
        --parameters location="$LOCATION" \
        --parameters environmentName="$ENVIRONMENT"; then
        
        print_info "Deployment completed successfully!"
        echo ""
        
        # Get outputs
        print_info "Retrieving deployment outputs..."
        VAULTWARDEN_URL=$(az deployment sub show \
            --name "$DEPLOYMENT_NAME" \
            --query properties.outputs.vaultwardenUrl.value \
            -o tsv)
        
        RESOURCE_GROUP=$(az deployment sub show \
            --name "$DEPLOYMENT_NAME" \
            --query properties.outputs.resourceGroupName.value \
            -o tsv)
        
        CONTAINER_APP=$(az deployment sub show \
            --name "$DEPLOYMENT_NAME" \
            --query properties.outputs.containerAppName.value \
            -o tsv)
        
        STORAGE_ACCOUNT=$(az deployment sub show \
            --name "$DEPLOYMENT_NAME" \
            --query properties.outputs.storageAccountName.value \
            -o tsv)
        
        # Display results
        echo ""
        print_info "=========================================="
        print_info "Deployment Information"
        print_info "=========================================="
        print_info "Vaultwarden URL: $VAULTWARDEN_URL"
        print_info "Resource Group: $RESOURCE_GROUP"
        print_info "Container App: $CONTAINER_APP"
        print_info "Storage Account: $STORAGE_ACCOUNT"
        print_info "=========================================="
        echo ""
        
        print_info "You can now access Vaultwarden at: $VAULTWARDEN_URL"
        print_info "It may take a few minutes for the application to start."
        echo ""
        
        print_info "To view logs, run:"
        echo "az containerapp logs show --name $CONTAINER_APP --resource-group $RESOURCE_GROUP --follow"
        echo ""
        
    else
        print_error "Deployment failed!"
        exit 1
    fi
}

# Run main function
main
