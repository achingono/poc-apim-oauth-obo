# Documentation Index

Welcome to the comprehensive documentation for the OAuth 2.0 On-Behalf-Of (OBO) with Azure API Management and Kubernetes Workload Identity proof of concept.

## Quick Links

### Getting Started
- **[Getting Started Guide](getting-started.md)** - Quick 5-minute setup guide
- **[Prerequisites](deployment/overview.md#prerequisites)** - Required tools and permissions

### Architecture
- **[Architecture Overview](architecture/overview.md)** - System architecture and design
- **[Application Architecture](architecture/application.md)** - .NET client application details
- **[APIM Configuration](architecture/apim.md)** - API Management setup and policies

### Deployment
- **[Deployment Overview](deployment/overview.md)** - Complete deployment guide
- **[Infrastructure Deployment](deployment/infrastructure.md)** - Azure infrastructure setup

### Development
- **[Developer Guide](development/guide.md)** - Development environment and workflow

### Operations
- **[Monitoring Guide](operations/monitoring.md)** - Monitoring, logging, and operations

### Reference
- **[Requirements](requirements.md)** - Detailed POC requirements
- **[Lessons Learned](lessons-learned.md)** - Key insights and solutions
- **[Deployment Script](deployment-script.md)** - Deployment automation details
- **[Helm Charts](helm.md)** - Kubernetes deployment configuration
- **[Ingress Configuration](ingress.md)** - Ingress setup and troubleshooting

## Documentation Structure

```
docs/
├── README.md                          # This file - documentation index
├── getting-started.md                 # Quick start guide
├── requirements.md                    # Detailed requirements (DO NOT MODIFY)
├── lessons-learned.md                 # Key insights and solutions
├── deployment-script.md               # Deployment automation
├── helm.md                           # Helm charts documentation
├── ingress.md                        # Ingress configuration
├── troubleshooting.md                # Troubleshooting guide (existing)
├── architecture/                      # Architecture documentation
│   ├── overview.md                   # System architecture overview
│   ├── application.md                # Application architecture
│   ├── apim.md                       # APIM configuration
│   ├── azure-ad.md                   # Azure AD setup (planned)
│   ├── kubernetes.md                 # Kubernetes architecture (planned)
│   └── security.md                   # Security architecture (planned)
├── deployment/                        # Deployment guides
│   ├── overview.md                   # Deployment overview
│   ├── infrastructure.md             # Infrastructure deployment
│   ├── application.md                # Application deployment (planned)
│   └── prerequisites.md              # Prerequisites (planned)
├── development/                       # Development guides
│   └── guide.md                      # Developer guide
└── operations/                        # Operations guides
    ├── monitoring.md                 # Monitoring and logging
    └── maintenance.md                # Maintenance procedures (planned)
```

## Documentation by Audience

### For First-Time Users

Start here to get up and running quickly:

1. **[Getting Started Guide](getting-started.md)**
   - What you'll build
   - 5-minute quick start
   - Testing the application

2. **[Architecture Overview](architecture/overview.md)**
   - Understand the system components
   - See the authentication flow
   - Learn about design decisions

3. **[Deployment Overview](deployment/overview.md)**
   - Deployment options
   - Automated deployment
   - Post-deployment validation

### For Developers

Learn how to develop and extend the POC:

1. **[Developer Guide](development/guide.md)**
   - Development environment setup
   - Building the application
   - Running locally
   - Debugging

2. **[Application Architecture](architecture/application.md)**
   - Application structure
   - Token acquisition services
   - Configuration management
   - Error handling

3. **[Source Code](../src/README.md)**
   - Client application details
   - Service implementations

### For Infrastructure Engineers

Deploy and manage the Azure infrastructure:

1. **[Infrastructure Deployment](deployment/infrastructure.md)**
   - Infrastructure components
   - Bicep templates
   - Deployment process
   - Configuration parameters

2. **[APIM Configuration](architecture/apim.md)**
   - APIM setup
   - OAuth policy implementation
   - Named values integration
   - Backend configuration

3. **[Infrastructure as Code](../iac/README.md)**
   - Bicep modules
   - Policy definitions
   - Deployment scripts

### For Operations Teams

Monitor and maintain the deployed system:

1. **[Monitoring Guide](operations/monitoring.md)**
   - Monitoring overview
   - Application monitoring
   - Infrastructure monitoring
   - Logging and alerting

2. **[Troubleshooting Guide](troubleshooting.md)** (existing)
   - Common issues and solutions
   - Diagnostic commands

3. **[Lessons Learned](lessons-learned.md)**
   - Known issues and workarounds
   - Best practices

## Key Concepts

### OAuth 2.0 On-Behalf-Of Flow

The OBO flow allows a service to call another service on behalf of an authenticated user:

1. User authenticates with Azure AD
2. Application receives user token
3. Application exchanges user token for service token (OBO)
4. Application calls downstream API with service token

**Resources:**
- [Microsoft OAuth OBO Documentation](https://learn.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-on-behalf-of-flow)
- [Our Implementation](architecture/overview.md#authentication-flow)

### Azure Workload Identity

Workload Identity enables Kubernetes pods to authenticate to Azure without secrets:

1. Kubernetes service account annotated with managed identity
2. Pod labeled for workload identity
3. OIDC token exchange with Azure AD
4. No secrets stored in Kubernetes

**Resources:**
- [Azure Workload Identity Documentation](https://azure.github.io/azure-workload-identity/)
- [Our Implementation](architecture/kubernetes.md) (planned)

### APIM OAuth Policy

APIM validates JWT tokens and enforces authorization:

1. Validate JWT signature and expiration
2. Check audience and scope claims
3. Evaluate user group membership
4. Inject custom headers for backend

**Resources:**
- [APIM Policy Reference](https://docs.microsoft.com/en-us/azure/api-management/api-management-policies)
- [Our OAuth Policy](architecture/apim.md#oauth-policy-implementation)

## Common Tasks

### Deploy the POC

```bash
# Quick deployment (recommended)
./deploy.sh -n oauth-obo -l eastus -s poc

# See: Deployment Overview
```

[Full Guide](deployment/overview.md#quick-start)

### Run Locally

```bash
# Set environment variables
export AZURE_CLIENT_ID="..."
export AZURE_CLIENT_SECRET="..."
# ... other variables

# Run application
cd src/client
dotnet run
```

[Full Guide](development/guide.md#running-locally)

### Troubleshoot Issues

```bash
# Check pod logs
kubectl logs -l app=oauth-obo-client --tail=100

# Check pod status
kubectl get pods

# View events
kubectl get events --sort-by='.lastTimestamp'
```

[Full Guide](troubleshooting.md)

### Monitor Application

```bash
# View Application Insights
# Navigate to Azure Portal → Application Insights

# Query logs
az monitor app-insights query \
  --app <app-name> \
  --analytics-query "requests | where timestamp > ago(1h)"
```

[Full Guide](operations/monitoring.md)

### Update Infrastructure

```bash
# Edit Bicep templates
vi iac/main.bicep

# Deploy changes
az deployment sub create \
  --name oauth-obo \
  --location eastus \
  --template-file iac/main.bicep \
  --parameters iac/main.bicepparam
```

[Full Guide](deployment/infrastructure.md)

## Technology Stack

### Application
- **.NET 9.0** - Application framework
- **ASP.NET Core** - Web framework
- **Razor Pages** - UI framework
- **Microsoft.Identity.Web** - Authentication
- **MSAL** - Token acquisition

### Infrastructure
- **Azure Kubernetes Service** - Container orchestration
- **Azure API Management** - API gateway
- **Azure Key Vault** - Secret management
- **Azure Active Directory** - Identity provider
- **Azure Container Registry** - Image storage
- **Application Insights** - Monitoring

### Tools
- **Docker** - Containerization
- **Helm** - Kubernetes package manager
- **Bicep** - Infrastructure as code
- **Azure CLI** - Azure management

## Contributing to Documentation

### Documentation Guidelines

✅ **Do:**
- Use clear, concise language
- Include code examples
- Provide screenshots where helpful
- Link to related documentation
- Keep information current

❌ **Don't:**
- Modify [requirements.md](requirements.md) - this is the source of truth
- Include sensitive information (secrets, keys, etc.)
- Duplicate information (link instead)
- Use unclear terminology
- Leave broken links

### File a Documentation Issue

Found a problem or have a suggestion?

1. Check [existing issues](https://github.com/achingono/poc-apim-oauth-obo/issues)
2. Create a new issue with:
   - What's wrong or missing
   - Which document needs updating
   - Suggested improvement
   - Your use case

## Additional Resources

### Microsoft Documentation
- [OAuth 2.0 On-Behalf-Of Flow](https://learn.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-on-behalf-of-flow)
- [Azure API Management](https://learn.microsoft.com/en-us/azure/api-management/)
- [Azure Workload Identity](https://azure.github.io/azure-workload-identity/)
- [ASP.NET Core Authentication](https://learn.microsoft.com/en-us/aspnet/core/security/authentication/)

### Repository Resources
- [Main README](../README.md) - Project overview
- [Source Code](../src/README.md) - Application source
- [IaC Documentation](../iac/README.md) - Infrastructure code
- [Helm Charts](../helm/README.md) - Kubernetes deployment

### Community Resources
- [GitHub Issues](https://github.com/achingono/poc-apim-oauth-obo/issues)
- [GitHub Discussions](https://github.com/achingono/poc-apim-oauth-obo/discussions)

## Getting Help

### Check Existing Documentation

1. Use search (Ctrl+F) to find topics
2. Check the [Troubleshooting Guide](troubleshooting.md)
3. Review [Lessons Learned](lessons-learned.md)

### Common Questions

**Q: How do I deploy to Azure?**  
A: See [Deployment Overview](deployment/overview.md#quick-start)

**Q: How do I run locally?**  
A: See [Developer Guide](development/guide.md#running-locally)

**Q: Why am I getting 401 errors?**  
A: See [Troubleshooting Guide](troubleshooting.md)

**Q: How do I monitor the application?**  
A: See [Monitoring Guide](operations/monitoring.md)

### Still Need Help?

1. Check GitHub Issues
2. Ask in GitHub Discussions
3. Review Azure documentation
4. Contact the maintainers

---

**Last Updated**: Generated during comprehensive documentation initiative
**Maintained By**: Project contributors
