# Troubleshooting Guide

This guide provides solutions to common issues encountered with the OAuth OBO POC.

## Table of Contents

- [Deployment Issues](#deployment-issues)
- [Authentication Issues](#authentication-issues)
- [API Call Issues](#api-call-issues)
- [Infrastructure Issues](#infrastructure-issues)
- [Application Issues](#application-issues)
- [Diagnostic Commands](#diagnostic-commands)

## Deployment Issues

### Issue: Deployment Script Fails

**Symptoms**: `deploy.sh` exits with error message

**Common Causes:**
1. Missing Azure CLI authentication
2. Insufficient Azure AD permissions
3. Invalid parameters
4. Resource provider not registered

**Solutions:**

**Check Azure CLI Authentication:**
```bash
# Verify logged in
az account show

# Login if needed
az login

# Set correct subscription
az account set --subscription "Your Subscription"
```

**Check Azure AD Permissions:**
```bash
# Check your permissions
az ad signed-in-user show --query userPrincipalName

# Required permissions:
# - Application.ReadWrite.All (or Application.ReadWrite.OwnedBy)
# - Group.ReadWrite.All
```

**Validate Parameters:**
```bash
# Correct syntax
./deploy.sh -n oauth-obo -l eastus -s poc

# Common errors:
# - Name too short (min 3 chars) or too long (max 21 chars)
# - Suffix contains special characters (alphanumeric only)
# - Invalid region name
```

**Register Resource Providers:**
```bash
# Register required providers
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.ApiManagement
az provider register --namespace Microsoft.KeyVault
az provider register --namespace Microsoft.ContainerRegistry

# Check registration status
az provider show --namespace Microsoft.ContainerService --query registrationState
```

### Issue: Bicep Deployment Fails

**Symptoms**: Infrastructure deployment fails with Bicep errors

**Solutions:**

**Validate Bicep Template:**
```bash
cd iac

# Build and validate
az bicep build --file main.bicep

# Check for syntax errors in output
```

**Check Resource Limits:**
```bash
# Check quota
az vm list-usage --location eastus --output table

# Request quota increase if needed
az support quota update \
  --quota-limit 10 \
  --resource-name "StandardDSv2Family" \
  --location eastus
```

**Review What-If Output:**
```bash
# Preview changes before deployment
az deployment sub what-if \
  --location eastus \
  --template-file iac/main.bicep \
  --parameters iac/main.bicepparam
```

### Issue: Helm Installation Fails

**Symptoms**: `helm install` command fails

**Solutions:**

**Check Kubernetes Connection:**
```bash
# Verify kubectl is connected
kubectl cluster-info

# Get AKS credentials
az aks get-credentials \
  --resource-group <rg-name> \
  --name <aks-name> \
  --overwrite-existing
```

**Validate Helm Chart:**
```bash
cd helm

# Lint chart
helm lint .

# Dry run installation
helm install oauth-obo-client . \
  --dry-run \
  --debug \
  -f values-aks.yaml
```

**Check Image Availability:**
```bash
# Verify image exists
az acr repository show \
  --name <acr-name> \
  --repository poc/client

# Check AKS can pull from ACR
az aks check-acr \
  --resource-group <rg-name> \
  --name <aks-name> \
  --acr <acr-name>
```

## Authentication Issues

### Issue: Login Redirect Loop

**Symptoms**: Sign-in keeps redirecting without completing

**Solutions:**

**Check Redirect URIs:**
```bash
# List app registration redirect URIs
az ad app show --id <client-app-id> --query "web.redirectUris"

# Must include:
# - http://<app-url>/signin-oidc
# - http://<app-url>/signout-callback-oidc
```

**Update Redirect URIs:**
```bash
# Get ingress URL
INGRESS_URL=$(kubectl get ingress -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')

# Update app registration
az ad app update --id <client-app-id> \
  --web-redirect-uris "http://$INGRESS_URL/signin-oidc" "http://$INGRESS_URL/signout-callback-oidc"
```

**Clear Browser Cache:**
```bash
# Or try incognito/private browsing mode
# Clear cookies for login.microsoftonline.com
```

### Issue: User Cannot Sign In

**Symptoms**: Error during Azure AD login

**Solutions:**

**Check User Exists:**
```bash
# Verify user in tenant
az ad user show --id user@domain.com
```

**Check App Registration:**
```bash
# Verify client ID matches
kubectl get configmap oauth-obo-client-config -o yaml | grep AZURE_CLIENT_ID

# Should match app registration
az ad app show --id <client-app-id> --query appId
```

**Check Tenant ID:**
```bash
# Verify tenant ID
kubectl get configmap oauth-obo-client-config -o yaml | grep AZURE_TENANT_ID

# Should match
az account show --query tenantId
```

### Issue: Consent Required

**Symptoms**: User prompted for admin consent on every login

**Solutions:**

**Grant Admin Consent:**
```bash
# Grant consent for all users
az ad app permission admin-consent --id <client-app-id>

# Or use Azure Portal:
# Azure AD → App Registrations → API Permissions → Grant admin consent
```

**Check Required Permissions:**
```bash
# List required permissions
az ad app show --id <client-app-id> --query "requiredResourceAccess"
```

## API Call Issues

### Issue: 401 Unauthorized from APIM

**Symptoms**: API calls return 401 Unauthorized

**Solutions:**

**Check Token Audience:**
```bash
# Get token
TOKEN=$(az account get-access-token --resource api://<api-app-id> --query accessToken -o tsv)

# Decode token (use jwt.io or jwt.ms)
# Verify 'aud' claim matches api://<api-app-id>
```

**Verify APIM Policy:**
```bash
# Check named values
az apim nv list \
  --service-name <apim-name> \
  --resource-group <rg-name> \
  --query "[].{name:name,value:properties.value}"

# Verify api_app_id matches audience
```

**Check Token Scope:**
```bash
# Token must include scope claim
# Verify 'scp' or 'roles' claim contains 'access_as_user'
```

**Test Token Directly:**
```bash
# Get token for correct audience
TOKEN=$(az account get-access-token --resource api://<api-app-id> --query accessToken -o tsv)

# Test APIM endpoint
curl -H "Authorization: Bearer $TOKEN" \
  https://<apim-name>.azure-api.net/httpbin/test
```

### Issue: Token Acquisition Fails

**Symptoms**: Application logs show token acquisition errors

**Solutions:**

**Check Workload Identity (AKS):**
```bash
# Verify service account annotation
kubectl get serviceaccount oauth-obo-client-sa -o yaml | grep clientId

# Should match managed identity client ID
az deployment sub show \
  --name <deployment-name> \
  --query properties.outputs.workloadIdentityClientId.value

# Check pod label
kubectl get pods -l app=oauth-obo-client -o yaml | grep azure.workload.identity/use

# Should be "true"
```

**Check Client Secret (Local):**
```bash
# Verify secret exists
kubectl get secret oauth-obo-client-credentials -o yaml

# Decode and verify
kubectl get secret oauth-obo-client-credentials -o jsonpath='{.data.AZURE_CLIENT_SECRET}' | base64 -d
```

**Check Federated Credential:**
```bash
# List federated credentials
az identity federated-credential list \
  --identity-name <managed-identity-name> \
  --resource-group <rg-name>

# Verify subject matches: system:serviceaccount:<namespace>:<service-account-name>
```

### Issue: Invalid Client Error

**Symptoms**: MSAL error "invalid_client"

**Solutions:**

**Verify Client Secret:**
```bash
# Check secret hasn't expired
az ad app credential list --id <client-app-id>

# Create new secret if expired
az ad app credential reset --id <client-app-id> --years 1
```

**Check Client ID:**
```bash
# Verify configuration
kubectl get configmap oauth-obo-client-config -o yaml | grep AZURE_CLIENT_ID
```

## Infrastructure Issues

### Issue: APIM Named Values Not Syncing

**Symptoms**: APIM policies fail with "Cannot find property"

**Solutions:**

**Check Key Vault RBAC:**
```bash
# List role assignments for APIM identity
az role assignment list \
  --assignee <apim-identity-object-id> \
  --scope /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<kv-name>

# Assign role if missing
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee <apim-identity-object-id> \
  --scope /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<kv-name>
```

**Verify Secret Exists:**
```bash
# List secrets
az keyvault secret list --vault-name <kv-name>

# Show specific secret
az keyvault secret show --vault-name <kv-name> --name api-app-id
```

**Check Named Value Status:**
```bash
# Show named value
az apim nv show \
  --service-name <apim-name> \
  --resource-group <rg-name> \
  --named-value-id api_app_id

# Status should be "Succeeded"
```

**Force Refresh:**
```bash
# Azure Portal → APIM → Named values → Select value → Refresh
# Or redeploy infrastructure
```

### Issue: AKS Pods Not Starting

**Symptoms**: Pods stuck in Pending or CrashLoopBackOff

**Solutions:**

**Check Pod Status:**
```bash
# Get pod status
kubectl get pods

# Describe pod for details
kubectl describe pod <pod-name>
```

**Image Pull Errors:**
```bash
# Check events
kubectl get events --sort-by='.lastTimestamp' | grep Failed

# Verify ACR access
az aks check-acr \
  --resource-group <rg-name> \
  --name <aks-name> \
  --acr <acr-name>

# Attach ACR if needed
az aks update \
  --resource-group <rg-name> \
  --name <aks-name> \
  --attach-acr <acr-name>
```

**Configuration Errors:**
```bash
# Check ConfigMap
kubectl get configmap oauth-obo-client-config -o yaml

# Check Secret (if using)
kubectl get secret oauth-obo-client-credentials -o yaml

# View pod logs
kubectl logs <pod-name>
```

**Resource Constraints:**
```bash
# Check node resources
kubectl top nodes

# Check pod resources
kubectl describe node <node-name> | grep -A 5 "Allocated resources"

# Scale cluster if needed
az aks scale \
  --resource-group <rg-name> \
  --name <aks-name> \
  --node-count 3
```

### Issue: Ingress Not Getting External IP

**Symptoms**: Ingress remains in Pending state

**Solutions:**

**Check Ingress Addon:**
```bash
# Check if Web Application Routing is enabled
az aks show \
  --resource-group <rg-name> \
  --name <aks-name> \
  --query "ingressProfile.webAppRouting.enabled"

# Enable if needed
az aks approuting enable \
  --resource-group <rg-name> \
  --name <aks-name>
```

**Check Ingress Resource:**
```bash
# View ingress
kubectl get ingress

# Describe ingress
kubectl describe ingress <ingress-name>

# Check ingress controller pods
kubectl get pods -n app-routing-system
```

**For Minikube:**
```bash
# Enable ingress addon
minikube addons enable ingress

# Check ingress controller
kubectl get pods -n ingress-nginx

# Get minikube IP
minikube ip
```

## Application Issues

### Issue: High Memory Usage

**Symptoms**: Pods consuming excessive memory

**Solutions:**

**Check Memory Usage:**
```bash
# Current usage
kubectl top pods

# View limits
kubectl describe pod <pod-name> | grep -A 5 Limits
```

**Adjust Resource Limits:**
```bash
# Update Helm values
helm upgrade oauth-obo-client ./helm \
  --set resources.limits.memory=512Mi \
  --set resources.requests.memory=256Mi
```

**Check for Memory Leaks:**
```bash
# Monitor over time
watch kubectl top pods

# Check application logs
kubectl logs <pod-name> | grep -i "memory\|out of memory"
```

### Issue: Slow Response Times

**Symptoms**: Application responding slowly

**Solutions:**

**Check Pod Performance:**
```bash
# CPU and memory
kubectl top pods

# Network latency
kubectl exec <pod-name> -- ping -c 3 httpbin.org
```

**Check Token Caching:**
```bash
# Review logs for repeated token acquisitions
kubectl logs <pod-name> | grep "Acquiring token"

# Should be cached after first acquisition
```

**Check APIM Performance:**
```bash
# Get APIM metrics
az monitor metrics list \
  --resource <apim-resource-id> \
  --metric "TotalRequests,Duration" \
  --start-time $(date -u -d '1 hour ago' '+%Y-%m-%dT%H:%M:%SZ') \
  --interval PT1M
```

## Diagnostic Commands

### Application Diagnostics

```bash
# View application logs
kubectl logs -l app=oauth-obo-client --tail=100

# Follow logs in real-time
kubectl logs -l app=oauth-obo-client -f

# View logs from all pods
kubectl logs -l app=oauth-obo-client --all-containers=true

# Get pod status
kubectl get pods -l app=oauth-obo-client

# Describe pod
kubectl describe pod <pod-name>

# Exec into pod
kubectl exec -it <pod-name> -- /bin/bash

# View environment variables
kubectl exec <pod-name> -- env

# Test internal connectivity
kubectl exec <pod-name> -- curl http://localhost:8080
```

### Infrastructure Diagnostics

```bash
# Check AKS cluster health
az aks show \
  --resource-group <rg-name> \
  --name <aks-name> \
  --query "{status:provisioningState,version:kubernetesVersion}"

# Check APIM status
az apim show \
  --resource-group <rg-name> \
  --name <apim-name> \
  --query "{status:provisioningState,sku:sku.name}"

# Check Key Vault status
az keyvault show \
  --name <kv-name> \
  --query "{status:properties.provisioningState}"

# List all resources in resource group
az resource list \
  --resource-group <rg-name> \
  --output table
```

### Kubernetes Diagnostics

```bash
# Get all resources
kubectl get all

# Get events
kubectl get events --sort-by='.lastTimestamp'

# Check nodes
kubectl get nodes

# Check node resources
kubectl top nodes

# Check services
kubectl get services

# Check ingress
kubectl get ingress

# Check configmaps
kubectl get configmaps

# Check secrets
kubectl get secrets
```

### APIM Diagnostics

```bash
# List APIs
az apim api list \
  --service-name <apim-name> \
  --resource-group <rg-name>

# List named values
az apim nv list \
  --service-name <apim-name> \
  --resource-group <rg-name>

# Get gateway URL
az apim show \
  --resource-group <rg-name> \
  --name <apim-name> \
  --query "gatewayUrl" -o tsv

# Test endpoint
TOKEN=$(az account get-access-token --resource api://<api-app-id> --query accessToken -o tsv)
curl -H "Authorization: Bearer $TOKEN" https://<apim-name>.azure-api.net/httpbin/test
```

### Azure AD Diagnostics

```bash
# List app registrations
az ad app list --display-name oauth-obo

# Show app registration
az ad app show --id <client-app-id>

# List permissions
az ad app permission list --id <client-app-id>

# List federated credentials
az ad app federated-credential list --id <client-app-id>

# Show user
az ad user show --id user@domain.com
```

## Getting Additional Help

### Collect Debug Information

When reporting issues, include:

1. **Deployment Information:**
```bash
# Get deployment outputs
az deployment sub show --name <deployment-name>
```

2. **Pod Logs:**
```bash
kubectl logs -l app=oauth-obo-client --tail=200 > pod-logs.txt
```

3. **Resource Status:**
```bash
kubectl get all -o yaml > k8s-resources.yaml
```

4. **Events:**
```bash
kubectl get events --sort-by='.lastTimestamp' > events.txt
```

### Additional Resources

- [Architecture Documentation](architecture/overview.md)
- [Deployment Guide](deployment/overview.md)
- [Monitoring Guide](operations/monitoring.md)
- [Lessons Learned](lessons-learned.md)
- [Azure Support](https://azure.microsoft.com/support)

### Common Solutions Summary

| Issue | Quick Fix |
|-------|-----------|
| 401 Unauthorized | Check token audience and APIM named values |
| Pod not starting | Check image pull, configuration, and logs |
| Login fails | Verify redirect URIs and app registration |
| Ingress pending | Enable Web Application Routing addon |
| Token acquisition fails | Check workload identity or client secret |
| Named values not syncing | Verify Key Vault RBAC permissions |
| High memory usage | Adjust resource limits in Helm |
| Slow responses | Check token caching and APIM performance |

---

**Note**: For detailed operational procedures, see the [Operations Guide](operations/monitoring.md).
