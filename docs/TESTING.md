---
layout: default
title: Testing Guide
---

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
  --location northeurope \
  --template-file bicep/main.bicep \
  --parameters resourceGroupName="vaultwarden-dev" \
  --parameters location="northeurope" \
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
- [ ] Azure Database for PostgreSQL Flexible Server
- [ ] Log Analytics Workspace
- [ ] App Service Plan
- [ ] App Service (Web App)
- [ ] Key Vault

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
- Subnets: app-service-snet, postgresql-snet

#### Check Subnet Configuration
```bash
az network vnet subnet show \
  --name app-service-snet \
  --vnet-name vaultwarden-dev-vnet \
  --resource-group vaultwarden-dev-rg \
  --query "{name:name, addressPrefix:addressPrefix}"
```

Expected: Subnet 10.0.0.0/24

### 3. PostgreSQL Verification

#### Check PostgreSQL Flexible Server
```bash
az postgres flexible-server show \
  --name vaultwarden-dev-psql \
  --resource-group vaultwarden-dev-rg \
  --query "{name:name, state:state, version:version, sku:sku.name, publicAccess:network.publicNetworkAccess}"
```

Expected:
- State: Ready
- Version: 16 (or configured version)
- Public access: Disabled

#### Verify Database Exists
```bash
az postgres flexible-server db show \
  --server-name vaultwarden-dev-psql \
  --resource-group vaultwarden-dev-rg \
  --database-name vaultwarden
```

Expected: Database named "vaultwarden" exists

#### Check VNet Integration
```bash
az postgres flexible-server show \
  --name vaultwarden-dev-psql \
  --resource-group vaultwarden-dev-rg \
  --query "{delegatedSubnet:network.delegatedSubnetResourceId, privateDnsZone:network.privateDnsZoneArmResourceId}"
```

Expected:
- Delegated subnet references postgresql-snet
- Private DNS zone is configured

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

#### Check Environment Variables
```bash
az webapp config appsettings list \
  --name vaultwarden-dev-app \
  --resource-group vaultwarden-dev-rg \
  --query "[?name=='DATABASE_URL' || name=='IP_HEADER'].{name:name, slotSetting:slotSetting}"
```

Expected:
- DATABASE_URL: Set (pointing to PostgreSQL Flexible Server)
- IP_HEADER: Set

#### Check VNet Integration
```bash
az webapp vnet-integration list \
  --name vaultwarden-dev-app \
  --resource-group vaultwarden-dev-rg
```

Expected:
- VNet integration configured with app-service-snet

#### Check App Service Plan
```bash
az appservice plan show \
  --name vaultwarden-dev-asp \
  --resource-group vaultwarden-dev-rg \
  --query "{name:name, sku:sku.name, kind:kind}"
```

Expected:
- SKU: B1 (or S1, S2, S3, P1v3, P2v3, P3v3 if upgraded)
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

#### Check PostgreSQL Security
```bash
az postgres flexible-server show \
  --name vaultwarden-dev-psql \
  --resource-group vaultwarden-dev-rg \
  --query "{publicAccess:network.publicNetworkAccess, sslEnforcement:requireSecureTransport}"
```

Expected:
- Public access: Disabled
- SSL enforcement: Enabled (secure transport required)

#### Verify PostgreSQL VNet Integration
```bash
az postgres flexible-server show \
  --name vaultwarden-dev-psql \
  --resource-group vaultwarden-dev-rg \
  --query "network"
```

Expected:
- Delegated subnet configured (postgresql-snet)
- Private DNS zone associated
- No public network access

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

### 3. Database Performance

> **Note:** The `date -u -d` syntax below is GNU-specific (Linux). On macOS/BSD, use `date -u -v-1H '+%Y-%m-%dT%H:%M:%SZ'` instead.

#### Check PostgreSQL Metrics
```bash
az monitor metrics list \
  --resource $(az postgres flexible-server show --name vaultwarden-dev-psql --resource-group vaultwarden-dev-rg --query id -o tsv) \
  --metric "cpu_percent" \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --interval PT1M \
  --output table
```

#### Check Active Connections
```bash
az monitor metrics list \
  --resource $(az postgres flexible-server show --name vaultwarden-dev-psql --resource-group vaultwarden-dev-rg --query id -o tsv) \
  --metric "active_connections" \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --interval PT1M \
  --output table
```

#### Check Storage Usage
```bash
az monitor metrics list \
  --resource $(az postgres flexible-server show --name vaultwarden-dev-psql --resource-group vaultwarden-dev-rg --query id -o tsv) \
  --metric "storage_percent" \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --interval PT1M \
  --output table
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

### 1. Verify Built-in Backups

Azure Database for PostgreSQL Flexible Server includes automatic backups. Verify the backup configuration:

```bash
az postgres flexible-server show \
  --name vaultwarden-dev-psql \
  --resource-group vaultwarden-dev-rg \
  --query "{backupRetentionDays:backup.backupRetentionDays, geoRedundantBackup:backup.geoRedundantBackup, earliestRestoreDate:backup.earliestRestoreDate}"
```

Expected:
- Backup retention days: 7 (or configured value)
- Earliest restore date: Should be populated

### 2. Point-in-Time Restore Test (Non-Production Only)

To validate recoverability, you can perform a point-in-time restore to a new server:

```bash
# Get the earliest restore point
EARLIEST=$(az postgres flexible-server show \
  --name vaultwarden-dev-psql \
  --resource-group vaultwarden-dev-rg \
  --query "backup.earliestRestoreDate" -o tsv)

echo "Earliest restore point: $EARLIEST"

# Perform a point-in-time restore to a new server (non-production testing only)
az postgres flexible-server restore \
  --resource-group vaultwarden-dev-rg \
  --name vaultwarden-dev-psql-restore-test \
  --source-server vaultwarden-dev-psql \
  --restore-time "$EARLIEST"

# Verify the restored server is ready
az postgres flexible-server show \
  --name vaultwarden-dev-psql-restore-test \
  --resource-group vaultwarden-dev-rg \
  --query "{name:name, state:state}"

# Clean up the test restore server
az postgres flexible-server delete \
  --name vaultwarden-dev-psql-restore-test \
  --resource-group vaultwarden-dev-rg \
  --yes
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
- [ ] Subnet configured for App Service VNet integration (app-service-snet)
- [ ] PostgreSQL subnet configured with delegation for Flexible Server (postgresql-snet)
- [ ] Azure Database for PostgreSQL Flexible Server deployed and ready
- [ ] PostgreSQL database "vaultwarden" created
- [ ] Log Analytics workspace deployed

### Application
- [ ] App Service running
- [ ] Correct container image deployed
- [ ] DATABASE_URL environment variable set (pointing to PostgreSQL)
- [ ] IP_HEADER environment variable set
- [ ] HTTPS configured
- [ ] VNet integration configured (app-service-snet)

### Security
- [ ] HTTPS enforced on App Service
- [ ] PostgreSQL public network access disabled
- [ ] PostgreSQL SSL enforcement enabled
- [ ] PostgreSQL accessible only via VNet (private access)
- [ ] Secrets stored securely
- [ ] Managed identity enabled

### Functionality
- [ ] Application accessible via URL
- [ ] Login page loads correctly
- [ ] Can create account (if enabled)
- [ ] Can login with credentials
- [ ] Vault operations work
- [ ] Data persists across App Service restarts (stored in PostgreSQL)
- [ ] Admin panel accessible (if enabled)

### Monitoring
- [ ] Logs visible in Log Analytics
- [ ] App Service logs accessible
- [ ] Metrics available
- [ ] No critical errors in logs

### Backup/Recovery
- [ ] PostgreSQL automatic backups configured
- [ ] Backup retention period verified
- [ ] Point-in-time restore validated (non-production)

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
[ ] PostgreSQL Flexible Server: PASS/FAIL
[ ] App Service Plan: PASS/FAIL
[ ] App Service: PASS/FAIL
[ ] Log Analytics: PASS/FAIL

Security
--------
[ ] HTTPS enforcement: PASS/FAIL
[ ] PostgreSQL private access: PASS/FAIL
[ ] PostgreSQL SSL enforcement: PASS/FAIL
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
[ ] PostgreSQL automatic backups: PASS/FAIL
[ ] Backup retention verified: PASS/FAIL

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
PSQL_NAME="vaultwarden-dev-psql"

# Test 1: Resource Group
echo "Test 1: Resource Group"
az group show --name $RG_NAME &> /dev/null && echo "✓ PASS" || echo "✗ FAIL"

# Test 2: PostgreSQL Flexible Server
echo "Test 2: PostgreSQL Flexible Server"
az postgres flexible-server show --name $PSQL_NAME --resource-group $RG_NAME &> /dev/null && echo "✓ PASS" || echo "✗ FAIL"

# Test 3: PostgreSQL Database
echo "Test 3: PostgreSQL Database"
az postgres flexible-server db show --server-name $PSQL_NAME --resource-group $RG_NAME --database-name vaultwarden &> /dev/null && echo "✓ PASS" || echo "✗ FAIL"

# Test 4: App Service
echo "Test 4: App Service"
az webapp show --name $APP_NAME --resource-group $RG_NAME &> /dev/null && echo "✓ PASS" || echo "✗ FAIL"

# Test 5: Application Access
echo "Test 5: Application Access"
URL=$(az webapp show --name $APP_NAME --resource-group $RG_NAME --query "defaultHostName" -o tsv)
curl -s -o /dev/null -w "%{http_code}" "https://$URL" | grep -q "200" && echo "✓ PASS" || echo "✗ FAIL"

# Test 6: PostgreSQL Private Access
echo "Test 6: PostgreSQL Private Access"
PUBLIC=$(az postgres flexible-server show --name $PSQL_NAME --resource-group $RG_NAME --query "network.publicNetworkAccess" -o tsv)
[ "$PUBLIC" = "Disabled" ] && echo "✓ PASS" || echo "✗ FAIL"

# Test 7: App Service Logs
echo "Test 7: App Service Logs"
# log tail is a streaming command that runs indefinitely; exit code 124 (timeout) means
# the connection was established successfully before the 15-second limit expired.
timeout 15s az webapp log tail --name $APP_NAME --resource-group $RG_NAME --only-show-errors &> /dev/null
LOG_TAIL_STATUS=$?
if [ "$LOG_TAIL_STATUS" -eq 0 ] || [ "$LOG_TAIL_STATUS" -eq 124 ]; then
  echo "✓ PASS"
else
  echo "✗ FAIL"
fi

echo "Automated verification complete!"
```

Save this as `verify.sh`, make it executable, and run after deployment.
