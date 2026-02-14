# GitHub Environments Setup Guide

This guide explains how to configure GitHub Environments for deploying Vaultwarden to Azure using GitHub Actions.

## Overview

This deployment uses GitHub Environments to manage configuration for different deployment stages (dev, staging, prod). Each environment has its own variables and secrets that are injected into the Bicep deployment.

## Prerequisites

1. GitHub repository with admin access
2. Azure subscription
3. Azure service principal for GitHub Actions authentication

## Step 1: Create Azure Service Principal

You need to create a service principal for GitHub Actions to authenticate with Azure.

### Option A: Using Azure CLI (Recommended)

```bash
# Set your subscription
az account set --subscription "<your-subscription-id>"

# Create a service principal with Contributor role
az ad sp create-for-rbac \
  --name "github-vaultwarden-deployer" \
  --role contributor \
  --scopes /subscriptions/<your-subscription-id> \
  --sdk-auth
```

**Note:** For newer Azure CLI versions (2.37.0+), use federated credentials instead:

```bash
# Get your GitHub repository details
GITHUB_ORG="<your-github-org>"
GITHUB_REPO="<your-repo-name>"
SUBSCRIPTION_ID="<your-subscription-id>"

# Create the service principal
APP_ID=$(az ad app create \
  --display-name "github-vaultwarden-deployer" \
  --query appId -o tsv)

# Create service principal
az ad sp create --id $APP_ID

# Assign contributor role
az role assignment create \
  --role contributor \
  --assignee $APP_ID \
  --scope /subscriptions/$SUBSCRIPTION_ID

# Create federated credential for GitHub Actions
az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "github-vaultwarden-dev",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'"$GITHUB_ORG"'/'"$GITHUB_REPO"':environment:dev",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# Get the client ID and tenant ID
CLIENT_ID=$(az ad app show --id $APP_ID --query appId -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

echo "AZURE_CLIENT_ID: $CLIENT_ID"
echo "AZURE_TENANT_ID: $TENANT_ID"
echo "AZURE_SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
```

Save these values - you'll need them in the next step.

### Option B: Using Azure Portal

1. Navigate to Azure Portal > Azure Active Directory
2. Select "App registrations" > "New registration"
3. Name it "github-vaultwarden-deployer"
4. After creation, note the "Application (client) ID" and "Directory (tenant) ID"
5. Go to "Certificates & secrets" > "Federated credentials"
6. Add credentials for each environment
7. Assign "Contributor" role at subscription level

## Step 2: Create GitHub Environments

### 2.1 Navigate to Repository Settings

1. Go to your GitHub repository
2. Click "Settings" > "Environments"
3. Click "New environment"

### 2.2 Create Environments

Create three environments: **dev**, **staging**, and **prod**

For each environment:

1. Click "New environment"
2. Enter the environment name (e.g., "dev")
3. Click "Configure environment"
4. (Optional) Set up protection rules:
   - For **prod**: Enable "Required reviewers" and add reviewers
   - Set deployment branches to limit which branches can deploy

## Step 3: Configure Environment Secrets

For each environment (dev, staging, prod), add the following **Secrets**:

### Required Secrets

| Secret Name | Description | Example Value |
|------------|-------------|---------------|
| `AZURE_CLIENT_ID` | Service principal client ID | `12345678-1234-1234-1234-123456789012` |
| `AZURE_TENANT_ID` | Azure AD tenant ID | `87654321-4321-4321-4321-210987654321` |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID | `abcdef12-3456-7890-abcd-ef1234567890` |
| `ADMIN_TOKEN` | Vaultwarden admin panel token | `your-secure-admin-token` (or leave empty to disable) |

### Adding Secrets

1. In the environment settings, scroll to "Environment secrets"
2. Click "Add secret"
3. Enter the secret name and value
4. Click "Add secret"

**Important:** Never commit secrets to your repository!

## Step 4: Configure Environment Variables

For each environment, add the following **Variables**:

### Development Environment (dev)

| Variable Name | Description | Example Value |
|--------------|-------------|---------------|
| `RESOURCE_GROUP_NAME` | Resource group name | `rg-vaultwarden-dev` |
| `AZURE_LOCATION` | Azure region | `eastus` |
| `ENVIRONMENT_NAME` | Environment identifier | `dev` |
| `DOMAIN_NAME` | Custom domain (optional) | `` (empty for auto-generated) |
| `SIGNUPS_ALLOWED` | Allow user signups | `true` |
| `VAULTWARDEN_IMAGE_TAG` | Docker image tag | `latest` |

### Staging Environment (staging)

| Variable Name | Value |
|--------------|-------|
| `RESOURCE_GROUP_NAME` | `rg-vaultwarden-staging` |
| `AZURE_LOCATION` | `eastus` |
| `ENVIRONMENT_NAME` | `staging` |
| `DOMAIN_NAME` | `https://vault-staging.yourdomain.com` |
| `SIGNUPS_ALLOWED` | `false` |
| `VAULTWARDEN_IMAGE_TAG` | `1.30.1` |

### Production Environment (prod)

| Variable Name | Value |
|--------------|-------|
| `RESOURCE_GROUP_NAME` | `rg-vaultwarden-prod` |
| `AZURE_LOCATION` | `eastus` |
| `ENVIRONMENT_NAME` | `prod` |
| `DOMAIN_NAME` | `https://vault.yourdomain.com` |
| `SIGNUPS_ALLOWED` | `false` |
| `VAULTWARDEN_IMAGE_TAG` | `1.30.1` |

### Adding Variables

1. In the environment settings, scroll to "Environment variables"
2. Click "Add variable"
3. Enter the variable name and value
4. Click "Add variable"

## Step 5: Set Up Federated Credentials (if using OIDC)

If you're using federated credentials (recommended), create a credential for each environment:

```bash
# For dev environment
az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "github-vaultwarden-dev",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'"$GITHUB_ORG"'/'"$GITHUB_REPO"':environment:dev",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# For staging environment
az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "github-vaultwarden-staging",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'"$GITHUB_ORG"'/'"$GITHUB_REPO"':environment:staging",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# For prod environment
az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "github-vaultwarden-prod",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'"$GITHUB_ORG"'/'"$GITHUB_REPO"':environment:prod",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

## Step 6: Test Deployment

### Manual Deployment

1. Go to GitHub repository > "Actions" tab
2. Select "Deploy Vaultwarden to Azure" workflow
3. Click "Run workflow"
4. Select the environment (e.g., "dev")
5. Click "Run workflow"

### Automatic Deployment

The workflow automatically deploys when:
- Changes are pushed to `main` branch
- Changes affect `bicep/**` or `.github/workflows/deploy.yml`
- Default environment: `dev`

## Step 7: Verify Deployment

After the workflow completes:

1. Check the workflow summary for deployment outputs
2. Note the Vaultwarden URL
3. Access the URL to verify the application is running
4. Check Azure Portal to verify resources were created

## Environment Protection Rules (Optional)

### For Production Environment

1. In environment settings, enable "Required reviewers"
2. Add team members who must approve deployments
3. Enable "Wait timer" to add a delay before deployment
4. Set "Deployment branches" to only allow `main` or `release/*` branches

### For Staging Environment

1. Enable "Required reviewers" (optional)
2. Set "Deployment branches" to allow `main` and feature branches

### For Dev Environment

1. No protection rules needed (fast iteration)
2. Allow any branch to deploy

## Configuration Examples

### Example: Complete Dev Environment Setup

**Secrets:**
```
AZURE_CLIENT_ID: 12345678-1234-1234-1234-123456789012
AZURE_TENANT_ID: 87654321-4321-4321-4321-210987654321
AZURE_SUBSCRIPTION_ID: abcdef12-3456-7890-abcd-ef1234567890
ADMIN_TOKEN: (leave empty or set a test token)
```

**Variables:**
```
RESOURCE_GROUP_NAME: rg-vaultwarden-dev
AZURE_LOCATION: eastus
ENVIRONMENT_NAME: dev
DOMAIN_NAME: (empty)
SIGNUPS_ALLOWED: true
VAULTWARDEN_IMAGE_TAG: latest
```

### Example: Complete Prod Environment Setup

**Secrets:**
```
AZURE_CLIENT_ID: 12345678-1234-1234-1234-123456789012
AZURE_TENANT_ID: 87654321-4321-4321-4321-210987654321
AZURE_SUBSCRIPTION_ID: abcdef12-3456-7890-abcd-ef1234567890
ADMIN_TOKEN: <strong-secure-random-token-from-password-manager>
```

**Variables:**
```
RESOURCE_GROUP_NAME: rg-vaultwarden-prod
AZURE_LOCATION: eastus
ENVIRONMENT_NAME: prod
DOMAIN_NAME: https://vault.example.com
SIGNUPS_ALLOWED: false
VAULTWARDEN_IMAGE_TAG: 1.30.1
```

**Protection Rules:**
- Required reviewers: 2 team members
- Deployment branches: main only

## Troubleshooting

### Error: "Resource 'Microsoft.Web/sites' could not be found"

**Solution:** Ensure the service principal has "Contributor" role on the subscription.

### Error: "The subscription is not registered to use namespace 'Microsoft.App'"

**Solution:** Register the required resource providers:
```bash
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.OperationalInsights
```

### Error: "Authentication failed"

**Solution:** 
1. Verify the service principal credentials are correct
2. Ensure federated credentials are set up for the correct repository and environment
3. Check that the service principal hasn't expired

### Workflow doesn't trigger automatically

**Solution:**
1. Ensure the workflow file is on the `main` branch
2. Check that branch protection rules aren't blocking the push
3. Verify the workflow file syntax is correct

## Security Best Practices

1. **Use Federated Credentials**: Prefer OIDC authentication over client secrets
2. **Enable Required Reviewers**: Especially for production environments
3. **Limit Deployment Branches**: Only allow specific branches to deploy to production
4. **Rotate Secrets**: Regularly rotate admin tokens and service principal credentials
5. **Audit Access**: Review who has access to environment secrets regularly
6. **Use Strong Admin Tokens**: Generate using: `openssl rand -base64 32`
7. **Separate Service Principals**: Consider using different service principals per environment

## Advanced Configuration

### Using Azure Key Vault for Secrets

Instead of storing secrets in GitHub, reference them from Azure Key Vault:

```yaml
- name: Get secrets from Key Vault
  uses: azure/get-keyvault-secrets@v1
  with:
    keyvault: "my-keyvault"
    secrets: 'vaultwarden-admin-token'
  id: keyvault

- name: Deploy with Key Vault secrets
  uses: azure/arm-deploy@v2
  with:
    parameters: adminToken=${{ steps.keyvault.outputs.vaultwarden-admin-token }}
```

### Multi-Region Deployment

Create separate environments for each region:
- `dev-eastus`
- `dev-westeurope`
- `prod-eastus`
- `prod-westeurope`

### Custom Workflows per Environment

Create environment-specific workflow files:
- `.github/workflows/deploy-dev.yml`
- `.github/workflows/deploy-prod.yml`

## Cleanup

To remove an environment and its resources, you must manually delete them through Azure Portal or Azure CLI:

### Via Azure CLI:
```bash
az group delete --name <resource-group-name> --yes
```

### Via Azure Portal:
1. Navigate to Resource Groups
2. Select the Vaultwarden resource group
3. Click "Delete resource group"
4. Type the resource group name to confirm
5. Click "Delete"

**Important:** Always backup your Vaultwarden data before deleting resources. Deletion is permanent and cannot be undone.

Optionally, after deleting Azure resources:
- Remove the GitHub environment from repository settings if no longer needed

## Additional Resources

- [GitHub Environments Documentation](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)
- [Azure Login Action](https://github.com/Azure/login)
- [Azure ARM Deploy Action](https://github.com/Azure/arm-deploy)
- [OpenID Connect with GitHub Actions](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-azure)
