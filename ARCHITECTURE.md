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
│  │  │  │  App Service Subnet (10.0.0.0/24)           │   │  │ │
│  │  │  │                                               │   │  │ │
│  │  │  │  ┌────────────────────────────────────┐     │   │  │ │
│  │  │  │  │  App Service Plan (S1 Standard)   │     │   │  │ │
│  │  │  │  │  - 1 core, 1.75 GB RAM            │     │   │  │ │
│  │  │  │  │                                    │     │   │  │ │
│  │  │  │  │  ┌──────────────────────────┐    │     │   │  │ │
│  │  │  │  │  │  App Service (Web App)   │    │     │   │  │ │
│  │  │  │  │  │  - Container: vaultwarden│◄───┼─────┼───┼──┼─┐
│  │  │  │  │  │  - Port: 80              │    │     │   │  │ │
│  │  │  │  │  │  - Storage Mount: /data  │    │     │   │  │ │
│  │  │  │  │  │  - Managed Identity      │    │     │   │  │ │
│  │  │  │  │  │  - VNet Integration      │    │     │   │  │ │
│  │  │  │  │  └──────────┬───────────────┘    │     │   │  │ │
│  │  │  │  │             │                     │     │   │  │ │
│  │  │  │  │             │ Mounts              │     │   │  │ │
│  │  │  │  │             │                     │     │   │  │ │
│  │  │  │  └─────────────┼─────────────────────┘     │   │  │ │
│  │  │  │                │                            │   │  │ │
│  │  │  └────────────────┼────────────────────────────┘   │  │ │
│  │  │                   │                                 │  │ │
│  │  └───────────────────┼─────────────────────────────────┘  │ │
│  │                      │                                     │ │
│  │  ┌───────────────────▼───────────────────────────────┐    │ │
│  │  │          Storage Account (Azure Files)            │    │ │
│  │  │                                                    │    │ │
│  │  │  ┌──────────────────────────────────────────┐    │    │ │
│  │  │  │   File Share: vaultwarden-data          │    │    │ │
│  │  │  │   - db.sqlite3                           │    │    │ │
│  │  │  │   - db.sqlite3-wal                       │    │    │ │
│  │  │  │   - attachments/                         │    │    │ │
│  │  │  │   - icon_cache/                          │    │    │ │
│  │  │  └──────────────────────────────────────────┘    │    │ │
│  │  │  │   - CanNotDelete lock enabled             │    │    │ │
│  │  └────────────────────────────────────────────────────┘    │ │
│  │                      ▲                                      │ │
│  │                      │ Backed up daily                      │ │
│  │  ┌───────────────────┴───────────────────────────────┐    │ │
│  │  │        Recovery Services Vault                     │    │ │
│  │  │        - Daily backup policy (2 AM UTC)           │    │ │
│  │  │        - 30-day retention                          │    │ │
│  │  │        - File share protection                     │    │ │
│  │  └────────────────────────────────────────────────────┘    │ │
│  │                                                              │ │
│  │  ┌────────────────────────────────────────────────────┐    │ │
│  │  │        Azure Key Vault                             │    │ │
│  │  │        - Admin token secret                        │────┼─┘
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
3. **Secrets Management**: App Service uses its system-assigned managed identity to retrieve admin token from Key Vault
4. **Data Storage**: App Service mounts Azure File Share for persistent data storage
5. **Backup Protection**: Recovery Services Vault automatically backs up the file share daily at 2 AM UTC
6. **Monitoring**: All logs and metrics are sent to Log Analytics Workspace
7. **Networking**: App Service is integrated with Virtual Network for enhanced security

## Security Features

### Network Security
- Virtual Network isolation with VNet integration
- App Service subnet with service delegation
- HTTPS-only access with Azure-managed certificates
- Private endpoint support available on S1+

### Data Security
- Storage Account with:
  - HTTPS-only traffic enforced
  - Minimum TLS 1.2
  - No public blob access
  - Private file share access
  - **CanNotDelete** resource lock to prevent accidental deletion
- Automated daily backups with 30-day retention
- Point-in-time recovery capabilities
- Encrypted data at rest (Azure Storage encryption)
- Encrypted data in transit (TLS 1.2+)

### Application Security
- Admin panel disabled by default
- User signups disabled by default
- Secrets stored in Azure Key Vault (not in configuration)
- App Service uses managed identity for Key Vault access
- System-assigned managed identity for Azure resource access
- RBAC-based access control for Key Vault

## Scaling and High Availability

### Scaling Configuration
- **App Service Plan**: S1 (1 core, 1.75 GB RAM)
- **Manual Scaling**: Scale up to higher SKUs (S2, S3, P1v2, P1v3, etc.) for more resources
- **Auto-scaling**: Available on Standard tier - configure based on CPU, memory, or HTTP queue metrics
- **Scale Out**: Scale to multiple instances (up to 10 on S1)

### High Availability
- Deployment slots for zero-downtime deployments (staging, production)
- Automatic health checks and container restart
- Data persistence ensures no data loss during restarts
- Zone redundancy available with Premium SKUs (P1v2+)
- Traffic manager integration for multi-region deployments

### Performance Optimizations
- SQLite WAL mode enabled for better performance on network storage
- VNet integration for optimal network performance
- S1 SKU: 1 core, 1.75 GB RAM (suitable for production deployments)
- Always On enabled to prevent cold starts
- Supports deployment slots for testing before production rollout

## Cost Breakdown

### Monthly Cost Estimates (East US)

| Resource | Configuration | Estimated Cost |
|----------|--------------|----------------|
| App Service Plan (S1) | 1 core, 1.75GB RAM, Linux | $70-75 |
| Storage Account | Standard LRS, ~5GB data | $2-5 |
| Recovery Services Vault + Backup | Daily backups, 30-day retention | $5-10 |
| Log Analytics | ~10GB/month logs | $2-10 |
| Virtual Network | Subnet, no additional charges | Free |
| Key Vault | Operations-based pricing | < $1 |
| **Total** | | **$79-101/month** |

**S1 Features vs B1**:
- ✅ Full VNet integration support
- ✅ Auto-scaling capabilities  
- ✅ Deployment slots (zero-downtime updates)
- ✅ Better performance and reliability
- ✅ Production-ready with SLA
- ✅ Custom domain with SSL included

**Backup & Protection Features**:
- ✅ Automated daily backups with 30-day retention
- ✅ Point-in-time recovery for data protection
- ✅ Storage account lock prevents accidental deletion
- ✅ Compliance-ready backup solution

**Note**: While more expensive than B1 (~$13/month), S1 provides enterprise-grade features essential for production workloads including VNet integration, deployment slots, and auto-scaling capabilities.

### Cost Optimization Tips
1. S1 tier is ideal for production with full feature set
2. Use deployment slots to test updates before production
3. Configure auto-scaling to scale down during low-traffic periods
4. Use lifecycle policies for storage account to clean old logs
5. Use shared Log Analytics workspace across multiple projects
6. Reserved instances available for 1-3 year commitments (30-55% savings)
7. Adjust backup retention period based on compliance requirements

## Deployment Process

### Pre-Deployment
1. Azure CLI and Bicep installed
2. Appropriate Azure subscription permissions
3. Optional: Custom domain DNS configured

### Deployment Steps
1. **Resource Group Creation**: Subscription-scoped deployment creates resource group
2. **Network Setup**: Virtual Network and subnet provisioned with App Service delegation
3. **Storage Provisioning**: Storage account and file share created
4. **Monitoring Setup**: Log Analytics Workspace deployed
5. **App Service Plan**: S1 Standard Linux plan created with auto-scaling support
6. **Key Vault**: Deployed for secrets management
7. **Application Deployment**: Vaultwarden container deployed on App Service with VNet integration

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
1. **Automated Backups**: Azure Backup is configured for the vaultwarden-data file share
   - **Schedule**: Daily at 2:00 AM UTC
   - **Retention**: 30 days
   - **Policy**: Configured via Recovery Services Vault
   - **Setup**: Requires one-time post-deployment configuration (see README for commands)
   - **Operation**: Automatic after initial setup
2. **Manual Backups**: Alternative option using Azure CLI to download data
3. **Storage Protection**: CanNotDelete lock prevents accidental storage account deletion

### Recovery Procedures

#### Automated Restore from Backup
1. Access Recovery Services Vault in Azure Portal or use Azure CLI
2. Select the recovery point (up to 30 days back)
3. Choose restore method:
   - **Original Location**: Overwrites current data
   - **Alternate Location**: Restores to a different file share
4. Monitor restore job completion
5. Restart App Service if needed
6. Verify data integrity

#### Manual Restore Process
1. Stop the App Service to prevent new writes
2. Restore file share from backup using Azure Portal or CLI
3. Restart the App Service
4. Verify data integrity and application functionality

### Business Continuity
- **RTO (Recovery Time Objective)**: < 1 hour with automated restore
- **RPO (Recovery Point Objective)**: < 24 hours with daily backups (configurable to hourly if needed)
- **Data Protection**: Resource lock prevents accidental deletion
- **Cross-region replication**: Available with geo-redundant storage (GRS) upgrade
- **Backup Retention**: 30 days (configurable up to years for compliance)

### Backup Monitoring
- Monitor backup jobs through Azure Portal or Azure CLI
- Set up alerts for backup failures in Azure Monitor
- Review backup history and compliance reports
- Validate backup integrity through periodic restore tests

## Troubleshooting Guide

### Common Issues

#### Container Won't Start
**Symptoms**: Container keeps restarting
**Causes**: 
- Invalid environment variables
- Storage mount issues
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

#### Database Corruption
**Symptoms**: Errors about locked database
**Causes**:
- Multiple containers writing simultaneously
- Improper shutdown
- Network issues with file share

**Resolution**:
1. Scale to 1 replica
2. Stop the container
3. Run SQLite integrity check on backup
4. Restore from known good backup if needed

## Security Hardening

### Production Checklist
- [ ] Enable admin token with strong password
- [ ] Disable signups or use invite-only mode
- [ ] Configure custom domain with valid SSL certificate
- [ ] Set up Azure Monitor alerts
- [x] Configure backup automation (daily backups with 30-day retention)
- [x] Enable storage account lock to prevent accidental deletion
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
- Data protection: Resource locks prevent accidental resource deletion

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
