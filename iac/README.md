# Infrastructure as Code (IaC) for OAuth 2.0 On-Behalf-Of POC

This directory contains Bicep templates for deploying the Azure infrastructure required for the OAuth 2.0 On-Behalf-Of (OBO) proof of concept with Azure API Management and Azure Kubernetes Service.

## Updated Components

### 1. Resource API Versions Updated ✅
All Azure resource providers have been updated to the latest stable API versions as of September 2025:

- **API Management**: `@2024-05-01`
- **Container Service (AKS)**: `@2025-01-01`
- **Container Registry**: `@2023-11-01-preview`
- **Key Vault**: `@2023-07-01`
- **Log Analytics**: `@2023-09-01`
- **Managed Identity**: `@2023-01-31`
- **Resource Groups**: `@2024-03-01`

### 2. Complete Azure Resource Deployment ✅

The Bicep templates now deploy all required Azure components:

#### Core Infrastructure
- **Resource Group**: Container for all resources
- **Azure Kubernetes Service (AKS)**: Container orchestration with workload identity enabled
- **Azure Container Registry (ACR)**: Container image storage
- **Key Vault**: Secrets management (optional for advanced scenarios)

#### API Management Setup
- **APIM Instance**: Developer tier with OAuth policy enforcement
- **Named Values**: Centralized configuration for OAuth parameters
- **Backend Configuration**: HTTPBin.org as testing backend
- **API Policies**: JWT validation and header injection

#### Observability
- **Log Analytics Workspace**: Centralized logging
- **Application Insights**: Performance monitoring and diagnostics
- **APIM Diagnostics**: API request/response logging

#### Security & Identity
- **User-Assigned Managed Identity**: For workload identity federation
- **Federated Identity Credentials**: Links AKS service accounts to Azure AD
- **App Registration placeholders**: Manual setup instructions provided

### 3. APIM API Definitions and OAuth OBO Policies ✅

The `main.bicepparam` file now includes complete APIM configuration:

#### HTTPBin API Configuration
```bicep
backends: [
  {
    name: 'httpbin'
    description: 'HTTPBin service for testing OAuth OBO flows'
    url: 'https://httpbin.org'
    protocol: 'http'
    services: [
      {
        name: 'httpbin-api'
        displayName: 'HTTPBin Test API'
        path: '/httpbin'
        operations: [...]
      }
    ]
  }
]
```

#### OAuth OBO Policy Implementation
The policy includes:
- **JWT Validation**: Validates access tokens against Azure AD
- **Audience Verification**: Ensures token is for the correct API
- **Scope Enforcement**: Requires `access_as_user` scope
- **Group-Based Authorization**: Maps user groups to API roles
- **Header Injection**: Adds `X-API-Key` and `X-User-Role` headers
- **Backend Routing**: Forwards to httpbin.org for testing

#### Policy Logic
```xml
<validate-jwt header-name="Authorization">
  <openid-config url="https://login.microsoftonline.com/{{tenant-id}}/.well-known/openid-configuration" />
  <required-claims>
    <claim name="aud">
      <value>api://{{api-app-id}}</value>
    </claim>
  </required-claims>
  <required-scopes>
    <scope>access_as_user</scope>
  </required-scopes>
</validate-jwt>
```

## Deployment Instructions

### Prerequisites
1. Azure CLI installed and authenticated
2. Bicep CLI installed
3. Contributor access to Azure subscription
4. PowerShell or Bash terminal

### 1. Deploy Infrastructure
```bash
# Set deployment parameters
export DEPLOYMENT_NAME="oauthpoc"
export DEPLOYMENT_SUFFIX="dev01" 
export DEPLOYMENT_LOCATION="eastus"

# Deploy the infrastructure
az deployment sub create \
  --location $DEPLOYMENT_LOCATION \
  --template-file main.bicep \
  --parameters main.bicepparam
```

### 2. Manual Configuration Required

#### Azure AD App Registrations
The Bicep templates cannot directly create Azure AD app registrations. Follow these steps:

1. **Create API App Registration**:
   ```bash
   az ad app create \
     --display-name "OAuth OBO API" \
     --identifier-uris "api://your-api-app-id"
   ```

2. **Create Client App Registration**:
   ```bash
   az ad app create \
     --display-name "OAuth OBO Client" \
     --public-client-redirect-uris "https://your-aks-fqdn/signin-oidc"
   ```

3. **Configure Permissions**:
   - Grant Client App permission to access API App
   - Configure admin consent for delegated permissions
   - Enable group claims in token configuration

#### Update APIM Named Values
After creating app registrations, update the APIM named values:

```bash
# Update API App ID
az rest \
  --method PUT \
  --url "https://management.azure.com/subscriptions/{subscription-id}/resourceGroups/{rg-name}/providers/Microsoft.ApiManagement/service/{apim-name}/namedValues/api-app-id" \
  --body '{"properties": {"value": "your-actual-api-app-id"}}'

# Update Admin Group ID  
az rest \
  --method PUT \
  --url "https://management.azure.com/subscriptions/{subscription-id}/resourceGroups/{rg-name}/providers/Microsoft.ApiManagement/service/{apim-name}/namedValues/admin-group-id" \
  --body '{"properties": {"value": "your-actual-admin-group-id"}}'
```

### 3. Kubernetes Configuration

Deploy the OAuth OBO client application to AKS with workload identity:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: oauth-obo-sa
  namespace: default
  annotations:
    azure.workload.identity/client-id: "{your-managed-identity-client-id}"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: oauth-obo-client
spec:
  template:
    metadata:
      labels:
        azure.workload.identity/use: "true"
    spec:
      serviceAccountName: oauth-obo-sa
      containers:
      - name: oauth-client
        image: your-registry/oauth-obo-client:latest
        env:
        - name: AZURE_CLIENT_ID
          value: "{your-client-app-id}"
        - name: AZURE_TENANT_ID
          value: "{your-tenant-id}"
        - name: APIM_BASE_URL
          value: "https://{your-apim-name}.azure-api.net/httpbin"
```

## Testing the OAuth OBO Flow

### 1. Test JWT Validation
```bash
# Get an access token (replace with your values)
TOKEN=$(az account get-access-token --resource api://your-api-app-id --query accessToken -o tsv)

# Test API call
curl -H "Authorization: Bearer $TOKEN" \
     https://your-apim-name.azure-api.net/httpbin/test
```

### 2. Verify Header Injection
The HTTPBin response should include injected headers:
```json
{
  "headers": {
    "Authorization": "Bearer ...",
    "X-Api-Key": "STANDARD",
    "X-User-Role": "user"
  }
}
```

### 3. Test Group-Based Authorization
- Users in the admin group should receive `X-API-Key: ADMIN`
- Standard users should receive `X-API-Key: STANDARD`

## Architecture Overview

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   .NET Client   │───▶│   Azure APIM     │───▶│   HTTPBin.org   │
│   (AKS Pod)     │    │  OAuth Policies  │    │  (Test Backend) │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │
         ▼                       ▼
┌─────────────────┐    ┌──────────────────┐
│ Workload Identity│    │   Azure AD       │
│ Federation      │    │  App Registrations│
└─────────────────┘    └──────────────────┘
```

## Security Considerations

1. **Workload Identity**: Eliminates need for client secrets in AKS
2. **JWT Validation**: Ensures tokens are valid and audience-specific
3. **Group Claims**: Enables fine-grained authorization
4. **HTTPS Only**: All communication encrypted in transit
5. **Named Values**: Centralized configuration management

## Troubleshooting

### Common Issues
1. **JWT Validation Fails**: Check tenant ID and API app ID in named values
2. **Group Claims Missing**: Enable group claims in Azure AD app manifest
3. **Token Audience Mismatch**: Verify API app ID URI configuration
4. **Workload Identity Issues**: Check federated credential configuration

### Diagnostic Commands
```bash
# Check APIM logs
az monitor activity-log list --resource-group {rg-name}

# Verify named values
az apim nv list --service-name {apim-name} --resource-group {rg-name}

# Test token validation
az ad app show --id {api-app-id}
```

## Next Steps

1. Deploy .NET client application with MSAL integration
2. Implement authorization code flow with PKCE
3. Test end-to-end OBO token exchange
4. Add monitoring and alerting
5. Implement token caching and refresh logic

## Files Structure

```
iac/
├── main.bicep              # Main deployment template
├── main.bicepparam         # Deployment parameters with OAuth config
├── types.bicep             # Type definitions
├── modules/
│   ├── apim.bicep          # API Management configuration
│   ├── aks.bicep           # Azure Kubernetes Service
│   ├── acr.bicep           # Azure Container Registry
│   ├── insights.bicep      # Application Insights
│   ├── vault.bicep         # Key Vault (optional)
│   ├── apim/
│   │   ├── backend.bicep   # APIM backend configuration
│   │   ├── service.bicep   # APIM API service configuration
│   │   └── operation.bicep # APIM API operations
│   └── security/
│       ├── identity.bicep      # Managed identity
│       ├── credential.bicep    # Federated credentials
│       ├── application.bicep   # App registration placeholders
│       └── acr-access.bicep    # ACR access for AKS
└── README.md               # This file
```