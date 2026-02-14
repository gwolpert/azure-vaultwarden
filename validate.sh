#!/bin/bash

# ========================================
# Vaultwarden Deployment Validation Script
# ========================================
# 
# This script uses bash-specific features like (( )) arithmetic expansion
# and requires bash (not sh) to run properly.

# Don't exit on errors - we want to show all validation results
# set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

# Function to print colored output
print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

print_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASS_COUNT++))
}

print_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAIL_COUNT++))
}

print_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARN_COUNT++))
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check if Azure CLI is installed
    if command -v az &> /dev/null; then
        AZ_VERSION=$(az version --query '"azure-cli"' -o tsv)
        print_pass "Azure CLI installed (version $AZ_VERSION)"
    else
        print_fail "Azure CLI is not installed"
        echo "  Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check if Bicep is available
    if az bicep version &> /dev/null; then
        BICEP_VERSION=$(az bicep version 2>/dev/null | grep -oP 'Bicep CLI version \K[^\s]+' || echo "unknown")
        print_pass "Bicep CLI available (version $BICEP_VERSION)"
    else
        print_warn "Bicep CLI is not available (will be installed automatically if needed)"
        echo "  Or install manually with: az bicep install"
    fi
    
    # Check if logged in to Azure
    if az account show &> /dev/null; then
        SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
        SUBSCRIPTION_ID=$(az account show --query id -o tsv)
        print_pass "Logged in to Azure"
        print_info "  Subscription: $SUBSCRIPTION_NAME"
        print_info "  ID: $SUBSCRIPTION_ID"
    else
        print_warn "Not logged in to Azure (run 'az login' to check Azure-specific validations)"
    fi
    
    # Check if git is installed
    if command -v git &> /dev/null; then
        GIT_VERSION=$(git --version | grep -oP 'git version \K[^\s]+')
        print_pass "Git installed (version $GIT_VERSION)"
    else
        print_warn "Git is not installed (optional for local development)"
    fi
}

# Check Bicep template
check_bicep_template() {
    print_header "Checking Bicep Template"
    
    if [ -f "bicep/main.bicep" ]; then
        print_pass "Main Bicep template exists"
        
        # Validate Bicep using Azure CLI (proper validation)
        if command -v az &> /dev/null && az bicep version &> /dev/null; then
            print_info "Validating Bicep template with Azure CLI..."
            
            # Capture both stdout and stderr
            BICEP_OUTPUT=$(az bicep build --file bicep/main.bicep --stdout 2>&1)
            BICEP_EXIT_CODE=$?
            
            # Check for warnings (excluding network errors which are expected without internet)
            WARNINGS=$(echo "$BICEP_OUTPUT" | grep -i "warning" | grep -v "BCP192" | grep -v "Unable to restore" || true)
            
            if [ $BICEP_EXIT_CODE -eq 0 ]; then
                print_pass "Bicep template validation passed"
            elif echo "$BICEP_OUTPUT" | grep -q "BCP192"; then
                # If only network errors (BCP192), consider it a pass for local validation
                print_warn "Bicep template has network dependencies (expected without internet access)"
                print_info "  Template syntax appears valid, but modules cannot be downloaded"
            else
                print_fail "Bicep template validation failed"
                echo "$BICEP_OUTPUT" | head -20
            fi
            
            # Check for linter warnings
            if [ -n "$WARNINGS" ]; then
                print_warn "Bicep linter warnings found:"
                echo "$WARNINGS"
            else
                print_pass "No linter warnings found"
            fi
        else
            print_warn "Azure CLI or Bicep not available, skipping proper validation"
            print_info "  Install Azure CLI and run 'az bicep install' for full validation"
            
            # Fallback to basic structure check
            if grep -q "targetScope = 'subscription'" bicep/main.bicep && \
               grep -q "param " bicep/main.bicep && \
               grep -q "module " bicep/main.bicep; then
                print_pass "Bicep template has valid structure (basic check)"
            else
                print_warn "Bicep template structure may be incomplete"
            fi
        fi
    else
        print_fail "Main Bicep template not found at bicep/main.bicep"
    fi
    
    # Check for required modules
    if grep -q "br/public:avm" bicep/main.bicep; then
        print_pass "Uses Azure Verified Modules (AVM)"
    else
        print_warn "Does not use Azure Verified Modules"
    fi
}

# Check GitHub workflows
check_github_workflows() {
    print_header "Checking GitHub Workflows"
    
    if [ -f ".github/workflows/deploy.yml" ]; then
        print_pass "Deploy workflow exists"
        
        # Check for required elements in workflow
        if grep -q "workflow_dispatch" .github/workflows/deploy.yml; then
            print_pass "  Manual trigger configured"
        else
            print_fail "  Manual trigger not configured"
        fi
        
        if grep -q "environment:" .github/workflows/deploy.yml; then
            print_pass "  Environment support configured"
        else
            print_fail "  Environment support not configured"
        fi
        
        if grep -q "azure/login@v2" .github/workflows/deploy.yml; then
            print_pass "  Azure login action configured"
        else
            print_fail "  Azure login action not found"
        fi
        
        if grep -q "azure/arm-deploy@v2" .github/workflows/deploy.yml; then
            print_pass "  ARM deploy action configured"
        else
            print_fail "  ARM deploy action not found"
        fi
    else
        print_fail "Deploy workflow not found"
    fi
}

# Check documentation
check_documentation() {
    print_header "Checking Documentation"
    
    local docs=("README.md" "GITHUB_SETUP.md" "ARCHITECTURE.md" "TESTING.md" "QUICK_REFERENCE.md")
    
    for doc in "${docs[@]}"; do
        if [ -f "$doc" ]; then
            print_pass "$doc exists"
        else
            print_warn "$doc not found"
        fi
    done
}

# Check file structure
check_file_structure() {
    print_header "Checking File Structure"
    
    local required_files=(
        "bicep/main.bicep"
        ".github/workflows/deploy.yml"
        "README.md"
    )
    
    for file in "${required_files[@]}"; do
        if [ -f "$file" ]; then
            print_pass "$file exists"
        else
            print_fail "$file is missing"
        fi
    done
    
    local optional_files=(
        "deploy.sh"
        ".gitignore"
    )
    
    for file in "${optional_files[@]}"; do
        if [ -f "$file" ]; then
            print_pass "$file exists"
        else
            print_warn "$file not found (optional)"
        fi
    done
}

# Check Azure resource providers
check_azure_providers() {
    print_header "Checking Azure Resource Providers"
    
    if ! az account show &> /dev/null; then
        print_warn "Not logged in to Azure, skipping provider check"
        return
    fi
    
    local providers=("Microsoft.App" "Microsoft.OperationalInsights" "Microsoft.Storage" "Microsoft.Network")
    
    for provider in "${providers[@]}"; do
        STATUS=$(az provider show --namespace "$provider" --query "registrationState" -o tsv 2>/dev/null || echo "Unknown")
        if [ "$STATUS" == "Registered" ]; then
            print_pass "$provider is registered"
        elif [ "$STATUS" == "Registering" ]; then
            print_warn "$provider is registering (in progress)"
        else
            print_warn "$provider is not registered"
            echo "  Register with: az provider register --namespace $provider"
        fi
    done
}

# Check for deployment
check_existing_deployment() {
    print_header "Checking for Existing Deployment"
    
    if ! az account show &> /dev/null; then
        print_warn "Not logged in to Azure, skipping deployment check"
        return
    fi
    
    local rg_name="${1:-rg-vaultwarden-dev}"
    
    if az group exists --name "$rg_name" | grep -q "true"; then
        print_info "Resource group '$rg_name' exists"
        
        # Check for container app
        if az containerapp list --resource-group "$rg_name" --query "[0].name" -o tsv &> /dev/null; then
            APP_NAME=$(az containerapp list --resource-group "$rg_name" --query "[0].name" -o tsv)
            print_info "  Container app: $APP_NAME"
            
            # Get FQDN
            FQDN=$(az containerapp show --name "$APP_NAME" --resource-group "$rg_name" --query "properties.configuration.ingress.fqdn" -o tsv 2>/dev/null || echo "")
            if [ ! -z "$FQDN" ]; then
                print_info "  URL: https://$FQDN"
            fi
        else
            print_info "  No container apps found"
        fi
    else
        print_info "No deployment found at '$rg_name'"
    fi
}

# Summary
print_summary() {
    print_header "Validation Summary"
    
    echo -e "Passed:   ${GREEN}$PASS_COUNT${NC}"
    echo -e "Failed:   ${RED}$FAIL_COUNT${NC}"
    echo -e "Warnings: ${YELLOW}$WARN_COUNT${NC}"
    
    echo ""
    if [ $FAIL_COUNT -eq 0 ]; then
        print_pass "All critical checks passed! ✨"
        echo ""
        echo "Next steps:"
        echo "1. Set up GitHub Environments (see GITHUB_SETUP.md)"
        echo "2. Configure secrets and variables in GitHub"
        echo "3. Run the 'Deploy Vaultwarden to Azure' workflow"
        return 0
    else
        print_fail "Some critical checks failed. Please fix the issues above."
        return 1
    fi
}

# Main execution
main() {
    echo "======================================"
    echo "Vaultwarden Deployment Validation"
    echo "======================================"
    
    # Check if in correct directory
    if [ ! -f "bicep/main.bicep" ] && [ ! -f "../bicep/main.bicep" ]; then
        print_fail "Not in repository root directory"
        echo "Please run this script from the repository root"
        exit 1
    fi
    
    # Run checks
    check_prerequisites
    check_file_structure
    check_bicep_template
    check_github_workflows
    check_documentation
    check_azure_providers
    check_existing_deployment "$1"
    
    # Print summary
    print_summary
}

# Run main function with optional resource group name argument
main "$@"
