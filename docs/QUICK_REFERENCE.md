---
layout: default
title: Quick Reference
---

# Quick Reference

Common commands and workflows for managing Vaultwarden on Azure.

## Deployment

### Deploy with Azure CLI

```bash
az deployment group create \
  --name vaultwarden-deployment \
  --resource-group vaultwarden-dev-rg \
  --template-file bicep/main.bicep \
  --parameters \
    postgresqlAdminPassword="<your-secure-password>"
```

### Deploy with the ARM template

Click the **Deploy to Azure** button in the [README](https://github.com/gwolpert/azure-vaultwarden#quick-deploy) to deploy the published ARM template through the Azure Portal.

### Cleanup Environment
**Note:** Resources must be manually deleted through Azure Portal or CLI for safety.

```bash
# Via Azure CLI
az group delete --name <resource-group-name> --yes

# Or use Azure Portal:
# 1. Navigate to Resource Groups
# 2. Select the resource group
# 3. Click "Delete resource group"
# 4. Confirm deletion
```

**Always backup your data before deleting resources!**

## Azure CLI Quick Commands

### Get Application URL
```bash
az webapp show \
  --name <app-name> \
  --resource-group <rg-name> \
  --query "defaultHostName" -o tsv
```

### View App Service Logs
```bash
az webapp log tail \
  --name <app-name> \
  --resource-group <rg-name>
```

### Check App Service Status
```bash
az webapp show \
  --name <app-name> \
  --resource-group <rg-name> \
  --query "{state:state, availabilityState:availabilityState}"
```

### List All Resources
```bash
az resource list \
  --resource-group <rg-name> \
  --output table
```

### Scale App Service Plan
```bash
az appservice plan update \
  --name <asp-name> \
  --resource-group <rg-name> \
  --sku S2
```

### Restart App Service
```bash
az webapp restart \
  --name <app-name> \
  --resource-group <rg-name>
```

## Backup and Restore

### Backup Data
```bash
# Get PostgreSQL server FQDN
PSQL_FQDN=$(az postgres flexible-server show \
  --name <baseName>-psql \
  --resource-group <rg-name> \
  --query "fullyQualifiedDomainName" -o tsv)

# Dump the database (you will be prompted for the password)
pg_dump \
  --host=$PSQL_FQDN \
  --username=vaultwardenadmin \
  --dbname=vaultwarden \
  --format=custom \
  --file=vaultwarden_backup.dump
```

### Restore Data
```bash
# Stop the App Service before restoring
az webapp stop --name <app-name> --resource-group <rg-name>

# Restore the database from a backup
pg_restore \
  --host=$PSQL_FQDN \
  --username=vaultwardenadmin \
  --dbname=vaultwarden \
  --clean \
  --if-exists \
  --no-owner \
  vaultwarden_backup.dump

# Start the App Service after restoring
az webapp start --name <app-name> --resource-group <rg-name>
```

## Monitoring

### View Metrics
```bash
az monitor metrics list \
  --resource <app-service-id> \
  --metric "CpuPercentage,MemoryPercentage" \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --interval PT1M
```

### Query Logs in Log Analytics
```bash
# Get workspace ID
WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group <rg-name> \
  --workspace-name <workspace-name> \
  --query customerId -o tsv)

# Query logs
az monitor log-analytics query \
  --workspace $WORKSPACE_ID \
  --analytics-query "AppServiceConsoleLogs | take 100" \
  --output table
```

## Troubleshooting

### Deployment Failed: Role Assignment Permission Error

**Symptom:**
```
Authorization failed for template resource of type 'Microsoft.Authorization/roleAssignments'. 
The client does not have permission to perform action 'Microsoft.Authorization/roleAssignments/write'
```

**Cause:** The service principal or user account doesn't have permission to create role assignments. This deployment creates role assignments for the App Service's managed identity to access Key Vault secrets.

**Solution:**
```bash
# Get your subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# For your user account
az role assignment create \
  --assignee "$(az ad signed-in-user show --query id -o tsv)" \
  --role "User Access Administrator" \
  --scope /subscriptions/$SUBSCRIPTION_ID
```

After assigning the role, redeploy the template.

**Alternative:** If your organization's policy doesn't allow User Access Administrator role, you can:
1. Pre-create the role assignment manually before deployment
2. Ask an administrator with Owner role to run the deployment

### Container Won't Start
```bash
# Check recent logs
az webapp log tail --name <app-name> --resource-group <rg-name>

# Check App Service status
az webapp show --name <app-name> --resource-group <rg-name>

# List deployment logs
az webapp log deployment list --name <app-name> --resource-group <rg-name>
```

### Performance Issues
```bash
# Check resource usage
az monitor metrics list \
  --resource <app-service-id> \
  --metric "CpuPercentage,MemoryPercentage" \
  --output table

# Scale up if needed
az appservice plan update \
  --name <asp-name> \
  --resource-group <rg-name> \
  --sku S2
```

### Database Issues
```bash
# Check PostgreSQL server status
az postgres flexible-server show \
  --name <baseName>-psql \
  --resource-group <rg-name> \
  --query "{state:state, version:version, fqdn:fullyQualifiedDomainName}"

# Test connectivity from App Service
az webapp ssh --name <app-name> --resource-group <rg-name>
# Inside the container, verify the DATABASE_URL is set:
#   echo $DATABASE_URL

# Check App Service connection string configuration
az webapp config appsettings list \
  --name <app-name> \
  --resource-group <rg-name> \
  --query "[?name=='DATABASE_URL']"

# View PostgreSQL server logs
az postgres flexible-server server-logs download \
  --name <log-file-name> \
  --server-name <baseName>-psql \
  --resource-group <rg-name>
```

## Security

### Generate Admin Token
```bash
openssl rand -base64 32
```

### Rotate Admin Token
1. Generate new token: `openssl rand -base64 32`
2. Pass the new value as the `adminToken` parameter and redeploy

### Check Security Settings
```bash
# App Service security
az webapp show \
  --name <app-name> \
  --query "{httpsOnly:httpsOnly, minTlsVersion:siteConfig.minTlsVersion}"

# App Service config
az webapp config show \
  --name <app-name> \
  --resource-group <rg-name> \
  --query "{alwaysOn:alwaysOn, linuxFxVersion:linuxFxVersion}"
```

## Custom Domain

### Add Custom Domain
```bash
# Get current hostname
az webapp show \
  --name <app-name> \
  --resource-group <rg-name> \
  --query "defaultHostName"

# Add custom hostname
az webapp config hostname add \
  --hostname vault.example.com \
  --resource-group <rg-name> \
  --webapp-name <app-name>

# Bind SSL certificate (Azure-managed)
az webapp config ssl bind \
  --certificate-thumbprint auto \
  --ssl-type SNI \
  --name <app-name> \
  --resource-group <rg-name>
```

## Environment Names by Default

Based on GitHub Environment configuration (CAF naming conventions):

- **Development**: `vaultwarden-dev-rg` / `vaultwarden-dev-app` / `vaultwarden-dev-asp` / `vaultwarden-dev-psql`
- **Staging**: `vaultwarden-staging-rg` / `vaultwarden-staging-app` / `vaultwarden-staging-asp` / `vaultwarden-staging-psql`
- **Production**: `vaultwarden-prod-rg` / `vaultwarden-prod-app` / `vaultwarden-prod-asp` / `vaultwarden-prod-psql`

VNet subnets: `app-service-snet` (App Service integration) / `postgresql-snet` (PostgreSQL private access)

Replace `<baseName>-*`, `<app-name>`, `<asp-name>`, and `<rg-name>` with your actual values in commands above.

## Useful Aliases

Add to your `.bashrc` or `.zshrc`:

```bash
# Vaultwarden aliases
alias vw-dev-logs="az webapp log tail --name vaultwarden-dev-app --resource-group vaultwarden-dev-rg"
alias vw-dev-status="az webapp show --name vaultwarden-dev-app --resource-group vaultwarden-dev-rg --query '{state:state, availabilityState:availabilityState}'"
alias vw-prod-logs="az webapp log tail --name vaultwarden-prod-app --resource-group vaultwarden-prod-rg"
alias vw-prod-status="az webapp show --name vaultwarden-prod-app --resource-group vaultwarden-prod-rg --query '{state:state, availabilityState:availabilityState}'"
```

## Getting Help

- **Vaultwarden Issues**: https://github.com/dani-garcia/vaultwarden/discussions
- **Azure App Service**: https://docs.microsoft.com/azure/app-service/
- **This Repository**: Open an issue

## Quick Health Check

Run this script to check if your deployment is healthy:

```bash
#!/bin/bash
RG_NAME="vaultwarden-dev-rg"
APP_NAME="vaultwarden-dev-app"

echo "🔍 Health Check for $APP_NAME in $RG_NAME"
echo ""

# Check if resource group exists
echo -n "Resource Group: "
az group show --name $RG_NAME &> /dev/null && echo "✅" || echo "❌"

# Check if App Service exists
echo -n "App Service: "
az webapp show --name $APP_NAME --resource-group $RG_NAME &> /dev/null && echo "✅" || echo "❌"

# Check running status
echo -n "Running Status: "
STATUS=$(az webapp show --name $APP_NAME --resource-group $RG_NAME --query "state" -o tsv 2>/dev/null)
[[ "$STATUS" == "Running" ]] && echo "✅ $STATUS" || echo "⚠️ $STATUS"

# Check PostgreSQL server
PSQL_NAME="vaultwarden-dev-psql"
echo -n "PostgreSQL Server: "
PSQL_STATE=$(az postgres flexible-server show --name $PSQL_NAME --resource-group $RG_NAME --query "state" -o tsv 2>/dev/null)
[[ "$PSQL_STATE" == "Ready" ]] && echo "✅ $PSQL_STATE" || echo "⚠️ $PSQL_STATE"

# Check HTTP endpoint
echo -n "HTTP Endpoint: "
URL=$(az webapp show --name $APP_NAME --resource-group $RG_NAME --query "defaultHostName" -o tsv 2>/dev/null)
if [ ! -z "$URL" ]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://$URL" || echo "000")
    [[ "$HTTP_CODE" == "200" ]] && echo "✅ ($HTTP_CODE)" || echo "⚠️ ($HTTP_CODE)"
    echo "URL: https://$URL"
else
    echo "❌ No URL found"
fi
```

Save as `health-check.sh`, make executable with `chmod +x health-check.sh`, and run with `./health-check.sh`.
