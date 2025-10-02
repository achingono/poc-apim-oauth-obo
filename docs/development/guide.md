# Developer Guide

This guide provides comprehensive information for developers working on the OAuth OBO POC.

## Table of Contents

- [Development Environment Setup](#development-environment-setup)
- [Project Structure](#project-structure)
- [Building the Application](#building-the-application)
- [Running Locally](#running-locally)
- [Testing](#testing)
- [Debugging](#debugging)
- [Contributing Changes](#contributing-changes)
- [Best Practices](#best-practices)

## Development Environment Setup

### Prerequisites

**Required Tools:**
- .NET 9.0 SDK
- Visual Studio Code or Visual Studio 2022
- Docker Desktop
- Azure CLI
- Git

**Recommended Extensions (VS Code):**
- C# Dev Kit
- Azure Account
- Docker
- Kubernetes
- Bicep

### Initial Setup

```bash
# Clone repository
git clone https://github.com/achingono/poc-apim-oauth-obo.git
cd poc-apim-oauth-obo

# Restore dependencies
cd src/client
dotnet restore

# Build solution
dotnet build

# Run tests (if any)
dotnet test
```

### Configure Development Environment

Create `.env` file in project root:

```bash
# Azure Configuration
export AZURE_TENANT_ID="your-tenant-id"
export AZURE_CLIENT_ID="your-client-app-id"
export AZURE_CLIENT_SECRET="your-client-secret"
export API_APP_ID="your-api-app-id"
export OAUTH_SCOPE="access_as_user"
export APIM_BASE_URL="https://your-apim.azure-api.net/httpbin"
export ENVIRONMENT="Development"
```

Load environment:
```bash
source .env
```

## Project Structure

### Repository Layout

```
poc-apim-oauth-obo/
├── .github/                    # GitHub workflows and configuration
│   └── copilot-instructions.md # AI coding assistant instructions
├── docs/                       # Documentation
│   ├── architecture/          # Architecture documentation
│   ├── deployment/            # Deployment guides
│   ├── development/           # Development guides
│   └── operations/            # Operations guides
├── iac/                       # Infrastructure as Code
│   ├── main.bicep            # Main deployment template
│   ├── main.bicepparam       # Parameters
│   ├── modules/              # Reusable Bicep modules
│   └── policies/             # APIM policy definitions
├── helm/                      # Kubernetes Helm charts
│   ├── templates/            # K8s resource templates
│   └── values*.yaml          # Configuration values
├── src/                       # Source code
│   └── client/               # .NET client application
│       ├── Pages/            # Razor Pages
│       ├── Services/         # Business logic
│       └── wwwroot/          # Static files
├── scripts/                   # Utility scripts
│   ├── cleanup.sh           # Cleanup script
│   └── functions.sh         # Shared functions
├── deploy.sh                 # Main deployment script
└── README.md                 # Project overview
```

### Source Code Organization

```
src/client/
├── Program.cs                 # Application entry point
├── appsettings.json          # Base configuration
├── appsettings.Development.json  # Development overrides
├── Pages/
│   ├── Index.cshtml          # Chat UI
│   ├── Index.cshtml.cs       # Chat logic
│   ├── Error.cshtml          # Error page
│   ├── Privacy.cshtml        # Privacy page
│   └── Shared/
│       ├── _Layout.cshtml    # Page layout
│       └── _LoginPartial.cshtml  # Login component
├── Services/
│   ├── ITokenAcquisitionService.cs       # Interface
│   ├── WorkloadIdentityTokenService.cs   # Production impl
│   ├── ClientSecretTokenService.cs       # Development impl
│   └── ApiClient.cs                      # APIM client
└── wwwroot/
    ├── css/                  # Stylesheets
    ├── js/                   # JavaScript
    └── lib/                  # Third-party libraries
```

## Building the Application

### Build from Source

```bash
cd src/client

# Clean previous builds
dotnet clean

# Restore NuGet packages
dotnet restore

# Build application
dotnet build

# Build for release
dotnet build --configuration Release
```

### Build Docker Image

```bash
cd src/client

# Build image
docker build -t poc/client:latest .

# Build with custom tag
docker build -t poc/client:v1.0.0 .

# Build for specific platform
docker build --platform linux/amd64 -t poc/client:latest .
```

### Build and Push to ACR

```bash
# Login to ACR
az acr login --name <registry-name>

# Build and push
cd src/client
./build.sh

# Or manually:
docker build -t <registry>.azurecr.io/poc/client:latest .
docker push <registry>.azurecr.io/poc/client:latest
```

## Running Locally

### Option 1: Run with .NET CLI

```bash
cd src/client

# Set environment variables
export ENVIRONMENT="Development"
export AZURE_CLIENT_ID="your-client-id"
export AZURE_CLIENT_SECRET="your-client-secret"
export AZURE_TENANT_ID="your-tenant-id"
export API_APP_ID="your-api-app-id"
export OAUTH_SCOPE="access_as_user"
export APIM_BASE_URL="https://your-apim.azure-api.net/httpbin"

# Run application
dotnet run

# Or run with watch (auto-reload)
dotnet watch run
```

Application runs at: `https://localhost:5001`

### Option 2: Run with Docker

```bash
# Build image
cd src/client
docker build -t poc/client:latest .

# Run container
docker run -p 8080:8080 \
  -e ENVIRONMENT="Development" \
  -e AZURE_CLIENT_ID="your-client-id" \
  -e AZURE_CLIENT_SECRET="your-client-secret" \
  -e AZURE_TENANT_ID="your-tenant-id" \
  -e API_APP_ID="your-api-app-id" \
  -e OAUTH_SCOPE="access_as_user" \
  -e APIM_BASE_URL="https://your-apim.azure-api.net/httpbin" \
  poc/client:latest
```

Application runs at: `http://localhost:8080`

### Option 3: Run in Minikube

```bash
# Start minikube
minikube start

# Build and load image
cd src/client
docker build -t poc/client:latest .
minikube image load poc/client:latest

# Deploy with Helm
cd ../../helm
helm install oauth-obo-client . \
  -f values-local.yaml \
  --set azure.tenantId=<tenant-id> \
  --set azure.clientId=<client-id> \
  --set azure.clientSecret=<client-secret> \
  --set azure.apiAppId=<api-app-id> \
  --set apim.baseUrl=<apim-url>

# Add hosts entry
echo "$(minikube ip) local.oauth-obo.dev" | sudo tee -a /etc/hosts

# Access application
open http://local.oauth-obo.dev
```

## Testing

### Manual Testing

#### Test Authentication Flow

1. Start application
2. Navigate to `https://localhost:5001`
3. Click "Sign In"
4. Enter Azure AD credentials
5. Verify redirect back to application
6. Check user is authenticated

#### Test Token Acquisition

1. Ensure authenticated
2. Send a message in chat
3. Check application logs for token acquisition
4. Verify token is cached (subsequent calls faster)

**Expected Logs:**
```
info: client.Services.ClientSecretTokenService[0]
      ClientSecretTokenService initialized for local development
info: client.Services.ApiClient[0]
      Acquiring access token for scope: api://xxx/access_as_user
info: client.Services.ApiClient[0]
      Access token acquired, calling APIM at https://...
```

#### Test API Calls

1. Send message in chat
2. Verify response shows:
   - Authorization header with Bearer token
   - X-API-Key header (STANDARD or ADMIN)
   - X-User-Role header (user or admin)
   - Your custom message header

#### Test Error Handling

**Test Invalid Configuration:**
```bash
# Unset required variable
unset AZURE_CLIENT_ID

# Run application - should fail with helpful error
dotnet run
```

**Test Invalid Token:**
```bash
# Call APIM directly with invalid token
curl -H "Authorization: Bearer invalid" \
  https://your-apim.azure-api.net/httpbin/test

# Expected: 401 Unauthorized
```

### Integration Testing

#### Test Complete Flow

```bash
# Use test script
cd scripts
./test-ingress.sh oauth-obo default false

# Script tests:
# 1. Pod is running
# 2. Service is available
# 3. Ingress is configured
# 4. Application responds
```

### Load Testing

```bash
# Simple load test with Apache Bench
ab -n 100 -c 10 http://your-app-url/

# Or use k6
k6 run - <<EOF
import http from 'k6/http';
export default function() {
  http.get('http://your-app-url/');
}
EOF
```

## Debugging

### Debug with Visual Studio Code

1. Open `src/client` folder in VS Code
2. Press F5 or use Debug menu
3. Set breakpoints in code
4. Use Debug Console to inspect variables

**.vscode/launch.json:**
```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": ".NET Core Launch (web)",
      "type": "coreclr",
      "request": "launch",
      "preLaunchTask": "build",
      "program": "${workspaceFolder}/bin/Debug/net9.0/client.dll",
      "args": [],
      "cwd": "${workspaceFolder}",
      "env": {
        "ASPNETCORE_ENVIRONMENT": "Development",
        "AZURE_CLIENT_ID": "your-client-id",
        "AZURE_CLIENT_SECRET": "your-client-secret",
        "AZURE_TENANT_ID": "your-tenant-id",
        "API_APP_ID": "your-api-app-id",
        "OAUTH_SCOPE": "access_as_user",
        "APIM_BASE_URL": "https://your-apim.azure-api.net/httpbin"
      }
    }
  ]
}
```

### Debug in Kubernetes

```bash
# View pod logs
kubectl logs -l app=oauth-obo-client --tail=100 -f

# Exec into pod
kubectl exec -it <pod-name> -- /bin/bash

# View environment variables
kubectl exec <pod-name> -- env

# Debug networking
kubectl exec <pod-name> -- curl http://localhost:8080

# Port forward to local machine
kubectl port-forward <pod-name> 8080:8080
```

### Debug APIM Policies

**Test Policy in Azure Portal:**
1. Open APIM service in Azure Portal
2. Go to APIs → HTTPBin API → Test
3. Add Authorization header
4. Send test request
5. View trace output

**Enable Policy Tracing:**
```bash
# Get test key
az apim api show --resource-group <rg> --service-name <apim> --api-id httpbin

# Call with tracing
curl -H "Authorization: Bearer <token>" \
     -H "Ocp-Apim-Trace: true" \
     -H "Ocp-Apim-Subscription-Key: <key>" \
     https://your-apim.azure-api.net/httpbin/test
```

### Debug Workload Identity

```bash
# Check service account
kubectl get serviceaccount oauth-obo-client-sa -o yaml

# Check annotations
kubectl get serviceaccount oauth-obo-client-sa -o jsonpath='{.metadata.annotations}'

# Check pod labels
kubectl get pods -l app=oauth-obo-client -o jsonpath='{.items[0].metadata.labels}'

# Check projected token
kubectl exec <pod-name> -- cat /var/run/secrets/azure/tokens/azure-identity-token

# View token acquisition logs
kubectl logs -l app=oauth-obo-client | grep -i workload
```

## Contributing Changes

### Code Style

**C# Conventions:**
- Use PascalCase for public members
- Use camelCase for private fields
- Use meaningful variable names
- Add XML documentation for public APIs
- Follow .NET coding conventions

**Example:**
```csharp
/// <summary>
/// Acquires an access token for the specified scopes.
/// </summary>
/// <param name="scopes">The scopes to request.</param>
/// <returns>An access token string.</returns>
public async Task<string> AcquireTokenForUserAsync(string[] scopes)
{
    // Implementation
}
```

### Making Changes

1. **Create Feature Branch:**
```bash
git checkout -b feature/my-new-feature
```

2. **Make Changes:**
- Edit code
- Add tests if applicable
- Update documentation

3. **Build and Test:**
```bash
dotnet build
dotnet test
```

4. **Commit Changes:**
```bash
git add .
git commit -m "Add my new feature"
```

5. **Push and Create PR:**
```bash
git push origin feature/my-new-feature
# Create pull request on GitHub
```

### Testing Changes

**Test Locally:**
```bash
# Run application
dotnet run

# Test in Docker
docker build -t poc/client:test .
docker run -p 8080:8080 poc/client:test

# Test in Minikube
minikube start
docker build -t poc/client:test .
minikube image load poc/client:test
helm upgrade oauth-obo-client ./helm --set image.tag=test
```

**Test Infrastructure Changes:**
```bash
# Validate Bicep
cd iac
az bicep build --file main.bicep

# What-if deployment
az deployment sub what-if \
  --location eastus \
  --template-file main.bicep \
  --parameters main.bicepparam
```

## Best Practices

### Security

✅ **Do:**
- Store secrets in Key Vault
- Use environment variables for configuration
- Use workload identity in production
- Validate all inputs
- Log security events

❌ **Don't:**
- Hardcode secrets in code
- Commit secrets to git
- Log access tokens
- Trust user input without validation
- Expose sensitive information in errors

### Performance

✅ **Do:**
- Use token caching
- Reuse HTTP clients
- Use async/await properly
- Profile performance bottlenecks
- Monitor resource usage

❌ **Don't:**
- Create new HTTP clients per request
- Block on async calls
- Fetch tokens for every request
- Ignore memory leaks
- Over-log in production

### Error Handling

✅ **Do:**
- Catch specific exceptions
- Log detailed error information
- Return user-friendly messages
- Implement retry logic where appropriate
- Handle token expiration gracefully

❌ **Don't:**
- Catch and ignore exceptions
- Expose stack traces to users
- Log sensitive information
- Return generic error messages
- Fail silently

### Logging

✅ **Do:**
```csharp
_logger.LogInformation("Acquiring token for scope: {Scope}", scope);
_logger.LogWarning("Token cache miss for user {UserId}", userId);
_logger.LogError(ex, "Failed to acquire token");
```

❌ **Don't:**
```csharp
Console.WriteLine("Token: " + token);  // Don't log tokens
_logger.LogInformation(token);         // Don't log tokens
Debug.Print("Secret: " + secret);      // Don't log secrets
```

## Related Documentation

- [Architecture Overview](../architecture/overview.md)
- [Application Architecture](../architecture/application.md)
- [Source Code Documentation](../../src/README.md)
- [Deployment Guide](../deployment/overview.md)
- [Troubleshooting](../troubleshooting.md)
