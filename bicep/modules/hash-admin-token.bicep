// ========================================
// Admin Token Hashing Module
// ========================================
// Uses a deployment script to hash the admin token with argon2id.
// This runs inside an Azure Container Instance during deployment,
// ensuring the plaintext token is never stored in Key Vault.
// Works with all deployment methods: GitHub Actions, Deploy to Azure button, and Azure CLI.

targetScope = 'resourceGroup'

@description('The plaintext admin token to hash with argon2id')
@secure()
param adminToken string

@description('The Azure region for the deployment script resources')
param location string

@description('Force new hash generation on each deployment')
param utcValue string = utcNow()

resource hashScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'hash-admin-token'
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
      pip install argon2-cffi --quiet
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

output hashedToken string = hashScript.properties.outputs.hashedToken
