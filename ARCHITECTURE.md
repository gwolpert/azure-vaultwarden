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
│  │  │  │  Container Apps Subnet (10.0.0.0/23)        │   │  │ │
│  │  │  │                                               │   │  │ │
│  │  │  │  ┌────────────────────────────────────┐     │   │  │ │
│  │  │  │  │  Container App Environment        │     │   │  │ │
│  │  │  │  │                                    │     │   │  │ │
│  │  │  │  │  ┌──────────────────────────┐    │     │   │  │ │
│  │  │  │  │  │  Vaultwarden Container   │    │     │   │  │ │
│  │  │  │  │  │  - Image: vaultwarden    │◄───┼─────┼───┼──┼─┐
│  │  │  │  │  │  - Port: 80              │    │     │   │  │ │
│  │  │  │  │  │  - Volume: /data         │    │     │   │  │ │
│  │  │  │  │  │  - Managed Identity      │    │     │   │  │ │
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
│  │  │        - Container logs                            │    │ │
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

1. **User Access**: Users access Vaultwarden via HTTPS through the Container App's public endpoint
2. **Container App**: Runs the Vaultwarden container with automatic HTTPS termination
3. **Secrets Management**: Container App uses its system-assigned managed identity to retrieve admin token from Key Vault
4. **Data Storage**: Container mounts Azure File Share for persistent data storage
5. **Monitoring**: All logs and metrics are sent to Log Analytics Workspace
6. **Networking**: Container App runs in a dedicated subnet within the Virtual Network

## Security Features

### Network Security
- Virtual Network isolation
- Container Apps subnet with network policies
- HTTPS-only access with Azure-managed certificates
- Optional internal-only deployment (set `internal: true`)

### Data Security
- Storage Account with:
  - HTTPS-only traffic enforced
  - Minimum TLS 1.2
  - No public blob access
  - Private file share access
- Encrypted data at rest (Azure Storage encryption)
- Encrypted data in transit (TLS 1.2+)

### Application Security
- Admin panel disabled by default
- User signups disabled by default
- Secrets stored in Azure Key Vault (not in configuration)
- Container App uses managed identity for Key Vault access
- System-assigned managed identity for Azure resource access
- RBAC-based access control for Key Vault

## Scaling and High Availability

### Scaling Configuration
- **Min Replicas**: 1 (always at least one instance running)
- **Max Replicas**: 3 (can scale up based on load)
- **Auto-scaling**: Based on HTTP traffic and CPU/Memory metrics

### High Availability
- Zone redundancy available (set `zoneRedundant: true` in production)
- Automatic health checks and container restart
- Data persistence ensures no data loss during scaling events

### Performance Optimizations
- SQLite WAL mode enabled for better performance on network storage
- Dedicated subnet for optimal network performance
- CPU: 0.5 cores per replica
- Memory: 1 GB per replica

## Cost Breakdown

### Monthly Cost Estimates (East US)

| Resource | Configuration | Estimated Cost |
|----------|--------------|----------------|
| Container App | 0.5 vCPU, 1GB RAM, 1-3 replicas | $10-30 |
| Storage Account | Standard LRS, ~5GB data | $2-5 |
| Log Analytics | ~10GB/month logs | $2-10 |
| Virtual Network | Subnet, no additional charges | Free |
| **Total** | | **$14-45/month** |

### Cost Optimization Tips
1. Use smaller instance sizes for low-traffic deployments
2. Set min replicas to 0 for dev/test environments (with cold start trade-off)
3. Implement log filtering to reduce Log Analytics costs
4. Use lifecycle policies for storage account to clean old logs
5. Consider reserved instances for production workloads

## Deployment Process

### Pre-Deployment
1. Azure CLI and Bicep installed
2. Appropriate Azure subscription permissions
3. Optional: Custom domain DNS configured

### Deployment Steps
1. **Resource Group Creation**: Subscription-scoped deployment creates resource group
2. **Network Setup**: Virtual Network and subnet provisioned
3. **Storage Provisioning**: Storage account and file share created
4. **Monitoring Setup**: Log Analytics Workspace deployed
5. **Container Environment**: Container App Environment created in subnet
6. **Application Deployment**: Vaultwarden container deployed with configuration

### Post-Deployment
1. Verify container health status
2. Test application access via provided URL
3. Configure custom domain (if required)
4. Set up backup procedures
5. Configure monitoring alerts

## Monitoring and Operations

### Key Metrics to Monitor
- Container CPU and memory usage
- HTTP request count and response times
- Storage usage and IOPS
- Container restart count
- Failed authentication attempts

### Log Queries (KQL)

#### Recent Container Logs
```kql
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == "vaultwarden-dev-ca"
| order by TimeGenerated desc
| take 100
```

#### Error Logs
```kql
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == "vaultwarden-dev-ca"
| where Log_s contains "ERROR" or Log_s contains "error"
| order by TimeGenerated desc
```

#### HTTP Request Stats
```kql
ContainerAppSystemLogs_CL
| where ContainerAppName_s == "vaultwarden-dev-ca"
| summarize count() by ResultCode_s
```

## Backup and Disaster Recovery

### Backup Strategy
1. **Automated Backups**: Configure Azure Backup for File Share (optional)
2. **Manual Backups**: Use provided scripts to download data
3. **Frequency**: Daily backups recommended for production
4. **Retention**: 30 days minimum

### Recovery Procedures
1. Stop the container app to prevent new writes
2. Restore file share from backup
3. Restart the container app
4. Verify data integrity

### Business Continuity
- RTO (Recovery Time Objective): < 1 hour with automated restore
- RPO (Recovery Point Objective): < 24 hours with daily backups
- Cross-region replication available with geo-redundant storage

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
# Check container logs
az containerapp logs show --name <app-name> --resource-group <rg-name> --tail 50

# Check container app status
az containerapp show --name <app-name> --resource-group <rg-name>
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
az containerapp ingress show --name <app-name> --resource-group <rg-name>

# Verify container is running
az containerapp revision list --name <app-name> --resource-group <rg-name>
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
- [ ] Enable zone redundancy for high availability
- [ ] Set up Azure Monitor alerts
- [ ] Configure backup automation
- [ ] Review and restrict network access
- [ ] Enable Azure Defender for Container Apps
- [ ] Implement IP restrictions if needed
- [ ] Set up log retention policies
- [ ] Configure SMTP for email notifications
- [ ] Review and update Vaultwarden regularly

### Compliance Considerations
- Data residency: Resources deployed in specified Azure region
- Encryption: Data encrypted at rest and in transit
- Audit logs: Available through Log Analytics
- Access control: Azure RBAC for resource management
- Network isolation: VNET integration available

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
- Zero-downtime updates possible with blue-green deployment pattern

## Additional Resources

### Official Documentation
- [Vaultwarden Documentation](https://github.com/dani-garcia/vaultwarden/wiki)
- [Azure Container Apps](https://docs.microsoft.com/azure/container-apps/)
- [Azure Bicep](https://docs.microsoft.com/azure/azure-resource-manager/bicep/)
- [Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/)

### Community Resources
- [Vaultwarden Discussions](https://github.com/dani-garcia/vaultwarden/discussions)
- [Azure Container Apps Samples](https://github.com/Azure-Samples/container-apps-samples)

### Support Channels
- Vaultwarden Issues: GitHub Issues
- Azure Support: Azure Portal
- Community: Reddit r/Vaultwarden
