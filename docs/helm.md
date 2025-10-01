# Helm Charts for OAuth OBO POC

This directory contains Helm charts for deploying the OAuth 2.0 On-Behalf-Of (OBO) proof of concept components to Kubernetes.

## Available Charts

### oauth-obo-client

The main Helm chart for deploying the OAuth OBO client application with support for both AKS (Azure Workload Identity) and local/minikube (client secret) authentication.

**Key Features:**
- Environment-aware configuration (Production vs Development)
- Azure Workload Identity support for AKS
- Traditional client secret authentication for local development
- Automatic configuration updates via checksums
- Comprehensive documentation and examples

**Quick Start:**

```bash
# For AKS deployment
helm install oauth-obo-client ./oauth-obo-client \
  --namespace poc-client \
  --create-namespace \
  -f values-aks.yaml

# For local/minikube deployment
helm install oauth-obo-client ./oauth-obo-client \
  --namespace poc-client \
  --create-namespace \
  -f values-local.yaml
```

For detailed documentation, see [README.md](README.md)

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- Azure subscription with required resources (see [../iac/README.md](../iac/README.md))

## Chart Structure

```
helm/
├── README.md                           # This file
└──                    # OAuth OBO client chart
    ├── Chart.yaml                      # Chart metadata
    ├── README.md                       # Detailed chart documentation
    ├── values.yaml                     # Default values
    ├── values-aks.yaml                 # AKS-specific values
    ├── values-local.yaml               # Local/minikube values
    ├── .helmignore                     # Files to ignore in packaging
    └── templates/                      # Kubernetes resource templates
        ├── NOTES.txt                   # Post-install notes
        ├── _helpers.tpl                # Template helpers
        ├── serviceaccount.yaml         # ServiceAccount resource
        ├── secret.yaml                 # Secret (dev only)
        ├── configmap.yaml              # ConfigMap
        ├── deployment.yaml             # Deployment
        └── service.yaml                # Service (optional)
```

## Integration with Infrastructure

These Helm charts are designed to work with the Azure infrastructure deployed via Bicep templates in the `iac/` directory:

1. **Deploy Infrastructure First**: Use the Bicep templates to create AKS, APIM, and other Azure resources
2. **Configure Helm Values**: Extract outputs from infrastructure deployment (managed identity client ID, APIM URL, etc.)
3. **Deploy Application**: Use Helm to deploy the OAuth OBO client to the Kubernetes cluster

See [../iac/README.md](../iac/README.md) for infrastructure deployment instructions.

## Deployment Scenarios

### Scenario 1: AKS with Workload Identity (Production)

**Prerequisites:**
- AKS cluster with OIDC issuer and workload identity enabled
- User-assigned managed identity
- Federated credential configured in Azure AD
- ACR for container images

**Steps:**
1. Update `values-aks.yaml` with your configuration
2. Install the chart:
   ```bash
   helm install oauth-obo-client ./oauth-obo-client \
     --namespace poc-client \
     --create-namespace \
     -f values-aks.yaml
   ```

**Authentication:** Azure Workload Identity with federated credentials (no client secrets)

### Scenario 2: Local/Minikube (Development)

**Prerequisites:**
- Local Kubernetes cluster (minikube, kind, etc.)
- Azure AD app registrations with client secret
- Access to APIM endpoint

**Steps:**
1. Update `values-local.yaml` with your configuration
2. Install the chart:
   ```bash
   helm install oauth-obo-client ./oauth-obo-client \
     --namespace poc-client \
     --create-namespace \
     -f values-local.yaml
   ```

**Authentication:** Client ID + Client Secret (stored in Kubernetes Secret)

## Validation

### Lint the Chart

```bash
helm lint oauth-obo-client
```

### Test Template Rendering

```bash
# Test AKS configuration
helm template oauth-obo-client ./oauth-obo-client \
  -f values-aks.yaml \
  --namespace poc-client

# Test local configuration
helm template oauth-obo-client ./oauth-obo-client \
  -f values-local.yaml \
  --namespace poc-client
```

### Package the Chart

```bash
helm package oauth-obo-client
```

## Troubleshooting

### Chart Validation Errors

```bash
# Validate YAML syntax
helm lint oauth-obo-client

# Dry-run install
helm install oauth-obo-client ./oauth-obo-client \
  --namespace poc-client \
  --dry-run --debug \
  -f values-aks.yaml
```

### Deployment Issues

```bash
# Check release status
helm status oauth-obo-client -n poc-client

# View all resources
helm get all oauth-obo-client -n poc-client

# Check pod logs
kubectl logs -n poc-client -l app.kubernetes.io/name=oauth-obo-client
```

## References

- [Helm Documentation](https://helm.sh/docs/)
- [Azure Workload Identity](https://azure.github.io/azure-workload-identity/)
- [OAuth 2.0 On-Behalf-Of Flow](https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-on-behalf-of-flow)
- [Project Requirements](../docs/requirements.md)
- [Infrastructure as Code](../iac/README.md)

## Contributing

For contributions, please refer to the main repository documentation and ensure:
- Charts follow Helm best practices
- Values files are well-documented
- Templates render correctly for all scenarios
- README is kept up-to-date

## License

See the LICENSE file in the repository root.
