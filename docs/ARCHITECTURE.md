---
layout: default
title: Architecture Overview
---

# Architecture Overview

## Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                      Azure Subscription                          │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                   Resource Group                            │ │
│  │                                                              │ │
│  │  ┌──────────────────────────────────────────────────────┐  │ │
│  │  │              Virtual Network (10.0.0.0/16)           │  │ │
│  │  │                                                        │  │ │
│  │  │  ┌──────────────────────────────────────────────┐   │  │ │
│  │  │  │  app-service-snet (10.0.0.0/24)             │   │  │ │
│  │  │  │                                               │   │  │ │
│  │  │  │  ┌────────────────────────────────────┐     │   │  │ │
│  │  │  │  │  App Service Plan (B1 Basic)      │     │   │  │ │
│  │  │  │  │  - 1 core, 1.75 GB RAM            │     │   │  │ │
│  │  │  │  │                                    │     │   │  │ │
│  │  │  │  │  ┌──────────────────────────┐    │     │   │  │ │
│  │  │  │  │  │  App Service (Web App)   │    │     │   │  │ │
│  │  │  │  │  │  - Container: vaultwarden│◄───┼─────┼───┼──┼─┐
│  │  │  │  │  │  - Port: 80              │    │     │   │  │ │
│  │  │  │  │  │  - DATABASE_URL from     │    │     │   │  │ │
│  │  │  │  │  │    Key Vault             │    │     │   │  │ │
│  │  │  │  │  │  - IP_HEADER: X-Client-IP│    │     │   │  │ │
│  │  │  │  │  │  - Managed Identity      │    │     │   │  │ │
│  │  │  │  │  │  - VNet Integration      │    │     │   │  │ │
│  │  │  │  │  └──────────┬───────────────┘    │     │   │  │ │
│  │  │  │  │             │                     │     │   │  │ │
│  │  │  │  └─────────────┼─────────────────────┘     │   │  │ │
│  │  │  │                │                            │   │  │ │
│  │  │  └────────────────┼────────────────────────────┘   │  │ │
│  │  │                   │ PostgreSQL (via VNet)           │  │ │
│  │  │  ┌────────────────▼───────────────────────────┐   │  │ │
│  │  │  │  postgresql-snet (10.0.1.0/24)             │   │  │ │
│  │  │  │  - Delegated to PostgreSQL Flexible Server │   │  │ │
│  │  │  │                                             │   │  │ │
│  │  │  │  ┌─────────────────────────────────────┐  │   │  │ │
│  │  │  │  │  Azure Database for PostgreSQL      │  │   │  │ │
│  │  │  │  │  Flexible Server                    │  │   │  │ │
│  │  │  │  │  - Burstable B1MS (1 vCore, 2 GB)  │  │   │  │ │
│  │  │  │  │  - SSL enforced                     │  │   │  │ │
│  │  │  │  │  - VNet integrated (private access) │  │   │  │ │
│  │  │  │  │  - Built-in backup (7-day retention)│  │   │  │ │
│  │  │  │  │  - Optional CanNotDelete lock       │  │   │  │ │
│  │  │  │  └─────────────────────────────────────┘  │   │  │ │
│  │  │  └─────────────────────────────────────────────┘   │  │ │
│  │  │                                                     │  │ │
│  │  └─────────────────────────────────────────────────────┘  │ │
│  │                                                              │ │
│  │  ┌────────────────────────────────────────────────────┐    │ │
│  │  │        Private DNS Zone                            │    │ │
│  │  │        - privatelink.postgres.database.azure.com   │    │ │
│  │  │        - Linked to VNet                            │    │ │
│  │  │        - Resolves PostgreSQL server to private IP  │    │ │
│  │  └────────────────────────────────────────────────────┘    │ │
│  │                                                              │ │
│  │  ┌────────────────────────────────────────────────────┐    │ │
│  │  │        Azure Key Vault                             │    │ │
│  │  │        - Admin token + Database URL secrets        │────┼─┘
│  │  │        - RBAC enabled                              │      
│  │  │        - System-assigned identity access           │      
│  │  └────────────────────────────────────────────────────┘      
│  │                                                              │ │
│  │  ┌────────────────────────────────────────────────────┐    │ │
│  │  │        Log Analytics Workspace                     │    │ │
│  │  │        - App Service logs                          │    │ │
│  │  │        - Metrics                                   │    │ │
│  │  │        - Performance data                          │    │ │
│  │  └────────────────────────────────────────────────────┘    │ │
│  │                                                              │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
         ▲
         │ HTTPS (443)
         │
    ┌────┴─────┐
    │  Users   │
    └──────────┘
```

## Resource Flow

1. **User Access**: Users access Vaultwarden via HTTPS through the App Service's public endpoint
2. **App Service**: Runs the Vaultwarden container with automatic HTTPS termination
3. **Secrets Management**: App Service uses its system-assigned managed identity to retrieve admin token and database URL from Key Vault
4. **Data Storage**: App Service connects to Azure Database for PostgreSQL Flexible Server via VNet integration → delegated PostgreSQL subnet
5. **DNS Resolution**: Private DNS Zone (`privatelink.postgres.database.azure.com`) resolves PostgreSQL server to its private IP within the VNet
6. **Backup Protection**: PostgreSQL Flexible Server built-in backup with 7-day retention (configurable up to 35 days) and point-in-time restore
7. **Monitoring**: All logs and metrics are sent to Log Analytics Workspace
8. **Networking**: App Service is integrated with Virtual Network; PostgreSQL Flexible Server is accessible only via VNet integration (no public access)

## Security Features

### Network Security
- Virtual Network isolation with VNet integration
- App Service subnet (`app-service-snet`) with service delegation (10.0.0.0/24)
- PostgreSQL subnet (`postgresql-snet`) with service delegation for Flexible Server (10.0.1.0/24)
- PostgreSQL Flexible Server accessible only via VNet integration (no public access)
- Private DNS Zone resolves PostgreSQL server to private IP within VNet
- HTTPS-only access with Azure-managed certificates
- App Service inbound private endpoints (for private access to the web app) require Premium tiers; connecting to PostgreSQL Flexible Server via VNet integration is supported from Basic (B1) and above

### Data Security
- Azure Database for PostgreSQL Flexible Server with:
  - SSL/TLS enforced for all connections
  - VNet integration (private access only, no public endpoint)
  - Encrypted data at rest (Azure-managed encryption)
  - Encrypted data in transit (TLS 1.2+)
  - Optional **CanNotDelete** resource lock to prevent accidental deletion (requires `Microsoft.Authorization/locks/write` permission)
- Built-in automated backups with 7-day retention (configurable up to 35 days)
- Point-in-time restore capability

### Application Security
- Admin panel disabled by default
- User signups disabled by default
- Secrets stored in Azure Key Vault (not in configuration)
- App Service uses managed identity for Key Vault access
- System-assigned managed identity for Azure resource access
- RBAC-based access control for Key Vault

## Scaling and High Availability

### Scaling Configuration
- **App Service Plan**: B1 (1 core, 1.75 GB RAM) - Default for cost-effectiveness with VNet integration support
- **Manual Scaling**: Scale up to higher SKUs (B2, B3, S1, S2, S3, P1v3, P2v3, P3v3) for more resources
- **Auto-scaling**: Available on Standard (S1+) and Premium tiers - configure based on CPU, memory, or HTTP queue metrics
- **Scale Out**: B1 supports up to 3 instances; Standard tier supports up to 10 instances

### High Availability
- Deployment slots for zero-downtime deployments (staging, production) *(Standard/Premium tiers only)*
- Automatic health checks and container restart
- Data persistence ensures no data loss during restarts
- Zone redundancy available with Premium SKUs (P1v2+)
- Traffic manager integration for multi-region deployments

### Performance Optimizations
- PostgreSQL Flexible Server for reliable, scalable database performance
- Optional: external PostgreSQL connection pooling (for example, PgBouncer) can improve resource utilization, but it is not configured by this repo
- VNet integration for optimal network performance
- B1 SKU: 1 core, 1.75 GB RAM (suitable for small to medium deployments, 5-50 users)
- Upgrade to Standard (S1+) or Premium tiers for auto-scaling and higher capacity
- Always On enabled to prevent cold starts
- Supports deployment slots for testing before production rollout (Standard and Premium tiers)

## Cost Breakdown

### Monthly Cost Estimates (North Europe)

| Resource | Configuration | Estimated Cost |
|----------|--------------|----------------|
| App Service Plan (B1) | 1 core, 1.75GB RAM, Linux | $13-15 |
| PostgreSQL Flexible Server | Burstable B1MS, 1 vCore, 2 GB RAM, 32 GB storage | $12-15 |
| Log Analytics | ~10GB/month logs | $2-10 |
| Virtual Network | Two subnets, no additional charges | Free |
| Private DNS Zone | privatelink.postgres.database.azure.com | < $1 |
| Key Vault | Operations-based pricing | < $1 |
| **Total** | | **$28-42/month** |

**B1 Features (Default)**:
- ✅ Full VNet integration support
- ✅ Custom domain with SSL included
- ✅ 1 core, 1.75 GB RAM (sufficient for 5-50 users)
- ✅ Manual scaling up to 3 instances
- ✅ Production-ready with SLA
- ❌ No auto-scaling (available on S1+)
- ❌ No deployment slots (available on S1+)

**Upgrade Options**:
- **Standard (S1, S2, S3)**: Adds auto-scaling, deployment slots, up to 10 instances (~$70-140/month for S1-S3)
- **Premium (P1v3, P2v3, P3v3)**: Enhanced performance, up to 30 instances, more cores and memory (~$100-400/month)

**Backup & Protection Features**:
- ✅ PostgreSQL built-in backup with 7-day retention (configurable up to 35 days)
- ✅ Point-in-time restore for data protection
- ✅ Optional PostgreSQL server lock prevents accidental deletion (enable via `enablePostgresqlLock` parameter)
- ✅ Compliance-ready backup solution

**Note**: B1 provides excellent value for small to medium deployments (5-50 users). For larger deployments or auto-scaling needs, upgrade to Standard (S1+) or Premium tiers.

### Cost Optimization Tips
1. B1 tier is ideal for small to medium deployments (5-50 users) with excellent cost savings
2. Upgrade to Standard (S1+) tier for auto-scaling and deployment slots if needed
3. Configure auto-scaling (on S1+) to scale down during low-traffic periods
4. Use lifecycle policies for Log Analytics to manage log retention
5. Use shared Log Analytics workspace across multiple projects
6. Reserved instances available for 1-3 year commitments (30-55% savings)
7. Adjust PostgreSQL backup retention period based on compliance requirements

## Deployment Process

### Pre-Deployment
1. Azure CLI and Bicep installed
2. Appropriate Azure subscription permissions
3. Optional: Custom domain DNS configured

### Deployment Steps
1. **Resource Group Creation**: Subscription-scoped deployment creates resource group
2. **Network Setup**: Virtual Network with two subnets (app service + PostgreSQL) provisioned
3. **Private DNS Zone**: DNS zone `privatelink.postgres.database.azure.com` created and linked to VNet
4. **Database Provisioning**: Azure Database for PostgreSQL Flexible Server deployed in the delegated subnet with VNet integration
5. **Monitoring Setup**: Log Analytics Workspace deployed
6. **App Service Plan**: B1 Basic Linux plan created (can be upgraded to Standard/Premium for auto-scaling)
7. **Key Vault**: Deployed for secrets management (admin token + database URL)
8. **Storage Account**: StorageV2 account with an Azure Files share is provisioned with `publicNetworkAccess` denied and a virtualNetworkRule restricting the data plane to the App Service subnet (via the `Microsoft.Storage` service endpoint). The share is mounted into the container at `/data/attachments` and Vaultwarden's `ATTACHMENTS_FOLDER`, `USER_ATTACHMENT_LIMIT` and `ORG_ATTACHMENT_LIMIT` (20 MB) point at it. Diagnostic metrics are forwarded to Log Analytics.
9. **Application Deployment**: Vaultwarden container deployed on App Service with VNet integration and DATABASE_URL configured

### Post-Deployment
1. Verify App Service health status
2. Test application access via provided URL
3. Configure custom domain (if required)
4. Set up backup procedures
5. Configure monitoring alerts

## Monitoring and Operations

### Key Metrics to Monitor
- App Service CPU and memory usage
- HTTP request count and response times
- Storage usage and IOPS
- PostgreSQL connections and query performance
- App Service restart count
- Failed authentication attempts

### Log Queries (KQL)

#### Recent App Service Logs
```kql
AppServiceConsoleLogs
| where ResourceId contains "vaultwarden-dev-app"
| order by TimeGenerated desc
| take 100
```

#### Error Logs
```kql
AppServiceConsoleLogs
| where ResourceId contains "vaultwarden-dev-app"
| where ResultDescription contains "ERROR" or ResultDescription contains "error"
| order by TimeGenerated desc
```

#### HTTP Request Stats
```kql
AppServiceHTTPLogs
| where ResourceId contains "vaultwarden-dev-app"
| summarize count() by ScStatus
```

## Backup and Disaster Recovery

### Backup Strategy
1. **PostgreSQL Built-in Backup**: Azure Database for PostgreSQL Flexible Server provides automated backups
   - **Schedule**: Continuous automated backups (snapshots + transaction logs)
   - **Retention**: 7 days by default (configurable up to 35 days)
   - **Point-in-Time Restore**: Restore to any second within the retention period
   - **Setup**: Automatically enabled on PostgreSQL Flexible Server at deployment
   - **Operation**: Fully automatic with no manual intervention required
2. **Manual Backups**: Alternative option using `pg_dump` via Azure CLI or direct connection for logical backups
3. **Database Protection**: Optional CanNotDelete lock prevents accidental PostgreSQL server deletion (enable via `enablePostgresqlLock` parameter)

### Recovery Procedures

#### Point-in-Time Restore
1. Access Azure Portal or use Azure CLI to initiate a point-in-time restore
2. Select the restore point (any second within the retention period)
3. A new PostgreSQL Flexible Server instance is created with the restored data
4. Update the App Service DATABASE_URL to point to the new server (or swap DNS)
5. Restart App Service if needed
6. Verify data integrity

#### Manual Restore Process
1. Stop the App Service to prevent new writes
2. Restore the PostgreSQL database using point-in-time restore via Azure Portal or CLI
3. Update connection settings if the restored server has a different endpoint
4. Restart the App Service
5. Verify data integrity and application functionality

### Business Continuity
- **RTO (Recovery Time Objective)**: < 1 hour with point-in-time restore
- **RPO (Recovery Point Objective)**: Near-zero data loss (continuous backup with transaction log archiving)
- **Data Protection**: Optional resource lock prevents accidental deletion of PostgreSQL server
- **Geo-redundant Backup**: Available as a configuration option for cross-region protection
- **Backup Retention**: 7 days default (configurable up to 35 days)

### Backup Monitoring
- Monitor PostgreSQL server health and backup status through Azure Portal
- Set up alerts for backup failures or storage issues in Azure Monitor
- Review backup configuration and retention policies periodically
- Validate backup integrity through periodic point-in-time restore tests

## Troubleshooting Guide

### Common Issues

#### Container Won't Start
**Symptoms**: Container keeps restarting
**Causes**: 
- Invalid environment variables
- Database connectivity issues
- Image pull failures

**Resolution**:
```bash
# Check App Service logs
az webapp log tail --name <app-name> --resource-group <rg-name>

# Check App Service status
az webapp show --name <app-name> --resource-group <rg-name>
```

#### Cannot Access Application
**Symptoms**: URL not responding
**Causes**:
- Container not ready
- Ingress misconfiguration
- DNS issues

**Resolution**:
```bash
# Check ingress configuration
az webapp show --name <app-name> --resource-group <rg-name> --query "httpsOnly,hostNames"

# Verify container is running
az webapp log tail --name <app-name> --resource-group <rg-name>
```

#### PostgreSQL Connectivity Issues
**Symptoms**: Application errors related to database connection failures
**Causes**:
- PostgreSQL server not running or unreachable
- VNet integration misconfigured
- Private DNS Zone not resolving correctly
- SSL certificate issues
- Incorrect DATABASE_URL in Key Vault

**Resolution**:
1. Verify PostgreSQL server status in Azure Portal
2. Check VNet integration and subnet delegation settings
3. Verify Private DNS Zone is linked to the VNet and resolving correctly
4. Test connectivity from App Service using Kudu console
```bash
# Check PostgreSQL server status
az postgres flexible-server show --name <server-name> --resource-group <rg-name>

# Verify DNS resolution from within the VNet
az webapp ssh --name <app-name> --resource-group <rg-name>
# Then from the SSH session: nslookup <server-name>.postgres.database.azure.com
```

## Security Hardening

### Production Checklist
- [ ] Enable admin token with strong password
- [ ] Disable signups or use invite-only mode
- [ ] Configure custom domain with valid SSL certificate
- [ ] Set up Azure Monitor alerts
- [x] Configure backup automation (PostgreSQL built-in backup with 7-day retention)
- [ ] Enable PostgreSQL server lock to prevent accidental deletion (set `enablePostgresqlLock=true`; requires `Microsoft.Authorization/locks/write` permission)
- [x] Enable VNet integration for PostgreSQL Flexible Server (no public access)
- [ ] Review and restrict network access
- [ ] Enable deployment slots for zero-downtime updates
- [ ] Configure auto-scaling rules based on load
- [ ] Set up Application Insights for detailed monitoring
- [ ] Implement IP restrictions if needed
- [ ] Set up log retention policies
- [ ] Configure SMTP for email notifications
- [ ] Review and update Vaultwarden regularly
- [ ] Consider zone redundancy (upgrade to Premium if needed)
- [ ] Test backup restore procedures periodically

### Compliance Considerations
- Data residency: Resources deployed in specified Azure region
- Encryption: Data encrypted at rest and in transit
- Audit logs: Available through Log Analytics
- Access control: Azure RBAC for resource management
- Network isolation: VNET integration available
- Backup and recovery: Automated daily backups with configurable retention
- Data protection: Optional resource locks prevent accidental resource deletion

## Updates and Maintenance

### Update Procedures
1. Test updates in dev environment first
2. Backup data before updating
3. Update image tag in parameters file
4. Redeploy template
5. Verify application functionality
6. Monitor for issues

### Maintenance Windows
- Recommended: Off-peak hours
- Duration: 5-10 minutes typical
- Zero-downtime updates possible with deployment slots (staging → production swap)

## Additional Resources

### Official Documentation
- [Vaultwarden Documentation](https://github.com/dani-garcia/vaultwarden/wiki)
- [Azure App Service](https://docs.microsoft.com/azure/app-service/)
- [Azure Bicep](https://docs.microsoft.com/azure/azure-resource-manager/bicep/)
- [Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/)

### Community Resources
- [Vaultwarden Discussions](https://github.com/dani-garcia/vaultwarden/discussions)
- [Azure App Service Samples](https://github.com/Azure-Samples/app-service-samples)

### Support Channels
- Vaultwarden Issues: GitHub Issues
- Azure Support: Azure Portal
- Community: Reddit r/Vaultwarden
