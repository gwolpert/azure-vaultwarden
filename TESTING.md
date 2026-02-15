# Testing and Verification Guide

This document provides comprehensive testing procedures to verify the Vaultwarden deployment.

## Pre-Deployment Validation

### 1. Bicep Template Validation

#### Syntax Check
```bash
az bicep build --file bicep/main.bicep
```

Expected: No errors, ARM template generated successfully

#### What-If Analysis
```bash
az deployment sub what-if \
  --name vaultwarden-deployment \
  --location eastus \
  --template-file bicep/main.bicep \
  --parameters resourceGroupName="vaultwarden-dev" \
  --parameters location="eastus" \
  --parameters environmentName="dev"
```

Expected: Shows all resources that will be created without actually deploying

### 2. Parameters Validation

For GitHub Environments deployment, verify environment variables are configured:
- [ ] Resource group name is set in GitHub Environment
- [ ] Location is a valid Azure region
- [ ] Environment name is dev/staging/prod
- [ ] Image tag is specified

For manual deployment, you can validate by running a what-if first (see above).

## Post-Deployment Verification

### 1. Resource Deployment Check

#### Verify Resource Group
```bash
az group show --name vaultwarden-dev-rg
```

Expected: Resource group exists with correct tags

#### List All Resources
```bash
az resource list --resource-group vaultwarden-dev-rg --output table
```

Expected resources:
- [ ] Virtual Network
- [ ] Storage Account
- [ ] File Share
- [ ] Log Analytics Workspace
- [ ] App Service Plan
- [ ] App Service (Web App)

### 2. Network Configuration Verification

#### Check Virtual Network
```bash
az network vnet show \
  --name vaultwarden-dev-vnet \
  --resource-group vaultwarden-dev-rg \
  --query "{name:name, addressSpace:addressSpace, subnets:subnets[].name}"
```

Expected:
- Address space: 10.0.0.0/16
- Subnet: container-apps-subnet

#### Check Subnet Configuration
```bash
az network vnet subnet show \
  --name container-apps-subnet \
  --vnet-name vaultwarden-dev-vnet \
  --resource-group vaultwarden-dev-rg \
  --query "{name:name, addressPrefix:addressPrefix}"
```

Expected: Subnet 10.0.0.0/23

### 3. Storage Account Verification

#### Check Storage Account
```bash
STORAGE_NAME=$(az storage account list \
  --resource-group vaultwarden-dev-rg \
  --query "[0].name" -o tsv)

az storage account show \
  --name $STORAGE_NAME \
  --query "{name:name, httpsOnly:enableHttpsTrafficOnly, minTls:minimumTlsVersion, publicAccess:allowBlobPublicAccess}"
```

Expected:
- HTTPS only: true
- Min TLS: TLS1_2
- Public access: false

#### Verify File Share
```bash
STORAGE_KEY=$(az storage account keys list \
  --account-name $STORAGE_NAME \
  --resource-group vaultwarden-dev-rg \
  --query "[0].value" -o tsv)

az storage share list \
  --account-name $STORAGE_NAME \
  --account-key $STORAGE_KEY \
  --output table
```

Expected: File share named "vaultwarden-data" exists

### 4. App Service Verification

#### Check App Service Status
```bash
az webapp show \
  --name vaultwarden-dev-app \
  --resource-group vaultwarden-dev-rg \
  --query "{name:name, state:state, availabilityState:availabilityState, defaultHostName:defaultHostName}"
```

Expected:
- State: Running
- Availability state: Normal
- Default hostname: Should be populated

#### Check App Service Configuration
```bash
az webapp config show \
  --name vaultwarden-dev-app \
  --resource-group vaultwarden-dev-rg \
  --query "{linuxFxVersion:linuxFxVersion, alwaysOn:alwaysOn, httpsOnly:httpsOnly}"
```

Verify:
- [ ] linuxFxVersion: DOCKER|vaultwarden/server:latest
- [ ] alwaysOn: true
- [ ] httpsOnly: true

#### Check VNet Integration
```bash
az webapp vnet-integration list \
  --name vaultwarden-dev-app \
  --resource-group vaultwarden-dev-rg
```

Expected:
- VNet integration configured with app-service-subnet

#### Check App Service Plan
```bash
az appservice plan show \
  --name vaultwarden-dev-asp \
  --resource-group vaultwarden-dev-rg \
  --query "{name:name, sku:sku.name, kind:kind}"
```

Expected:
- SKU: S1
- Kind: linux

### 5. Application Health Check

#### Get Application URL
```bash
VAULTWARDEN_URL=$(az webapp show \
  --name vaultwarden-dev-app \
  --resource-group vaultwarden-dev-rg \
  --query "defaultHostName" -o tsv)

echo "Vaultwarden URL: https://$VAULTWARDEN_URL"
```

#### Test HTTP Connectivity
```bash
curl -I "https://$VAULTWARDEN_URL"
```

Expected: HTTP 200 OK

#### Test Application Response
```bash
curl -s "https://$VAULTWARDEN_URL" | grep -i "bitwarden"
```

Expected: HTML content containing "Bitwarden" or "Vaultwarden"

#### Test API Endpoint
```bash
curl -s "https://$VAULTWARDEN_URL/api/config" | jq '.'
```

Expected: JSON response with Vaultwarden configuration

### 6. App Service Logs Verification

#### View Recent Logs
```bash
az webapp log tail \
  --name vaultwarden-dev-app \
  --resource-group vaultwarden-dev-rg
```

Check for:
- [ ] No error messages
- [ ] Successful startup messages
- [ ] Database initialization messages

#### Check for Errors
```bash
az webapp log download \
  --name vaultwarden-dev-app \
  --resource-group vaultwarden-dev-rg \
  --log-file vaultwarden-logs.zip

unzip -p vaultwarden-logs.zip | grep -i error | tail -50
```

Expected: No critical errors (some warnings may be normal)

### 7. Log Analytics Verification

#### Check Workspace
```bash
az monitor log-analytics workspace show \
  --resource-group vaultwarden-dev-rg \
  --workspace-name vaultwarden-dev-log \
  --query "{name:name, provisioningState:provisioningState}"
```

Expected: Provisioning state Succeeded

#### Query Container Logs (wait a few minutes after deployment)
```bash
WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group vaultwarden-dev-rg \
  --workspace-name vaultwarden-dev-log \
  --query customerId -o tsv)

# Note: Logs may take 5-10 minutes to appear
az monitor log-analytics query \
  --workspace $WORKSPACE_ID \
  --analytics-query "AppServiceConsoleLogs | take 10" \
  --output table
```

### 8. Security Verification

#### Check Storage Account Security
```bash
az storage account show \
  --name $STORAGE_NAME \
  --query "{httpsOnly:enableHttpsTrafficOnly, tlsVersion:minimumTlsVersion, blobPublicAccess:allowBlobPublicAccess, networkRules:networkRuleSet.defaultAction}"
```

Expected:
- HTTPS only: true
- TLS version: TLS1_2
- Blob public access: false

#### Verify App Service Secrets
```bash
az webapp config appsettings list \
  --name vaultwarden-dev-app \
  --resource-group vaultwarden-dev-rg \
  --query "[?name=='ADMIN_TOKEN'].{name:name, slotSetting:slotSetting}"
```

Expected: Settings exist (values should not be displayed for secrets)

#### Check Managed Identity
```bash
az webapp identity show \
  --name vaultwarden-dev-app \
  --resource-group vaultwarden-dev-rg
```

Expected: System-assigned identity enabled

## Functional Testing

### 1. User Registration Test (if enabled)

If signups are allowed:

1. Navigate to: `https://$VAULTWARDEN_URL`
2. Click "Create Account"
3. Fill in email and master password
4. Verify account creation succeeds

### 2. Login Test

1. Navigate to: `https://$VAULTWARDEN_URL`
2. Enter credentials
3. Verify successful login

### 3. Vault Operations Test

1. Create a new login item
2. Verify it's saved
3. Edit the item
4. Delete the item

### 4. Data Persistence Test

#### Create Test Data
1. Login and create a test vault item
2. Note the item details

#### Restart Container
```bash
az webapp restart \
  --name vaultwarden-dev-app \
  --resource-group vaultwarden-dev-rg
```

#### Verify Data
1. Wait for App Service to restart (check logs)
2. Login again
3. Verify test item still exists

### 5. Admin Panel Test (if enabled)

If admin token is set:

1. Navigate to: `https://$VAULTWARDEN_URL/admin`
2. Enter admin token
3. Verify access to admin panel
4. Check users list
5. Review diagnostics

## Performance Testing

### 1. Response Time Test

```bash
time curl -s "https://$VAULTWARDEN_URL" > /dev/null
```

Expected: < 2 seconds

### 2. Load Test (Simple)

```bash
# Run 10 concurrent requests
for i in {1..10}; do
  curl -s "https://$VAULTWARDEN_URL" > /dev/null &
done
wait

echo "Load test completed"
```

Check logs for any errors during load

### 3. Storage Performance

#### Write Test
```bash
# Create a test file
echo "Test data" > test.txt

# Upload to file share
az storage file upload \
  --account-name $STORAGE_NAME \
  --account-key $STORAGE_KEY \
  --share-name vaultwarden-data \
  --source test.txt \
  --path test.txt

# Verify upload
az storage file show \
  --account-name $STORAGE_NAME \
  --account-key $STORAGE_KEY \
  --share-name vaultwarden-data \
  --path test.txt

# Cleanup
rm test.txt
az storage file delete \
  --account-name $STORAGE_NAME \
  --account-key $STORAGE_KEY \
  --share-name vaultwarden-data \
  --path test.txt
```

## Monitoring Validation

### 1. Metrics Check

```bash
# CPU usage
az monitor metrics list \
  --resource $(az webapp show --name vaultwarden-dev-app --resource-group vaultwarden-dev-rg --query id -o tsv) \
  --metric "CpuPercentage" \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --interval PT1M \
  --output table
```

### 2. Alert Configuration (Optional)

Create an alert for high CPU usage:

```bash
az monitor metrics alert create \
  --name vaultwarden-cpu-alert \
  --resource-group vaultwarden-dev-rg \
  --scopes $(az webapp show --name vaultwarden-dev-app --resource-group vaultwarden-dev-rg --query id -o tsv) \
  --condition "avg CpuPercentage > 80" \
  --description "Alert when CPU usage exceeds 80%"
```

## Backup and Recovery Testing

### 1. Backup Test

```bash
# Create backup directory
mkdir -p backup-test

# Download all data
az storage file download-batch \
  --destination backup-test \
  --source vaultwarden-data \
  --account-name $STORAGE_NAME \
  --account-key $STORAGE_KEY

# Verify backup
ls -lh backup-test/
```

Expected: Database files and attachments downloaded

### 2. Recovery Test

```bash
# Stop App Service
az webapp stop \
  --name vaultwarden-dev-app \
  --resource-group vaultwarden-dev-rg

# Wait for stop
sleep 10

# Upload backup
az storage file upload-batch \
  --destination vaultwarden-data \
  --source backup-test \
  --account-name $STORAGE_NAME \
  --account-key $STORAGE_KEY

# Start App Service
az webapp start \
  --name vaultwarden-dev-app \
  --resource-group vaultwarden-dev-rg

# Verify application is accessible
sleep 60
curl -I "https://$VAULTWARDEN_URL"

# Cleanup
rm -rf backup-test
```

## Troubleshooting Tests

### 1. App Service Restart Test

```bash
# Force a restart
az webapp restart \
  --name vaultwarden-dev-app \
  --resource-group vaultwarden-dev-rg

# Monitor restart - check logs
az webapp log tail \
  --name vaultwarden-dev-app \
  --resource-group vaultwarden-dev-rg
```

Expected: App Service restarts successfully within 1-2 minutes

### 2. Network Connectivity Test

```bash
# From within Azure (if you have a VM in the same region)
# Test internal connectivity to the App Service
nslookup $VAULTWARDEN_URL
telnet $VAULTWARDEN_URL 443
```

## Verification Checklist

Use this checklist to verify your deployment:

### Infrastructure
- [ ] Resource group created
- [ ] Virtual network deployed with correct address space
- [ ] Subnet configured for Container Apps
- [ ] Storage account created with security settings
- [ ] File share created and accessible
- [ ] Log Analytics workspace deployed

### Application
- [ ] App Service running
- [ ] Correct container image deployed
- [ ] Environment variables set
- [ ] Storage mounted correctly
- [ ] HTTPS configured
- [ ] VNet integration configured

### Security
- [ ] HTTPS enforced
- [ ] Storage HTTPS-only enabled
- [ ] TLS 1.2 minimum configured
- [ ] Secrets stored securely
- [ ] Public blob access disabled
- [ ] Managed identity enabled

### Functionality
- [ ] Application accessible via URL
- [ ] Login page loads correctly
- [ ] Can create account (if enabled)
- [ ] Can login with credentials
- [ ] Vault operations work
- [ ] Data persists across restarts
- [ ] Admin panel accessible (if enabled)

### Monitoring
- [ ] Logs visible in Log Analytics
- [ ] App Service logs accessible
- [ ] Metrics available
- [ ] No critical errors in logs

### Backup/Recovery
- [ ] Can backup data from file share
- [ ] Can restore data to file share
- [ ] Application recovers after restoration

## Test Report Template

After running all tests, document your results:

```
Deployment Test Report
======================
Date: [DATE]
Environment: [dev/staging/prod]
Tester: [NAME]

Pre-Deployment
--------------
[ ] Bicep syntax validation: PASS/FAIL
[ ] What-if analysis: PASS/FAIL
[ ] Parameters validation: PASS/FAIL

Resource Deployment
------------------
[ ] Resource group: PASS/FAIL
[ ] Virtual network: PASS/FAIL
[ ] Storage account: PASS/FAIL
[ ] App Service Plan: PASS/FAIL
[ ] App Service: PASS/FAIL
[ ] Log Analytics: PASS/FAIL

Security
--------
[ ] HTTPS enforcement: PASS/FAIL
[ ] Storage security: PASS/FAIL
[ ] Secrets management: PASS/FAIL
[ ] Managed identity: PASS/FAIL

Functionality
------------
[ ] Application access: PASS/FAIL
[ ] User operations: PASS/FAIL
[ ] Data persistence: PASS/FAIL
[ ] Admin panel: PASS/FAIL

Performance
----------
[ ] Response time: [TIME]ms
[ ] Load handling: PASS/FAIL

Backup/Recovery
--------------
[ ] Backup creation: PASS/FAIL
[ ] Data restoration: PASS/FAIL

Issues Found
-----------
1. [Issue description]
2. [Issue description]

Recommendations
--------------
1. [Recommendation]
2. [Recommendation]

Overall Status: PASS/FAIL
```

## Automated Testing Script

A simple automated test script:

```bash
#!/bin/bash

echo "Starting automated verification..."

RG_NAME="vaultwarden-dev-rg"
APP_NAME="vaultwarden-dev-app"

# Test 1: Resource Group
echo "Test 1: Resource Group"
az group show --name $RG_NAME &> /dev/null && echo "✓ PASS" || echo "✗ FAIL"

# Test 2: App Service
echo "Test 2: App Service"
az webapp show --name $APP_NAME --resource-group $RG_NAME &> /dev/null && echo "✓ PASS" || echo "✗ FAIL"

# Test 3: Application Access
echo "Test 3: Application Access"
URL=$(az webapp show --name $APP_NAME --resource-group $RG_NAME --query "defaultHostName" -o tsv)
curl -s -o /dev/null -w "%{http_code}" "https://$URL" | grep -q "200" && echo "✓ PASS" || echo "✗ FAIL"

# Test 4: App Service Logs
echo "Test 4: App Service Logs"
az webapp log tail --name $APP_NAME --resource-group $RG_NAME --only-show-errors &> /dev/null && echo "✓ PASS" || echo "✗ FAIL"

echo "Automated verification complete!"
```

Save this as `verify.sh`, make it executable, and run after deployment.
