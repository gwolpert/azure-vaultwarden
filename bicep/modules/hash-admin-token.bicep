// ========================================
// Admin Token Hashing Module
// ========================================
// Uses a deployment script to hash the admin token with argon2id
// and stores the hashed token directly in Key Vault.
// This runs inside an Azure Container Instance during deployment,
// ensuring the plaintext token is never stored in Key Vault.
// Works with all deployment methods: GitHub Actions, Deploy to Azure button, and Azure CLI.

targetScope = 'resourceGroup'

@description('The base name for resources (without suffixes)')
param baseName string

@description('The plaintext admin token to hash with argon2id')
@secure()
param adminToken string

@description('The name of the Key Vault to store the hashed token in')
param keyVaultName string

@description('The Azure region for the deployment script resources')
param location string

@description('Force new hash generation on each deployment')
param utcValue string = utcNow()

// Reference the existing Key Vault to store the hashed admin token
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' existing = {
  name: keyVaultName
}

resource hashScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: '${baseName}-hash-token-script'
  location: location
  kind: 'AzureCLI'
  properties: {
    azCliVersion: '2.63.0'
    retentionInterval: 'PT1H'
    timeout: 'PT10M'
    cleanupPreference: 'Always'
    forceUpdateTag: utcValue
    environmentVariables: [
      {
        name: 'ADMIN_TOKEN'
        secureValue: adminToken
      }
    ]
    scriptContent: '''
      set -e
      python3 -m pip install --quiet 'argon2-cffi==23.1.0'
      python3 << 'PYEOF'
import argon2, os, json

token = os.environ['ADMIN_TOKEN']

# Skip hashing if the token is already an argon2 PHC string
if token.startswith('$argon2'):
    hashed = token
else:
    hasher = argon2.PasswordHasher(
        time_cost=3,
        memory_cost=65540,
        parallelism=4,
        type=argon2.Type.ID
    )
    hashed = hasher.hash(token)

with open(os.environ['AZ_SCRIPTS_OUTPUT_PATH'], 'w') as f:
    json.dump({'hashedToken': hashed}, f)
PYEOF
    '''
  }
}

// Store the hashed admin token directly in Key Vault
resource adminTokenSecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = {
  parent: keyVault
  name: 'vaultwarden-admin-token'
  properties: {
    value: hashScript.properties.outputs.hashedToken
  }
}

output adminTokenSecretUri string = adminTokenSecret.properties.secretUri
