---
layout: default
title: Backup and Recovery
---

# Backup and Recovery

This document explains the backup and recovery strategy for Vaultwarden data stored in Azure Database for PostgreSQL Flexible Server.

## Overview

Azure Database for PostgreSQL Flexible Server provides **built-in automated backups** with no additional configuration required. Backups are automatically enabled when the PostgreSQL server is provisioned.

### Backup Features

- **Automatic daily backups**: Full snapshots taken automatically
- **Point-in-time restore (PITR)**: Restore to any point within the retention period
- **7-day retention**: Default backup retention period (configurable up to 35 days)
- **Geo-redundant backup**: Available as an upgrade option for disaster recovery
- **No manual setup required**: Backups are managed entirely by Azure

## Backup Configuration

The PostgreSQL Flexible Server is deployed with the following backup settings:

| Setting | Value |
|---------|-------|
| **Backup retention** | 7 days |
| **Backup type** | Automated full + incremental |
| **Point-in-time restore** | Supported (within retention period) |
| **Geo-redundancy** | Disabled (can be enabled for DR) |

## Recovery Procedures

### Point-in-Time Restore

Restore the database to any point within the retention period:

```bash
# Restore to a specific point in time
az postgres flexible-server restore \
  --resource-group vaultwarden-dev-rg \
  --name vaultwarden-dev-psql-restored \
  --source-server vaultwarden-dev-psql \
  --restore-time "2024-01-15T10:30:00Z"
```

**Note**: This creates a new server with the restored data. You will need to update the `DATABASE_URL` secret in Key Vault to point to the new server.

### Manual Backup with pg_dump

For additional backup control, use `pg_dump`:

```bash
# Set variables
RESOURCE_GROUP="vaultwarden-dev-rg"
SERVER_NAME="vaultwarden-dev-psql"
DB_NAME="vaultwarden"
ADMIN_USER="vaultwardenadmin"

# Get the server FQDN
FQDN=$(az postgres flexible-server show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$SERVER_NAME" \
  --query "fullyQualifiedDomainName" -o tsv)

# Create a backup (requires network access to the server)
pg_dump "postgresql://${ADMIN_USER}:<password>@${FQDN}:5432/${DB_NAME}?sslmode=require" \
  --file vaultwarden-backup.sql
```

**Note**: Since the PostgreSQL server is VNet-integrated (private access only), `pg_dump` must be run from a machine with network access to the VNet (e.g., an Azure VM in the same VNet, or via VPN/ExpressRoute).

### Restore from pg_dump

```bash
# Restore from a backup file
psql "postgresql://${ADMIN_USER}:<password>@${FQDN}:5432/${DB_NAME}?sslmode=require" \
  --file vaultwarden-backup.sql
```

## Verifying Backups

### Check Backup Status

```bash
az postgres flexible-server show \
  --resource-group vaultwarden-dev-rg \
  --name vaultwarden-dev-psql \
  --query "{backupRetentionDays:backup.backupRetentionDays, geoRedundantBackup:backup.geoRedundantBackup, earliestRestoreDate:backup.earliestRestoreDate}"
```

## Data Protection

In addition to automated backups, the deployment includes:

- **CanNotDelete resource lock** on the PostgreSQL server to prevent accidental deletion
- **VNet integration** ensures the database is only accessible within the private network
- **SSL enforcement** for all database connections
- **Encryption at rest** managed by Azure

## Troubleshooting

### Cannot Restore to a Specific Point in Time

**Cause**: The requested restore time is outside the backup retention window.

**Solution**: Check the earliest available restore point:
```bash
az postgres flexible-server show \
  --resource-group vaultwarden-dev-rg \
  --name vaultwarden-dev-psql \
  --query "backup.earliestRestoreDate"
```

### Restore Creates a New Server

**Expected behavior**: Point-in-time restore always creates a new server. After verifying the restored data:
1. Update the `DATABASE_URL` secret in Key Vault with the new server's connection string
2. Restart the App Service to pick up the new connection
3. Delete the old server when no longer needed

## See Also

- [Azure Database for PostgreSQL - Backup and Restore](https://learn.microsoft.com/azure/postgresql/flexible-server/concepts-backup-restore)
- [Point-in-Time Restore](https://learn.microsoft.com/azure/postgresql/flexible-server/how-to-restore-server-portal)
- [Architecture Overview]({% link ARCHITECTURE.md %})
