# Source Code Directory

This directory contains the source code for the OAuth OBO (On-Behalf-Of) client applications.

## Projects

### OAuthOboClient

A .NET 9.0 ASP.NET Core web application that demonstrates OAuth 2.0 On-Behalf-Of flow with Azure API Management and Kubernetes Workload Identity.

**Key Features:**
- OAuth Authentication (Authorization Code Flow with PKCE)
- AI-style chat interface for testing API calls
- Environment-aware token acquisition (Workload Identity for AKS, Client Secret for local)
- OBO token exchange for downstream API calls
- APIM integration with Bearer token authentication

**Documentation:** See [client/README.md](client/README.md)

## Getting Started

### Prerequisites

- .NET 9.0 SDK
- Docker (for containerization)
- Azure AD app registrations
- Azure API Management instance

### Quick Start

1. Navigate to the project directory:
   ```bash
   cd client
   ```

2. Set up environment variables (see `.env.example`):
   ```bash
   export ENVIRONMENT=Development
   export AZURE_CLIENT_ID=your-client-id
   export AZURE_CLIENT_SECRET=your-client-secret
   export AZURE_TENANT_ID=your-tenant-id
   export API_APP_ID=your-api-app-id
   export OAUTH_SCOPE=access_as_user
   export APIM_BASE_URL=https://your-apim.azure-api.net/httpbin
   ```

3. Run the application:
   ```bash
   dotnet run
   ```

4. Navigate to `https://localhost:5001`

### Building Docker Images

Each project includes a `Dockerfile` and `build.sh` script for containerization:

```bash
cd client
./build.sh
```

For custom registry and tags:
```bash
IMAGE_NAME=oauth-obo-client IMAGE_TAG=v1.0.0 REGISTRY=myregistry.azurecr.io PUSH=true ./build.sh
```

## Deployment

The applications are designed to be deployed to Kubernetes using Helm charts in the `../helm` directory.

See:
- [Infrastructure documentation](../iac/README.md)
- [Helm chart documentation](../helm/README.md)
- [Requirements documentation](../docs/requirements.md)

## Architecture

```
User Browser
    ↓ (OAuth Login)
.NET Client Web App
    ↓ (Azure AD Authentication)
Token Acquisition Service
    ├─ (AKS) Workload Identity
    └─ (Local) Client Secret
    ↓ (Bearer Token)
Azure API Management
    ↓ (Header Injection)
HTTPBin Backend
```

## Development

### Project Structure

```
src/
├── client/           # Main .NET web application
│   ├── Services/             # Token acquisition and API services
│   ├── Pages/                # Razor Pages (UI)
│   ├── Dockerfile            # Container definition
│   ├── build.sh              # Docker build script
│   └── README.md             # Project documentation
└── README.md                 # This file
```

### Adding New Features

1. Create new services in the `Services/` directory
2. Implement business logic with dependency injection
3. Add UI pages in the `Pages/` directory
4. Update configuration as needed
5. Document changes in project README

## Testing

### Local Testing

Run the application locally with development settings:
```bash
cd client
dotnet run --environment Development
```

### Container Testing

Build and run in a container:
```bash
cd client
docker build -t oauth-obo-client:test .
docker run -p 8080:8080 \
  -e ENVIRONMENT=Development \
  -e AZURE_CLIENT_ID=your-client-id \
  -e AZURE_CLIENT_SECRET=your-client-secret \
  -e AZURE_TENANT_ID=your-tenant-id \
  -e API_APP_ID=your-api-app-id \
  -e OAUTH_SCOPE=access_as_user \
  -e APIM_BASE_URL=https://your-apim.azure-api.net/httpbin \
  oauth-obo-client:test
```

## Troubleshooting

### Build Issues

- Ensure .NET 9.0 SDK is installed: `dotnet --version`
- Restore dependencies: `dotnet restore`
- Clean build artifacts: `dotnet clean`

### Authentication Issues

- Verify Azure AD app registration redirect URIs
- Check client ID and secret are correct
- Ensure API permissions are granted in Azure AD

### Container Issues

- Verify Docker is running: `docker info`
- Check image build logs for errors
- Ensure all required environment variables are set

## Contributing

1. Create a feature branch
2. Make changes following existing code patterns
3. Test changes locally and in a container
4. Update documentation
5. Submit a pull request

## Resources

- [ASP.NET Core Documentation](https://learn.microsoft.com/en-us/aspnet/core/)
- [Microsoft.Identity.Web](https://learn.microsoft.com/en-us/azure/active-directory/develop/microsoft-identity-web)
- [Azure Workload Identity](https://azure.github.io/azure-workload-identity/)
- [Docker Documentation](https://docs.docker.com/)
