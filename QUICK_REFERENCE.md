# Quick Reference

Common commands and workflows for managing Vaultwarden on Azure.

## GitHub Actions Workflows

### Deploy to Development
1. Go to Actions > "Deploy Vaultwarden to Azure"
2. Run workflow > Select `dev` environment
3. Wait for completion (~5-10 minutes)

### Deploy to Production
1. Go to Actions > "Deploy Vaultwarden to Azure"
2. Run workflow > Select `prod` environment
3. Approve deployment (if protection rules enabled)
4. Wait for completion

### Cleanup Environment
**Note:** There is no automated destroy workflow. Resources must be manually deleted through Azure Portal or CLI for safety.

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
az containerapp show \
  --name <app-name> \
  --resource-group <rg-name> \
  --query "properties.configuration.ingress.fqdn" -o tsv
```

### View Container Logs
```bash
az containerapp logs show \
  --name <app-name> \
  --resource-group <rg-name> \
  --follow
```

### Check Container Status
```bash
az containerapp show \
  --name <app-name> \
  --resource-group <rg-name> \
  --query "{state:properties.provisioningState, running:properties.runningStatus}"
```

### List All Resources
```bash
az resource list \
  --resource-group <rg-name> \
  --output table
```

### Scale Container App
```bash
az containerapp update \
  --name <app-name> \
  --resource-group <rg-name> \
  --min-replicas 1 \
  --max-replicas 5
```

### Restart Container
```bash
az containerapp revision restart \
  --name <app-name> \
  --resource-group <rg-name> \
  --revision <revision-name>
```

## Backup and Restore

### Backup Data
```bash
# Get storage account name
STORAGE_NAME=$(az storage account list -g <rg-name> --query "[0].name" -o tsv)

# Get storage key
STORAGE_KEY=$(az storage account keys list \
  --account-name $STORAGE_NAME \
  --resource-group <rg-name> \
  --query "[0].value" -o tsv)

# Download all files
az storage file download-batch \
  --destination ./backup \
  --source vaultwarden-data \
  --account-name $STORAGE_NAME \
  --account-key $STORAGE_KEY
```

### Restore Data
```bash
# Upload files back
az storage file upload-batch \
  --destination vaultwarden-data \
  --source ./backup \
  --account-name $STORAGE_NAME \
  --account-key $STORAGE_KEY
```

## Monitoring

### View Metrics
```bash
az monitor metrics list \
  --resource <container-app-id> \
  --metric "UsageNanoCores" \
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
  --analytics-query "ContainerAppConsoleLogs_CL | take 100" \
  --output table
```

## Troubleshooting

### Container Won't Start
```bash
# Check recent logs
az containerapp logs show --name <app-name> --resource-group <rg-name> --tail 50

# Check container app status
az containerapp show --name <app-name> --resource-group <rg-name>

# List revisions
az containerapp revision list --name <app-name> --resource-group <rg-name>
```

### Performance Issues
```bash
# Check resource usage
az monitor metrics list \
  --resource <container-app-id> \
  --metric "UsageNanoCores,WorkingSetBytes" \
  --output table

# Scale up if needed
az containerapp update \
  --name <app-name> \
  --resource-group <rg-name> \
  --cpu 1.0 \
  --memory 2Gi
```

### Database Issues
```bash
# Check if WAL mode is enabled (in container logs)
az containerapp logs show --name <app-name> --resource-group <rg-name> | grep WAL

# Access container (if needed for debugging)
az containerapp exec \
  --name <app-name> \
  --resource-group <rg-name> \
  --command /bin/sh
```

## Security

### Generate Admin Token
```bash
openssl rand -base64 32
```

### Rotate Admin Token
1. Generate new token: `openssl rand -base64 32`
2. Update GitHub Environment secret `ADMIN_TOKEN`
3. Redeploy via GitHub Actions

### Check Security Settings
```bash
# Storage account security
az storage account show \
  --name $STORAGE_NAME \
  --query "{httpsOnly:enableHttpsTrafficOnly, minTls:minimumTlsVersion}"

# Container App ingress
az containerapp ingress show \
  --name <app-name> \
  --resource-group <rg-name> \
  --query "{external:external, allowInsecure:allowInsecure}"
```

## Custom Domain

### Add Custom Domain
```bash
# Get current FQDN
az containerapp show \
  --name <app-name> \
  --resource-group <rg-name> \
  --query "properties.configuration.ingress.fqdn"

# Add custom hostname
az containerapp hostname add \
  --hostname vault.example.com \
  --resource-group <rg-name> \
  --name <app-name>

# Bind certificate (optional - Azure can manage)
az containerapp hostname bind \
  --hostname vault.example.com \
  --resource-group <rg-name> \
  --name <app-name> \
  --environment <env-name>
```

## Environment Names by Default

Based on GitHub Environment configuration:

- **Development**: `vaultwarden-dev-rg` / `vaultwarden-dev-app`
- **Staging**: `vaultwarden-staging-rg` / `vaultwarden-staging-app`
- **Production**: `vaultwarden-prod-rg` / `vaultwarden-prod-app`

Replace `<app-name>` and `<rg-name>` with your actual values in commands above.

## Useful Aliases

Add to your `.bashrc` or `.zshrc`:

```bash
# Vaultwarden aliases
alias vw-dev-logs="az containerapp logs show --name vaultwarden-dev-app --resource-group vaultwarden-dev-rg --follow"
alias vw-dev-status="az containerapp show --name vaultwarden-dev-app --resource-group vaultwarden-dev-rg --query '{state:properties.provisioningState, running:properties.runningStatus}'"
alias vw-prod-logs="az containerapp logs show --name vaultwarden-prod-app --resource-group vaultwarden-prod-rg --follow"
alias vw-prod-status="az containerapp show --name vaultwarden-prod-app --resource-group vaultwarden-prod-rg --query '{state:properties.provisioningState, running:properties.runningStatus}'"
```

## Getting Help

- **Vaultwarden Issues**: https://github.com/dani-garcia/vaultwarden/discussions
- **Azure Container Apps**: https://docs.microsoft.com/azure/container-apps/
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

# Check if container app exists
echo -n "Container App: "
az containerapp show --name $APP_NAME --resource-group $RG_NAME &> /dev/null && echo "✅" || echo "❌"

# Check running status
echo -n "Running Status: "
STATUS=$(az containerapp show --name $APP_NAME --resource-group $RG_NAME --query "properties.runningStatus" -o tsv 2>/dev/null)
[[ "$STATUS" == "Running" ]] && echo "✅ $STATUS" || echo "⚠️ $STATUS"

# Check HTTP endpoint
echo -n "HTTP Endpoint: "
URL=$(az containerapp show --name $APP_NAME --resource-group $RG_NAME --query "properties.configuration.ingress.fqdn" -o tsv 2>/dev/null)
if [ ! -z "$URL" ]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://$URL" || echo "000")
    [[ "$HTTP_CODE" == "200" ]] && echo "✅ ($HTTP_CODE)" || echo "⚠️ ($HTTP_CODE)"
    echo "URL: https://$URL"
else
    echo "❌ No URL found"
fi
```

Save as `health-check.sh`, make executable with `chmod +x health-check.sh`, and run with `./health-check.sh`.
