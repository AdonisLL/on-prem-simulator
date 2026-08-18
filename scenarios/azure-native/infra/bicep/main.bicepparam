using './main.bicep'

param namePrefix = 'opmlab'
param location = 'eastus2'
param adminUsername = 'labadmin'
// Supply adminPassword at deployment time or from a Key Vault reference.
param adminPassword = readEnvironmentVariable('ONPREM_LAB_ADMIN_PASSWORD')
