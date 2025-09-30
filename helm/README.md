# OAuth OBO Client Helm Chart

This Helm chart deploys the OAuth 2.0 On-Behalf-Of (OBO) client application for Azure APIM with Kubernetes Workload Identity support.

## Overview

The chart supports two deployment scenarios:
1. **AKS (Production)**: Uses Azure Workload Identity with federated credentials (no client secrets)
2. **Local/Minikube (Development)**: Uses traditional client ID + client secret authentication

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- Azure subscription with:
  - Azure API Management instance
  - Azure AD app registrations (Client and API)
  - Azure Kubernetes Service (for production deployment)
  - Managed Identity (for AKS with Workload Identity)

## Installation

### AKS Deployment (Production)

1. Configure your values file or use the provided `values-aks.yaml`:

```bash
# Edit values-aks.yaml with your Azure configuration
vim values-aks.yaml
```

2. Install the chart:

```bash
helm install oauth-obo-client ./oauth-obo-client \
  --namespace poc-client \
  --create-namespace \
  -f values-aks.yaml
```

### Local/Minikube Deployment (Development)

1. Configure your values file or use the provided `values-local.yaml`:

```bash
# Edit values-local.yaml with your Azure configuration
vim values-local.yaml
```

2. Install the chart:

```bash
helm install oauth-obo-client ./oauth-obo-client \
  --namespace poc-client \
  --create-namespace \
  -f values-local.yaml
```

### Installing with Command Line Parameters

You can also override specific values at install time:

```bash
helm install oauth-obo-client ./oauth-obo-client \
  --namespace poc-client \
  --create-namespace \
  --set azure.tenantId=your-tenant-id \
  --set azure.clientId=your-client-id \
  --set azure.apiAppId=your-api-app-id \
  --set apim.baseUrl=https://your-apim.azure-api.net/httpbin
```

## Configuration

### Key Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `environment` | Deployment environment (Production/Development) | `Production` | Yes |
| `azure.tenantId` | Azure AD tenant ID | `""` | Yes |
| `azure.clientId` | Client application ID | `""` | Yes |
| `azure.apiAppId` | API application ID | `""` | Yes |
| `azure.scope` | OAuth scope | `""` | Yes |
| `azure.clientSecret` | Client secret (Development only) | `""` | Yes (Dev) |
| `apim.baseUrl` | APIM base URL | `https://your-apim-name.azure-api.net/httpbin` | Yes |
| `workloadIdentity.enabled` | Enable Azure Workload Identity | `true` | No |
| `workloadIdentity.clientId` | Managed identity client ID | `""` | Yes (AKS) |
| `image.repository` | Container image repository | `your-registry/oauth-obo-client` | Yes |
| `image.tag` | Container image tag | `latest` | Yes |

### Environment-Specific Configuration

#### Production (AKS)
- Set `environment: "Production"`
- Enable `workloadIdentity.enabled: true`
- Provide `workloadIdentity.clientId`
- Do NOT set `azure.clientSecret`
- Use ACR image repository

#### Development (Local/Minikube)
- Set `environment: "Development"`
- Disable `workloadIdentity.enabled: false`
- Provide `azure.clientSecret`
- Use local image repository

## Architecture

### AKS Production Flow
```
User → .NET Client (Pod) → Azure Workload Identity → Azure AD → APIM → HTTPBin
                          ↓
                    Federated Credentials
                    (No client secrets)
```

### Local Development Flow
```
User → .NET Client (Pod) → Client Secret → Azure AD → APIM → HTTPBin
                          ↓
                    Kubernetes Secret
```

## Resources Created

The chart creates the following Kubernetes resources:

1. **ServiceAccount**: For pod identity
   - AKS: Annotated with workload identity client ID
   - Local: Standard service account

2. **Secret** (Development only): Stores client credentials
   - `clientId`: Azure AD client application ID
   - `clientSecret`: Azure AD client secret

3. **ConfigMap**: Non-sensitive configuration
   - Environment settings
   - Azure tenant ID
   - API app ID
   - OAuth scope
   - APIM base URL

4. **Deployment**: Pod deployment
   - Environment-aware configuration
   - Automatic config/secret updates via checksums
   - Workload identity labels (AKS)

5. **Service** (Optional): Service endpoint
   - Disabled by default
   - Enable with `service.enabled: true`

## Verification

### Check Deployment Status

```bash
# Check pod status
kubectl get pods -n poc-client

# View pod logs
kubectl logs -n poc-client -l app.kubernetes.io/name=oauth-obo-client

# Describe pod for events
kubectl describe pod -n poc-client -l app.kubernetes.io/name=oauth-obo-client
```

### Verify Configuration

```bash
# Check ConfigMap
kubectl get configmap -n poc-client oauth-obo-client-config -o yaml

# Check ServiceAccount (AKS)
kubectl get serviceaccount -n poc-client oauth-obo-sa -o yaml

# Check Secret (Local only)
kubectl get secret -n poc-client oauth-obo-client-credentials -o yaml
```

### Test OAuth Flow

```bash
# Execute into the pod
kubectl exec -it -n poc-client deployment/oauth-obo-client -- /bin/sh

# Check environment variables
env | grep AZURE
env | grep APIM
```

## Upgrading

To upgrade the deployment:

```bash
# For AKS
helm upgrade oauth-obo-client ./oauth-obo-client \
  --namespace poc-client \
  -f values-aks.yaml

# For Local
helm upgrade oauth-obo-client ./oauth-obo-client \
  --namespace poc-client \
  -f values-local.yaml
```

## Uninstalling

To uninstall/delete the deployment:

```bash
helm uninstall oauth-obo-client --namespace poc-client
```

This removes all the Kubernetes resources created by the chart.

## Troubleshooting

### Common Issues

#### 1. Workload Identity Not Working (AKS)

**Symptoms**: Pod cannot acquire tokens, authentication errors

**Solutions**:
- Verify AKS cluster has workload identity enabled:
  ```bash
  az aks show -g <resource-group> -n <cluster-name> --query oidcIssuerProfile.enabled
  ```
- Check federated credential configuration in Azure AD
- Verify service account annotation matches managed identity client ID
- Ensure pod label `azure.workload.identity/use: "true"` is set

#### 2. Client Secret Issues (Local)

**Symptoms**: Authentication fails in local development

**Solutions**:
- Verify secret is created: `kubectl get secret -n poc-client oauth-obo-client-credentials`
- Check secret contains correct values (base64 decoded)
- Ensure `environment: "Development"` is set in values

#### 3. Image Pull Failures

**Symptoms**: Pods stuck in `ImagePullBackOff`

**Solutions**:
- For AKS: Verify ACR access is configured
- For Local: Ensure image is built locally or accessible
- Check `imagePullSecrets` if using private registry

#### 4. Configuration Not Applied

**Symptoms**: Old configuration still in use

**Solutions**:
- Delete pods to force recreation:
  ```bash
  kubectl delete pods -n poc-client -l app.kubernetes.io/name=oauth-obo-client
  ```
- Check ConfigMap/Secret checksums in pod annotations

## Security Considerations

### Production (AKS)
- ✅ No client secrets stored in cluster
- ✅ Workload identity uses federated credentials
- ✅ Service account bound to managed identity
- ✅ Automatic token rotation by Azure

### Development (Local)
- ⚠️ Client secrets stored in Kubernetes secrets
- ⚠️ Should only be used for local development
- ⚠️ Never use client secrets in production
- ✅ Secrets base64 encoded (not encrypted)

## Integration with Infrastructure

This Helm chart is designed to work with the infrastructure deployed via the Bicep templates in the `iac/` directory:

1. **Prerequisites from IaC**:
   - AKS cluster with OIDC issuer enabled
   - Managed identity created
   - Federated credential configured
   - APIM instance deployed

2. **Values to Extract from IaC**:
   - `workloadIdentity.clientId`: From managed identity output
   - `apim.baseUrl`: From APIM output
   - `azure.tenantId`: From Azure subscription
   - `azure.clientId`: From app registration
   - `azure.apiAppId`: From app registration

## Advanced Configuration

### Custom Resource Limits

```yaml
resources:
  limits:
    cpu: 1000m
    memory: 1Gi
  requests:
    cpu: 500m
    memory: 512Mi
```

### Node Selector

```yaml
nodeSelector:
  kubernetes.io/os: linux
  workload: oauth-client
```

### Tolerations

```yaml
tolerations:
- key: "oauth-workload"
  operator: "Equal"
  value: "true"
  effect: "NoSchedule"
```

### Affinity Rules

```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchExpressions:
          - key: app.kubernetes.io/name
            operator: In
            values:
            - oauth-obo-client
        topologyKey: kubernetes.io/hostname
```

## References

- [Azure Workload Identity Documentation](https://azure.github.io/azure-workload-identity/)
- [OAuth 2.0 On-Behalf-Of Flow](https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-on-behalf-of-flow)
- [Azure API Management Policies](https://docs.microsoft.com/en-us/azure/api-management/api-management-policies)
- [Helm Documentation](https://helm.sh/docs/)

## Contributing

For issues, questions, or contributions, please refer to the main repository documentation.

## License

See the LICENSE file in the repository root.
