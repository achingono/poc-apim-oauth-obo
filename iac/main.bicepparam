using 'main.bicep'

param name = readEnvironmentVariable('DEPLOYMENT_NAME', 'airloge')
param suffix = readEnvironmentVariable('DEPLOYMENT_SUFFIX', 'dev')
param location = readEnvironmentVariable('DEPLOYMENT_LOCATION', 'eastus')
