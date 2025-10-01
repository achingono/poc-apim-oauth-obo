# Ingress Configuration

This document explains the ingress configuration for the OAuth OBO POC application.

## Overview

The application supports ingress configuration for both local development (minikube) and production (AKS) environments. Ingress provides a unified way to access the application and enables proper OAuth redirect URI configuration.

## Local Development (minikube)

### Configuration
- **Ingress Controller**: NGINX (via minikube addon)
- **Host**: `local.oauth-obo.dev`
- **Access**: Requires `/etc/hosts` entry

### Setup Process
1. The deployment script automatically enables the minikube ingress addon
2. Configures NGINX for proper forwarded headers handling
3. Creates an ingress resource with the local hostname
4. Updates Azure AD app registration redirect URIs

### Manual Steps Required
Add this entry to your `/etc/hosts` file:
```
<minikube-ip> local.oauth-obo.dev
```

You can get the minikube IP with:
```bash
minikube ip
```

## Production (AKS)

### Configuration
- **Ingress Controller**: Web Application Routing (Azure-managed NGINX)
- **Host**: Dynamic (assigned by Azure)
- **Access**: External IP provided by Azure Load Balancer

### Setup Process
1. The deployment script enables the Web Application Routing addon
2. Creates an ingress resource with appropriate annotations
3. Waits for external IP assignment
4. Updates Azure AD app registration redirect URIs automatically

### Features
- Automatic TLS termination (when configured)
- Azure-managed certificates (when configured)
- Load balancing across multiple pods
- Integration with Azure DNS (when configured)

## Helm Configuration

### Default Values (values.yaml)
```yaml
ingress:
  enabled: true
  className: ""
  annotations: {}
  hosts:
    - host: ""
      paths:
        - path: /
          pathType: Prefix
  tls: []
```

### Local Values (values-local.yaml)
```yaml
ingress:
  enabled: true
  className: "nginx"
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/use-regex: "true"
  hosts:
    - host: local.oauth-obo.dev
      paths:
        - path: /
          pathType: Prefix
```

### AKS Values (values-aks.yaml)
```yaml
ingress:
  enabled: true
  className: "webapprouting.kubernetes.azure.com"
  annotations:
    kubernetes.io/ingress.class: webapprouting.kubernetes.azure.com
  hosts:
    - host: ""  # Will be set dynamically during deployment
      paths:
        - path: /
          pathType: Prefix
```

## OAuth Redirect URIs

The deployment script automatically configures the following redirect URIs in the Azure AD app registration:

- **Sign-in**: `<ingress-url>/signin-oidc`
- **Sign-out**: `<ingress-url>/signout-callback-oidc`

These URIs are required for the OIDC authentication flow to work properly.

## Troubleshooting

### Common Issues

1. **Ingress not getting external IP (AKS)**
   - Check if Web Application Routing addon is enabled
   - Verify the ingress resource exists: `kubectl get ingress`
   - Check events: `kubectl get events --sort-by='.lastTimestamp'`

2. **Cannot access local application (minikube)**
   - Verify `/etc/hosts` entry is correct
   - Check minikube status: `minikube status`
   - Verify ingress addon is enabled: `minikube addons list`

3. **OAuth redirect errors**
   - Verify redirect URIs are configured in Azure AD app registration
   - Check that the URLs match exactly (including protocol)
   - Ensure app registration allows web redirects

### Debugging Commands

Check ingress status:
```bash
kubectl get ingress -n <namespace>
kubectl describe ingress <deployment-name> -n <namespace>
```

Check ingress controller:
```bash
# For minikube
kubectl get pods -n ingress-nginx

# For AKS
kubectl get pods -n app-routing-system
```

Check service and endpoints:
```bash
kubectl get svc -n <namespace>
kubectl get endpoints -n <namespace>
```

## Security Considerations

1. **TLS Configuration**: Production deployments should use HTTPS with proper certificates
2. **Network Policies**: Consider implementing network policies to restrict traffic
3. **Authentication**: The ingress should only expose authenticated endpoints
4. **CORS**: Ensure proper CORS configuration for API endpoints

## Future Enhancements

1. **Automatic TLS**: Configure automatic certificate provisioning
2. **Custom Domains**: Support for custom domain names
3. **Rate Limiting**: Implement rate limiting at the ingress level
4. **WAF Integration**: Integrate with Azure Application Gateway WAF