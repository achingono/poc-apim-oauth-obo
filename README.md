# OAuth 2.0 On-Behalf-Of with Azure APIM & Kubernetes Workload Identity

A proof-of-concept demonstrating OAuth 2.0 On-Behalf-Of (OBO) flow with Azure API Management (APIM) and Kubernetes Workload Identity for secure service-to-service communication.

## Overview

This repository contains a complete implementation of OAuth OBO authentication patterns for Azure-based microservices, including:

- **Infrastructure as Code (IaC)**: Bicep templates for deploying Azure resources (APIM, AKS, Key Vault, etc.)
- **.NET Client Application**: ASP.NET Core web application with OAuth authentication and chat-like interface
- **Helm Charts**: Kubernetes deployment configurations for AKS and local development
- **Documentation**: Comprehensive requirements and integration guides

## Architecture

```
User Browser
    ↓ (OAuth Login - Authorization Code Flow + PKCE)
.NET Client Web App
    ↓ (Azure AD Authentication)
Token Acquisition Service
    ├─ (AKS) Azure Workload Identity (Federated Credentials)
    └─ (Local) Client Secret Authentication
    ↓ (Bearer Token with OBO)
Azure API Management
    ├─ JWT Validation
    ├─ Group-Based Authorization
    └─ Header Injection (X-API-Key, X-User-Role)
    ↓
HTTPBin Backend (Test Service)
```

## Key Features

### Authentication & Authorization
- **User Authentication**: Authorization Code Flow with PKCE for secure web authentication
- **Environment-Aware Token Acquisition**: 
  - Production (AKS): Azure Workload Identity with federated credentials (no secrets)
  - Development (Local): Traditional Client ID + Client Secret
- **OBO Token Exchange**: Acquire downstream API tokens on behalf of authenticated users
- **Group-Based Authorization**: Map Azure AD groups to API access levels

### Infrastructure
- **Azure API Management**: JWT validation, policy-based routing, header injection
- **Azure Kubernetes Service (AKS)**: Container orchestration with workload identity
- **Azure Key Vault**: Secure secret management
- **Azure Container Registry**: Private container image registry

### Application
- **Chat-Like Interface**: Interactive UI for testing OAuth flows
- **Real-Time Token Validation**: Immediate feedback on authentication status
- **Response Analysis**: Parse and display API responses including injected headers

## Repository Structure

```
.
├── docs/                     # Requirements and design documentation
│   └── requirements.md       # Detailed POC requirements
├── iac/                      # Infrastructure as Code (Bicep)
│   ├── main.bicep           # Main infrastructure template
│   ├── main.bicepparam      # Configuration parameters
│   ├── modules/             # Reusable Bicep modules
│   ├── policies/            # APIM policy definitions
│   └── README.md            # Infrastructure deployment guide
├── helm/                     # Kubernetes Helm charts
│   └── oauth-obo-client/    # Client application chart
│       ├── templates/       # Kubernetes resource templates
│       ├── values.yaml      # Default values
│       ├── values-aks.yaml  # AKS-specific values
│       ├── values-local.yaml # Local development values
│       └── README.md        # Helm deployment guide
├── src/                      # Source code
│   ├── OAuthOboClient/      # .NET client application
│   │   ├── Services/        # Token acquisition and API services
│   │   ├── Pages/           # Razor Pages UI
│   │   ├── Dockerfile       # Container definition
│   │   └── README.md        # Application documentation
│   └── README.md            # Source code overview
└── README.md                # This file
```

## Getting Started

### Prerequisites

- **Azure Subscription**: For deploying infrastructure
- **Azure CLI**: For authentication and deployment
- **.NET 9.0 SDK**: For building the client application
- **Docker**: For containerization
- **Kubernetes/Helm**: For deployment (AKS or local minikube)

### Quick Start

#### 1. Deploy Infrastructure

```bash
cd iac
az login
az deployment sub create \
  --location eastus \
  --template-file main.bicep \
  --parameters main.bicepparam
```

See [iac/README.md](iac/README.md) for detailed infrastructure setup.

#### 2. Build and Run the Client Application

**Local Development:**

```bash
cd src/OAuthOboClient

# Set environment variables
export ENVIRONMENT=Development
export AZURE_CLIENT_ID=<your-client-id>
export AZURE_CLIENT_SECRET=<your-client-secret>
export AZURE_TENANT_ID=<your-tenant-id>
export API_APP_ID=<your-api-app-id>
export OAUTH_SCOPE=access_as_user
export APIM_BASE_URL=https://<your-apim>.azure-api.net/httpbin

# Run the application
dotnet run
```

Navigate to `https://localhost:5001` to access the chat interface.

See [src/OAuthOboClient/README.md](src/OAuthOboClient/README.md) for detailed application documentation.

#### 3. Deploy to Kubernetes

**AKS (Production):**

```bash
cd helm
helm install oauth-obo-client ./oauth-obo-client \
  -f ./oauth-obo-client/values-aks.yaml \
  --set azure.tenantId=<tenant-id> \
  --set azure.clientId=<client-id> \
  --set azure.apiAppId=<api-app-id> \
  --set apim.baseUrl=<apim-base-url> \
  --set workloadIdentity.clientId=<managed-identity-client-id>
```

**Local Minikube (Development):**

```bash
helm install oauth-obo-client ./oauth-obo-client \
  -f ./oauth-obo-client/values-local.yaml \
  --set azure.tenantId=<tenant-id> \
  --set azure.clientId=<client-id> \
  --set azure.clientSecret=<client-secret> \
  --set azure.apiAppId=<api-app-id> \
  --set apim.baseUrl=<apim-base-url>
```

See [helm/oauth-obo-client/README.md](helm/oauth-obo-client/README.md) for detailed Helm deployment guide.

## Application UI

![OAuth OBO Chat Interface](https://github.com/user-attachments/assets/12b4e367-4826-44f5-be17-d38371f473fc)

The application provides an AI-style chat interface where:
- Users can send messages that trigger API calls through APIM
- Responses show complete request details including OAuth headers
- Chat history is maintained during the session
- Users can clear chat history or logout to switch accounts

## Configuration

### Required Azure Resources

1. **Azure AD App Registrations**:
   - Client Application (for user authentication)
   - API Application (for downstream API)

2. **Azure Resources**:
   - API Management instance
   - AKS cluster (with OIDC issuer and workload identity enabled)
   - Managed Identity (for AKS workload identity)
   - Key Vault (for secret management)
   - Container Registry (for container images)

3. **Azure AD Configuration**:
   - User groups for authorization
   - Federated credentials for workload identity
   - API permissions and scopes

### Environment Variables

See [src/OAuthOboClient/.env.example](src/OAuthOboClient/.env.example) for a complete list of required environment variables.

## Development Workflow

### Local Development

1. Configure Azure AD app registrations
2. Deploy APIM infrastructure with OAuth policies
3. Set environment variables for local development
4. Run the application with `dotnet run`
5. Test OAuth flows through the chat interface

### Container Development

1. Build Docker image: `cd src/OAuthOboClient && ./build.sh`
2. Run container locally with environment variables
3. Test authentication and API calls

### Kubernetes Deployment

1. Deploy to AKS or local minikube
2. Configure workload identity (AKS) or client secret (local)
3. Verify pod logs for successful token acquisition
4. Test end-to-end OAuth OBO flow

## Testing

### Manual Testing

1. **Login Flow**: Verify user can authenticate with Azure AD
2. **Token Acquisition**: Check logs for successful token retrieval
3. **API Calls**: Send messages and verify APIM responses
4. **Header Injection**: Confirm X-API-Key and X-User-Role headers
5. **Group Authorization**: Test different user groups get different access levels
6. **Logout Flow**: Verify users can logout and login as different users

### Automated Testing

The application validates:
- JWT token structure and claims
- OBO token exchange success
- APIM policy enforcement
- Header injection by APIM
- HTTPBin response parsing

## Troubleshooting

### Common Issues

1. **Authentication Fails**: 
   - Verify Azure AD app registration redirect URIs
   - Check client ID and tenant ID are correct
   - Ensure API permissions are granted

2. **Token Acquisition Fails**:
   - Local: Verify client secret is correct
   - AKS: Check workload identity and federated credentials

3. **APIM Returns 401**:
   - Verify JWT validation policy in APIM
   - Check audience and scope claims in token
   - Confirm named values in APIM are correct

4. **Workload Identity Not Working**:
   - Ensure AKS has OIDC issuer enabled
   - Verify federated credential configuration
   - Check service account annotations

See individual README files for component-specific troubleshooting.

## Documentation

- **Requirements**: [docs/requirements.md](docs/requirements.md) - Detailed POC requirements and design
- **Infrastructure**: [iac/README.md](iac/README.md) - Infrastructure deployment and configuration
- **Helm Charts**: [helm/oauth-obo-client/README.md](helm/oauth-obo-client/README.md) - Kubernetes deployment
- **Application**: [src/OAuthOboClient/README.md](src/OAuthOboClient/README.md) - Application development and usage

## Security Considerations

- **No Secrets in Production**: AKS uses workload identity with federated credentials
- **Client Secrets**: Only used in local development, never in production
- **Token Caching**: In-memory token caches with automatic refresh
- **HTTPS**: All communication uses HTTPS/TLS
- **JWT Validation**: APIM validates all tokens before forwarding requests
- **Group-Based Access**: Authorization based on Azure AD group membership

## Contributing

This is a proof-of-concept repository. For production use, consider:
- Implementing token refresh logic
- Adding comprehensive error handling
- Implementing monitoring and alerting
- Adding automated tests
- Implementing secrets rotation
- Adding rate limiting and throttling

## License

See [LICENSE](LICENSE) file for details.

## Additional Resources

- [OAuth 2.0 On-Behalf-Of Flow](https://learn.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-on-behalf-of-flow)
- [Azure API Management Policies](https://learn.microsoft.com/en-us/azure/api-management/api-management-policies)
- [Azure Workload Identity](https://azure.github.io/azure-workload-identity/)
- [Microsoft.Identity.Web](https://learn.microsoft.com/en-us/azure/active-directory/develop/microsoft-identity-web)
- [ASP.NET Core Authentication](https://learn.microsoft.com/en-us/aspnet/core/security/authentication/)
