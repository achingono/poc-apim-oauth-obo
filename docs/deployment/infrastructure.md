# Infrastructure Deployment Guide

This document provides detailed information about deploying the Azure infrastructure for the OAuth OBO POC.

## Table of Contents

- [Overview](#overview)
- [Infrastructure Components](#infrastructure-components)
- [Bicep Templates](#bicep-templates)
- [Deployment Process](#deployment-process)
- [Configuration Parameters](#configuration-parameters)
- [Post-Deployment Configuration](#post-deployment-configuration)
- [Troubleshooting](#troubleshooting)

## Overview

The infrastructure is defined using Azure Bicep templates and deployed at the subscription scope. All resources are created in a single resource group for easy management.

**Deployment Method**: Azure Bicep (Infrastructure as Code)  
**Deployment Scope**: Subscription-level  
**Deployment Time**: ~3-4 minutes  
**Automation**: Fully automated via `deploy.sh` script

## Infrastructure Components

### Resource Group

**Name Format**: `rg-{name}-{suffix}-{location}`

**Purpose**: Container for all project resources

**Lifecycle**: Created first, destroyed last

### Azure Kubernetes Service (AKS)

**Name Format**: `aks-{name}-{suffix}`

**Configuration:**
- **Node Count**: 2 nodes (default)
- **VM Size**: Standard_DS2_v2
- **Kubernetes Version**: Latest stable
- **Network Plugin**: kubenet
- **Load Balancer**: Standard
- **Workload Identity**: Enabled
- **OIDC Issuer**: Enabled

**Features:**
- Managed identity
- Container Insights integration
- Automatic upgrades enabled
- Web Application Routing addon

**Bicep Module**: `modules/aks.bicep`

### Azure API Management (APIM)

**Name Format**: `apim-{name}-{suffix}`

**Configuration:**
- **SKU**: Developer (for POC)
- **Capacity**: 1 unit
- **Publisher Email**: Configurable
- **Publisher Name**: Configurable
- **Virtual Network**: None (External option available)

**Features:**
- Managed identity for Key Vault access
- Named values synchronized from Key Vault
- Application Insights integration
- OAuth validation policies
- CORS policy
- HTTPBin backend configuration

**Bicep Module**: `modules/apim.bicep`

### Azure Key Vault

**Name Format**: `kv-{name}-{suffix}`

**Configuration:**
- **SKU**: Standard
- **Access Control**: RBAC (not access policies)
- **Soft Delete**: Enabled
- **Purge Protection**: Disabled (for POC)

**Stored Secrets:**
- `tenant-id`: Azure AD tenant ID
- `api-app-id`: API application ID
- `client-app-id`: Client application ID
- `admin-group-id`: Admin security group ID
- `standard-group-id`: Standard user group ID

**Access:**
- APIM managed identity: Key Vault Secrets User role
- Deployment identity: Key Vault Administrator role (temporary)

**Bicep Module**: `modules/vault.bicep`

### Azure Container Registry (ACR)

**Name Format**: `acr{name}{suffix}{uniqueString}`

**Configuration:**
- **SKU**: Basic
- **Admin User**: Enabled
- **Public Network Access**: Enabled

**Purpose:**
- Store Docker images for client application
- Integrated with AKS for image pulling

**Bicep Module**: `modules/acr.bicep`

### Managed Identity

**Name Format**: `id-{name}-{suffix}`

**Purpose:**
- Workload identity for Kubernetes pods
- Federated credential for OIDC exchange
- No secrets required in pods

**Federated Credential:**
- **Subject**: `system:serviceaccount:{namespace}:{serviceAccountName}`
- **Issuer**: AKS OIDC issuer URL
- **Audience**: `api://AzureADTokenExchange`

**Bicep Module**: `modules/security/identity.bicep`

### Application Insights

**Name Format**: `appi-{name}-{suffix}`

**Configuration:**
- **Type**: Web
- **Workspace**: Log Analytics workspace

**Integration:**
- APIM sends telemetry
- Application sends logs (optional)
- Performance monitoring
- Request tracking

**Bicep Module**: `modules/insights.bicep`

## Bicep Templates

### File Structure

```
iac/
├── main.bicep                 # Entry point
├── main.bicepparam           # Parameters
├── types.bicep               # Type definitions
├── modules/
│   ├── acr.bicep            # Container Registry
│   ├── aks.bicep            # Kubernetes Service
│   ├── apim.bicep           # API Management
│   ├── insights.bicep       # Application Insights
│   ├── secrets.bicep        # Key Vault secrets
│   ├── vault.bicep          # Key Vault
│   ├── apim/
│   │   ├── backend.bicep    # APIM backend
│   │   ├── service.bicep    # APIM API
│   │   ├── operation.bicep  # APIM operations
│   │   └── vaultPolicy.bicep # Key Vault policy
│   └── security/
│       ├── identity.bicep         # Managed identity
│       ├── credential.bicep       # Federated credentials
│       ├── acr-access.bicep       # ACR role assignments
│       └── keyvault-rbac.bicep    # Key Vault RBAC
└── policies/
    ├── oauth-policy.xml      # OAuth JWT validation
    └── global-policy.xml     # Global CORS policy
```

### Main Template (main.bicep)

**Purpose**: Orchestrates all resource deployments

**Key Sections:**
1. Parameter definitions
2. Variable calculations
3. Resource group creation
4. Module orchestration
5. Output definitions

**Dependencies:**
```
Resource Group
  ↓
├─ Insights (Log Analytics + App Insights)
├─ ACR (if not using external)
├─ Key Vault (if not using external)
│   ↓
│   └─ Secrets
└─ AKS
    ↓
    ├─ Managed Identity
    │   ↓
    │   └─ Federated Credential
    └─ APIM
        ↓
        ├─ Key Vault RBAC
        ├─ Named Values (from Key Vault)
        └─ API Configuration
            ↓
            └─ OAuth Policy
```

### Module: AKS (modules/aks.bicep)

**Parameters:**
- `name`: Cluster name
- `location`: Azure region
- `nodeCount`: Number of nodes (default: 2)
- `nodeVMSize`: VM size (default: Standard_DS2_v2)
- `logAnalyticsWorkspaceId`: For Container Insights

**Resources Created:**
- AKS cluster with system-assigned managed identity
- Node pool
- OIDC issuer configuration
- Workload identity enablement

**Outputs:**
- `clusterName`: Name of AKS cluster
- `oidcIssuerUrl`: OIDC issuer URL for federated credentials
- `kubeletIdentityObjectId`: Object ID of kubelet identity

### Module: APIM (modules/apim.bicep)

**Parameters:**
- `name`: APIM service name
- `location`: Azure region
- `publisherEmail`: Publisher email
- `publisherName`: Publisher name
- `sku`: SKU tier (default: Developer)
- `namedValues`: Configuration values
- `keyVaultName`: Key Vault for secrets
- `policies`: Policy configurations

**Resources Created:**
- APIM service with system-assigned managed identity
- Named values (synchronized from Key Vault)
- HTTPBin API
- Test operation (GET /test)
- OAuth validation policy
- Backend configuration

**Outputs:**
- `apimName`: Name of APIM service
- `gatewayUrl`: APIM gateway URL
- `managedIdentityObjectId`: Object ID for RBAC assignments

### Module: Key Vault (modules/vault.bicep)

**Parameters:**
- `name`: Key Vault name
- `location`: Azure region
- `skuName`: SKU tier (default: standard)
- `enableRbacAuthorization`: Use RBAC (default: true)

**Resources Created:**
- Key Vault with RBAC enabled
- Diagnostic settings (optional)

**Outputs:**
- `vaultName`: Name of Key Vault
- `vaultUri`: Key Vault URI

### Module: Secrets (modules/secrets.bicep)

**Parameters:**
- `keyVaultName`: Target Key Vault
- `secrets`: Array of secret objects

**Secret Structure:**
```bicep
{
  name: 'secret-name'
  value: 'secret-value'
}
```

**Resources Created:**
- One secret resource per input

## Deployment Process

### Automated Deployment

The `deploy.sh` script handles the entire deployment process:

```bash
./deploy.sh -n oauth-obo -l eastus -s poc
```

**Script Steps:**
1. Validate parameters
2. Create app registrations
3. Deploy infrastructure
4. Configure RBAC
5. Build and push images
6. Deploy to Kubernetes

### Manual Deployment

#### Step 1: Prepare Parameters

Create or edit `main.bicepparam`:

```bicep
using 'main.bicep'

param name = 'oauth-obo'
param location = 'eastus'
param suffix = 'poc'
param gateway = {
  publisher: {
    name: 'OAuth OBO POC'
    email: 'admin@example.com'
  }
}
param namedValues = [
  {
    name: 'tenant-id'
    displayName: 'tenant_id'
    value: '<tenant-id>'
    secret: false
  }
  {
    name: 'api-app-id'
    displayName: 'api_app_id'
    secret: true
    keyVaultSecretName: 'api-app-id'
  }
  // ... more named values
]
```

#### Step 2: Deploy Infrastructure

```bash
cd iac

# Validate template
az bicep build --file main.bicep

# Preview changes
az deployment sub what-if \
  --location eastus \
  --template-file main.bicep \
  --parameters main.bicepparam

# Deploy
az deployment sub create \
  --name oauth-obo-deployment \
  --location eastus \
  --template-file main.bicep \
  --parameters main.bicepparam
```

#### Step 3: Get Outputs

```bash
# Get all outputs
az deployment sub show \
  --name oauth-obo-deployment \
  --query properties.outputs

# Get specific output
az deployment sub show \
  --name oauth-obo-deployment \
  --query properties.outputs.gatewayUrl.value \
  -o tsv
```

## Configuration Parameters

### Required Parameters

| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `name` | string | Base name (3-21 chars) | `oauth-obo` |
| `location` | string | Azure region | `eastus` |
| `suffix` | string | Unique suffix (3-23 chars) | `poc` |

### Optional Parameters

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `gateway.publisher.name` | string | APIM publisher name | `OAuth OBO POC` |
| `gateway.publisher.email` | string | APIM publisher email | `admin@example.com` |
| `registry` | object | External ACR details | `null` (creates new) |
| `vault` | object | External Key Vault details | `null` (creates new) |

### Named Values Configuration

Named values are configuration parameters used in APIM policies.

**Structure:**
```bicep
{
  name: 'secret-name'           // Key Vault secret name
  displayName: 'display_name'   // Name used in policies {{display_name}}
  secret: true                  // Mark as secret
  keyVaultSecretName: 'secret-name'  // Key Vault reference
}
```

**Example:**
```bicep
param namedValues = [
  {
    name: 'tenant-id'
    displayName: 'tenant_id'
    value: '<tenant-id>'
    secret: false
  }
  {
    name: 'api-app-id'
    displayName: 'api_app_id'
    secret: true
    keyVaultSecretName: 'api-app-id'
  }
]
```

## Post-Deployment Configuration

### Configure AKS Credentials

```bash
# Get AKS credentials
az aks get-credentials \
  --resource-group rg-oauth-obo-poc-eastus \
  --name aks-oauth-obo-poc

# Verify connection
kubectl get nodes
```

### Enable Ingress

```bash
# Enable Web Application Routing
az aks approuting enable \
  --resource-group rg-oauth-obo-poc-eastus \
  --name aks-oauth-obo-poc
```

### Configure ACR Access

```bash
# Attach ACR to AKS (if not done in template)
az aks update \
  --resource-group rg-oauth-obo-poc-eastus \
  --name aks-oauth-obo-poc \
  --attach-acr acroauthobo
```

### Verify Named Values Sync

```bash
# List named values
az apim nv list \
  --service-name apim-oauth-obo-poc \
  --resource-group rg-oauth-obo-poc-eastus

# Check specific value
az apim nv show \
  --service-name apim-oauth-obo-poc \
  --resource-group rg-oauth-obo-poc-eastus \
  --named-value-id api_app_id
```

## Troubleshooting

### Issue: Deployment Fails with "Invalid Template"

**Symptoms**: Deployment fails during validation

**Solutions:**
```bash
# Validate Bicep syntax
az bicep build --file main.bicep

# Check for errors in output
# Fix any syntax errors in Bicep files
```

### Issue: Key Vault Access Denied

**Symptoms**: APIM cannot read secrets from Key Vault

**Solutions:**
```bash
# Check RBAC assignments
az role assignment list \
  --scope /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<kv> \
  --assignee <apim-identity-object-id>

# Assign role if missing
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee <apim-identity-object-id> \
  --scope /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<kv>
```

### Issue: Named Values Not Syncing

**Symptoms**: Named values show as empty or not found

**Solutions:**
```bash
# Check named value status
az apim nv show \
  --service-name <apim-name> \
  --resource-group <rg-name> \
  --named-value-id api_app_id \
  --query "properties.{value:value,secret:secret,keyVault:keyVault}"

# Manually refresh (if needed)
# Navigate to Azure Portal → APIM → Named values → Refresh
```

### Issue: AKS Cluster Not Accessible

**Symptoms**: kubectl commands fail

**Solutions:**
```bash
# Check cluster status
az aks show \
  --resource-group <rg-name> \
  --name <aks-name> \
  --query provisioningState

# Get credentials again
az aks get-credentials \
  --resource-group <rg-name> \
  --name <aks-name> \
  --overwrite-existing

# Verify connection
kubectl cluster-info
```

### Issue: OIDC Issuer Not Enabled

**Symptoms**: Workload identity setup fails

**Solutions:**
```bash
# Check OIDC status
az aks show \
  --resource-group <rg-name> \
  --name <aks-name> \
  --query oidcIssuerProfile.enabled

# Enable OIDC issuer
az aks update \
  --resource-group <rg-name> \
  --name <aks-name> \
  --enable-oidc-issuer

# Enable workload identity
az aks update \
  --resource-group <rg-name> \
  --name <aks-name> \
  --enable-workload-identity
```

## Infrastructure Updates

### Update APIM Policy

```bash
# Edit policy file
vi iac/policies/oauth-policy.xml

# Redeploy infrastructure
az deployment sub create \
  --name oauth-obo-deployment \
  --location eastus \
  --template-file iac/main.bicep \
  --parameters iac/main.bicepparam
```

### Scale AKS Cluster

```bash
# Scale node count
az aks scale \
  --resource-group rg-oauth-obo-poc-eastus \
  --name aks-oauth-obo-poc \
  --node-count 3
```

### Update Named Values

```bash
# Update secret in Key Vault
az keyvault secret set \
  --vault-name kv-oauth-obo-poc \
  --name api-app-id \
  --value "new-value"

# APIM will sync automatically
# Or force refresh in Azure Portal
```

## Related Documentation

- [Architecture Overview](../architecture/overview.md)
- [APIM Configuration](../architecture/apim.md)
- [Deployment Overview](overview.md)
- [Infrastructure as Code README](../../iac/README.md)
- [Lessons Learned](../lessons-learned.md)
