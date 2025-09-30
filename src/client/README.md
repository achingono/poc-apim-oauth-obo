# OAuth OBO Client

A .NET 9.0 web application that demonstrates OAuth 2.0 On-Behalf-Of (OBO) flow with Azure API Management (APIM) and Azure Workload Identity for Kubernetes.

## Features

- **OAuth Authentication**: Authorization Code Flow with PKCE for user authentication
- **AI Chat Interface**: Interactive chat-like UI for testing API calls
- **Environment-Aware Token Acquisition**: 
  - Production (AKS): Uses Azure Workload Identity with federated credentials
  - Development (Local): Uses Client ID + Client Secret
- **OBO Token Exchange**: Acquires downstream API tokens using the appropriate credential type
- **APIM Integration**: Calls APIM endpoints with Bearer tokens
- **Response Analysis**: Displays and parses httpbin.org responses to validate header injection

## Architecture

### Authentication Flow

```
User → .NET Client → Azure AD (OAuth) → APIM → HTTPBin API
                    ↓
         Token Acquisition Service
         (Workload Identity or Client Secret)
```

### Components

- **ITokenAcquisitionService**: Interface for token acquisition
  - **WorkloadIdentityTokenService**: AKS production implementation
  - **ClientSecretTokenService**: Local development implementation
- **ApiClient**: Service for making authenticated calls to APIM
- **Chat Interface**: Razor Pages-based UI for user interaction

## Configuration

The application requires the following environment variables:

| Variable | Description | Required |
|----------|-------------|----------|
| `ENVIRONMENT` | "Production" (AKS) or "Development" (local) | Yes |
| `AZURE_CLIENT_ID` | Azure AD client application ID | Yes |
| `AZURE_TENANT_ID` | Azure AD tenant ID | Yes |
| `API_APP_ID` | API application ID for audience validation | Yes |
| `OAUTH_SCOPE` | OAuth scope (default: "access_as_user") | Yes |
| `APIM_BASE_URL` | Base URL for APIM endpoint | Yes |
| `AZURE_CLIENT_SECRET` | Client secret (Development only) | No* |
| `AZURE_FEDERATED_TOKEN_FILE` | Workload identity token file path (AKS only) | No* |

*Required depending on environment

## Running Locally

### Prerequisites

- .NET 9.0 SDK
- Azure AD app registration with configured redirect URIs
- APIM instance with OAuth policies configured
- Client ID and Client Secret

### Steps

1. Set environment variables:
```bash
export ENVIRONMENT=Development
export AZURE_CLIENT_ID=<your-client-id>
export AZURE_CLIENT_SECRET=<your-client-secret>
export AZURE_TENANT_ID=<your-tenant-id>
export API_APP_ID=<your-api-app-id>
export OAUTH_SCOPE=access_as_user
export APIM_BASE_URL=https://<your-apim>.azure-api.net/httpbin
```

2. Run the application:
```bash
cd src/client
dotnet run
```

3. Navigate to `https://localhost:5001` (or the configured port)

## Building Docker Image

```bash
cd src/client
docker build -t oauth-obo-client:latest .
```

## Deploying to Kubernetes

The application is designed to be deployed using the Helm chart in the `helm/oauth-obo-client` directory.

### AKS with Workload Identity

```bash
helm install oauth-obo-client ./helm/oauth-obo-client \
  -f ./helm/oauth-obo-client/values-aks.yaml \
  --set azure.tenantId=<tenant-id> \
  --set azure.clientId=<client-id> \
  --set azure.apiAppId=<api-app-id> \
  --set apim.baseUrl=<apim-base-url> \
  --set workloadIdentity.clientId=<managed-identity-client-id>
```

### Local Minikube

```bash
helm install oauth-obo-client ./helm/oauth-obo-client \
  -f ./helm/oauth-obo-client/values-local.yaml \
  --set azure.tenantId=<tenant-id> \
  --set azure.clientId=<client-id> \
  --set azure.clientSecret=<client-secret> \
  --set azure.apiAppId=<api-app-id> \
  --set apim.baseUrl=<apim-base-url>
```

## Usage

1. **Login**: Click "Login" in the navigation bar to authenticate with Azure AD
2. **Send Message**: Type a message in the text box and click "Send"
3. **View Response**: The API response will appear in the chat history above
4. **Clear Chat**: Click "Clear Chat" to reset the conversation
5. **Logout**: Click "Logout" to sign out and log in as a different user

## Troubleshooting

### Token Acquisition Fails

- **Local Development**: Ensure `AZURE_CLIENT_SECRET` is set correctly
- **AKS Production**: Verify workload identity configuration and federated credentials

### APIM Returns 401

- Check JWT validation in APIM policies
- Verify audience and scope claims in the token
- Check APIM named values for correct tenant ID and API app ID

### Workload Identity Not Working

- Ensure AKS cluster has OIDC issuer and workload identity enabled
- Verify federated credential configuration in Azure AD
- Check service account annotations in Kubernetes deployment

## Development

### Project Structure

```
client/
├── Pages/
│   ├── Index.cshtml          # Main chat interface
│   ├── Index.cshtml.cs       # Chat logic and API calls
│   └── Shared/
│       ├── _Layout.cshtml    # Application layout
│       └── _LoginPartial.cshtml  # Login/logout UI
├── Services/
│   ├── ITokenAcquisitionService.cs  # Token acquisition interface
│   ├── WorkloadIdentityTokenService.cs  # AKS implementation
│   ├── ClientSecretTokenService.cs      # Local implementation
│   └── ApiClient.cs          # APIM integration
├── Program.cs                # Application startup and configuration
├── Dockerfile                # Container image definition
└── appsettings.json          # Application settings
```

### Adding New Features

1. Create new services in the `Services/` directory
2. Register services in `Program.cs`
3. Add new pages in the `Pages/` directory for new UI features
4. Update configuration in `appsettings.json` as needed

## References

- [Microsoft.Identity.Web Documentation](https://learn.microsoft.com/en-us/azure/active-directory/develop/microsoft-identity-web)
- [Azure Workload Identity](https://azure.github.io/azure-workload-identity/)
- [OAuth 2.0 On-Behalf-Of Flow](https://learn.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-on-behalf-of-flow)
- [Azure API Management Policies](https://learn.microsoft.com/en-us/azure/api-management/api-management-policies)
