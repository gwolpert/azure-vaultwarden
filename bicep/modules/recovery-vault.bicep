// ========================================
// Recovery Services Vault Module
// ========================================

targetScope = 'resourceGroup'

@description('The base name for resources (without suffixes)')
param baseName string

@description('The Azure region where resources will be deployed')
param location string

// Build the full Recovery Services Vault name using naming convention
// Recovery Services Vault name must be 2-50 characters, alphanumeric and hyphens
// Pattern: {baseName}-rsv
var recoveryServicesVaultName = '${baseName}-rsv'

// Deploy Recovery Services Vault for backup
module recoveryVaultDeployment 'br/public:avm/res/recovery-services/vault:0.8.0' = {
  name: 'recovery-vault-deployment'
  params: {
    name: recoveryServicesVaultName
    location: location
    backupPolicies: [
      {
        name: 'vaultwarden-daily-backup-policy'
        properties: {
          backupManagementType: 'AzureStorage'
          workloadType: 'AzureFileShare'
          schedulePolicy: {
            schedulePolicyType: 'SimpleSchedulePolicy'
            scheduleRunFrequency: 'Daily'
            scheduleRunTimes: [
              '2024-01-01T02:00:00Z'  // Daily backup at 2 AM UTC
            ]
          }
          retentionPolicy: {
            retentionPolicyType: 'LongTermRetentionPolicy'
            dailySchedule: {
              retentionTimes: [
                '2024-01-01T02:00:00Z'
              ]
              retentionDuration: {
                count: 30
                durationType: 'Days'
              }
            }
          }
          timeZone: 'UTC'
        }
      }
    ]
  }
}

output name string = recoveryVaultDeployment.outputs.name
output resourceId string = recoveryVaultDeployment.outputs.resourceId
