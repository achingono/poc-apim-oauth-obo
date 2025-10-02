# Troubleshooting Guide

This guide provides solutions to common issues encountered with the OAuth OBO POC.

## 🚨 Critical OAuth Issues - Quick Fixes

### AADSTS500011 Error (Most Common)
```bash
# ❌ Problem: OAuth scope configured as full URI
OAUTH_SCOPE="api://379eb22e-22d4-4990-8fdc-caef12894896/access_as_user"

# ✅ Solution: Use only the scope name
OAUTH_SCOPE="access_as_user"

# Fix in Helm:
helm upgrade oauth-obo ./helm --set azure.scope="access_as_user"
```

### ConfigMap Variables Empty
```bash
# Check if variables are set
kubectl get configmap oauth-obo-oauth-obo-client-config -o jsonpath='{.data.AZURE_CLIENT_ID}'

# If empty, fix with proper values:
helm upgrade oauth-obo ./helm \
  --values ./helm/values.yaml \
  --values ./helm/values-aks.yaml \
  --set azure.clientId="your-client-id" \
  --set azure.tenantId="your-tenant-id"
```

### Missing OAuth Scope in API App
```bash
# Check if scope exists
az ad app show --id <api-app-id> --query "api.oauth2PermissionScopes[?value=='access_as_user']"

# If empty, create scope:
SCOPE_ID=$(uuidgen)
az ad app update --id <api-app-id> --set api.oauth2PermissionScopes='[{
  "id": "'$SCOPE_ID'",
  "value": "access_as_user",
  "isEnabled": true,
  "type": "User"
}]'
```

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

### Issue: Helm Values Placeholders Not Replaced

**Symptoms**: 
- Pods show environment variables with placeholder values like `${AZURE_CLIENT_ID}`
- Application fails to start with missing configuration

**Root Cause**: Helm values loading order or missing override files

**Solution:**

**Check Values Loading Order:**
```bash
# Correct order (later values override earlier ones):
helm upgrade oauth-obo ./helm \
  --values ./helm/values.yaml \          # Base values
  --values ./helm/values-aks.yaml \      # Environment-specific
  --values app-config-override.yaml      # Generated overrides (LAST)
```

**Create Proper Override File:**
```bash
# Create override file with all required values
cat > app-config-override.yaml <<EOF
azure:
  tenantId: "your-tenant-id"
  clientId: "your-client-id" 
  apiAppId: "your-api-app-id"
  scope: "access_as_user"

image:
  repository: "your-acr.azurecr.io/poc/client"
  tag: "latest"

workloadIdentity:
  clientId: "your-workload-identity-client-id"
EOF
```

**Validate Template Rendering:**
```bash
# Test template rendering
helm template oauth-obo ./helm \
  --values ./helm/values.yaml \
  --values ./helm/values-aks.yaml \
  --values app-config-override.yaml \
  | grep -A 10 -B 10 "AZURE_CLIENT_ID"

# Should show actual values, not placeholders
```

### Issue: Pod Image Pull Errors

**Symptoms**: 
- Pods stuck in `ImagePullBackOff` or `ErrImagePull`
- Events show image pull authentication errors

**Solution:**

**For AKS with Workload Identity:**
```bash
# Verify managed identity has AcrPull role
az role assignment list \
  --assignee <workload-identity-client-id> \
  --query "[?roleDefinitionName=='AcrPull']"

# Grant AcrPull if missing
az role assignment create \
  --assignee <workload-identity-client-id> \
  --role AcrPull \
  --scope /subscriptions/<subscription-id>/resourceGroups/<rg>/providers/Microsoft.ContainerRegistry/registries/<acr-name>
```

**For Local Development:**
```bash
# Build image locally for minikube
eval $(minikube docker-env)
docker build -t poc/client:latest ./src/client

# Or push to public registry for testing
docker tag poc/client:latest your-registry/poc/client:latest
docker push your-registry/poc/client:latest
```

## Authentication Issues

### Issue: AADSTS500011 - Resource Principal Not Found

**Symptoms**: Error `AADSTS500011: The resource principal named api://xxx/api://xxx was not found`

**Root Cause**: OAuth scope configured incorrectly, causing duplicate API URI in the scope claim

**Solution:**

**Fix OAuth Scope Configuration:**
```bash
# ❌ WRONG: Don't use full URI in scope
# OAUTH_SCOPE="api://379eb22e-22d4-4990-8fdc-caef12894896/access_as_user"

# ✅ CORRECT: Use only the scope name
OAUTH_SCOPE="access_as_user"
```

**Steps to Fix:**
1. **Update Helm values:**
   ```yaml
   azure:
     scope: "access_as_user"  # NOT the full api:// URI
   ```

2. **Verify API App Configuration:**
   ```bash
   # Check API app has OAuth scope defined
   az ad app show --id <api-app-id> --query "api.oauth2PermissionScopes[?value=='access_as_user']"
   
   # Should return scope with proper ID and value
   ```

3. **Update ConfigMap:**
   ```bash
   # Check current value
   kubectl get configmap <config-name> -o jsonpath='{.data.OAUTH_SCOPE}'
   
   # Should be "access_as_user", not full URI
   ```

4. **Redeploy with corrected scope:**
   ```bash
   helm upgrade oauth-obo ./helm \
     --set azure.scope="access_as_user"
   ```

### Issue: Missing OAuth Scope in API App Registration

**Symptoms**: 
- Application fails to start with authentication errors
- Error about missing scope in token request

**Solution:**

**Create OAuth Scope in API App:**
```bash
# Generate new scope ID
SCOPE_ID=$(uuidgen)

# Create the OAuth scope
az ad app update --id <api-app-id> --set api.oauth2PermissionScopes='[{
  "id": "'$SCOPE_ID'",
  "adminConsentDescription": "Allow the application to access the API on behalf of the signed-in user",
  "adminConsentDisplayName": "Access API as user", 
  "isEnabled": true,
  "type": "User",
  "userConsentDescription": "Allow the application to access the API on your behalf",
  "userConsentDisplayName": "Access API as you",
  "value": "access_as_user"
}]'
```

**Grant Client App Permission:**
```bash
# Add permission to client app
az ad app permission add \
  --id <client-app-id> \
  --api <api-app-id> \
  --api-permissions $SCOPE_ID=Scope

# Grant admin consent
az ad app permission admin-consent --id <client-app-id>
```

### Issue: ConfigMap Environment Variables Missing

**Symptoms**: 
- Pod logs show "The 'ClientId' option must be provided"
- Application fails to start with ArgumentNullException

**Root Cause**: Helm values not properly set or override order incorrect

**Solution:**

**Check ConfigMap Values:**
```bash
# Check current ConfigMap
kubectl get configmap <config-name> -o yaml

# Look for empty values:
# AZURE_CLIENT_ID: ""
# AZURE_TENANT_ID: ""
```

**Fix Helm Values Order:**
```bash
# Correct order (last values override earlier ones):
helm upgrade oauth-obo ./helm \
  --values ./helm/values.yaml \
  --values ./helm/values-aks.yaml \
  --set azure.tenantId="<tenant-id>" \
  --set azure.clientId="<client-id>" \
  --set azure.apiAppId="<api-app-id>" \
  --set azure.scope="access_as_user"
```

**Validate Configuration:**
```bash
# All these should return non-empty values
kubectl get configmap <config-name> -o jsonpath='{.data.AZURE_CLIENT_ID}'
kubectl get configmap <config-name> -o jsonpath='{.data.AZURE_TENANT_ID}'
kubectl get configmap <config-name> -o jsonpath='{.data.API_APP_ID}'
kubectl get configmap <config-name> -o jsonpath='{.data.OAUTH_SCOPE}'
```

### Issue: Ingress Not Working

**Symptoms**: 
- Cannot access application via external IP
- Timeout or connection refused errors
- Ingress shows no external IP

**Solutions:**

**For AKS with Azure Web Application Routing:**
```bash
# Check if addon is enabled
az aks show --name <aks-name> --resource-group <rg-name> \
  --query addonProfiles.webApplicationRouting.enabled

# Enable if not already enabled
az aks addon enable --name web_application_routing \
  --resource-group <rg-name> --name <aks-name>

# Check ingress controller pods
kubectl get pods -n app-routing-system
```

**For Minikube:**
```bash
# Check if ingress addon is enabled
minikube addons list | grep ingress

# Enable ingress addon
minikube addons enable ingress

# Get minikube IP
minikube ip
```

**Check Ingress Configuration:**
```bash
# Verify ingress resource exists
kubectl get ingress

# Check ingress details
kubectl describe ingress <ingress-name>

# Verify service endpoints
kubectl get endpoints <service-name>
```

**Update App Registration Redirect URIs:**
```bash
# Get ingress external IP
EXTERNAL_IP=$(kubectl get ingress <ingress-name> -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Update redirect URIs
az ad app update --id <client-app-id> \
  --web-redirect-uris "http://$EXTERNAL_IP/signin-oidc" \
                      "http://localhost:5000/signin-oidc" \
                      "https://localhost:5001/signin-oidc"
```

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

### OAuth Configuration Diagnostics

```bash
# Complete OAuth configuration check
echo "=== OAuth Configuration Diagnostics ==="

# 1. Check app registration details
echo "--- Client App Registration ---"
az ad app show --id <client-app-id> --query "{appId:appId,displayName:displayName}"
az ad app show --id <client-app-id> --query "web.redirectUris" --output table

echo "--- API App Registration ---"
az ad app show --id <api-app-id> --query "{appId:appId,displayName:displayName}"
az ad app show --id <api-app-id> --query "identifierUris" --output table
az ad app show --id <api-app-id> --query "api.oauth2PermissionScopes[].{value:value,id:id}" --output table

# 2. Check client app permissions
echo "--- Client App Permissions ---"
az ad app permission list --id <client-app-id> --output table

# 3. Check ConfigMap values
echo "--- ConfigMap Configuration ---"
kubectl get configmap <config-name> -o jsonpath='{.data}' | jq '.'

# 4. Validate OAuth scope format
echo "--- OAuth Scope Validation ---"
OAUTH_SCOPE=$(kubectl get configmap <config-name> -o jsonpath='{.data.OAUTH_SCOPE}')
if [ "$OAUTH_SCOPE" = "access_as_user" ]; then
  echo "✓ OAuth scope format is correct"
else
  echo "❌ OAuth scope format is incorrect: $OAUTH_SCOPE"
  echo "   Should be: access_as_user"
fi

# 5. Test ingress and redirect URI
echo "--- Ingress and Redirect URI Check ---"
INGRESS_IP=$(kubectl get ingress <ingress-name> -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Ingress IP: $INGRESS_IP"
curl -I "http://$INGRESS_IP" 2>/dev/null | head -1
REDIRECT_URIS=$(az ad app show --id <client-app-id> --query "web.redirectUris" --output tsv)
echo "Redirect URIs: $REDIRECT_URIS"
echo "$REDIRECT_URIS" | grep -q "$INGRESS_IP" && echo "✓ Ingress IP found in redirect URIs" || echo "❌ Ingress IP missing from redirect URIs"
```

### Token Validation Diagnostics

```bash
# Test token acquisition and validation
echo "=== Token Validation ==="

# 1. Get token for API app
echo "--- Getting Access Token ---"
TOKEN=$(az account get-access-token --resource "api://<api-app-id>" --query accessToken -o tsv 2>/dev/null)
if [ $? -eq 0 ] && [ "$TOKEN" != "" ]; then
  echo "✓ Successfully acquired token"
  
  # 2. Decode token (requires jq and base64)
  echo "--- Token Claims ---"
  PAYLOAD=$(echo $TOKEN | cut -d. -f2)
  # Add padding if needed
  while [ $((${#PAYLOAD} % 4)) -ne 0 ]; do PAYLOAD="${PAYLOAD}="; done
  echo $PAYLOAD | base64 -d 2>/dev/null | jq '.aud, .scp, .appid' 2>/dev/null || echo "Could not decode token"
  
  # 3. Test APIM endpoint
  echo "--- Testing APIM Endpoint ---"
  APIM_URL=$(kubectl get configmap <config-name> -o jsonpath='{.data.APIM_BASE_URL}')
  curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
    -H "Authorization: Bearer $TOKEN" \
    "$APIM_URL/get"
else
  echo "❌ Failed to acquire token"
fi
```

### Pod Startup Diagnostics

```bash
# Comprehensive pod diagnostics
echo "=== Pod Startup Diagnostics ==="

# 1. Check pod status and events
POD_NAME=$(kubectl get pods -l app.kubernetes.io/name=oauth-obo-client -o jsonpath='{.items[0].metadata.name}')
echo "Pod: $POD_NAME"
kubectl get pod $POD_NAME -o jsonpath='{.status.phase}'
echo ""

# 2. Check environment variables in pod
echo "--- Environment Variables ---"
kubectl exec $POD_NAME -- env | grep -E "(AZURE|OAUTH|API)" | sort

# 3. Check for startup errors
echo "--- Startup Logs ---"
kubectl logs $POD_NAME --tail=20 | grep -E -i "(error|exception|fail|warn)"

# 4. Check service account and workload identity
echo "--- Service Account Configuration ---"
kubectl get pod $POD_NAME -o jsonpath='{.spec.serviceAccount}'
echo ""
SA_NAME=$(kubectl get pod $POD_NAME -o jsonpath='{.spec.serviceAccount}')
kubectl get serviceaccount $SA_NAME -o jsonpath='{.metadata.annotations}' | jq '.'

# 5. Test internal connectivity
echo "--- Internal Connectivity ---"
kubectl exec $POD_NAME -- curl -s -o /dev/null -w "Status: %{http_code}\n" http://localhost:8080/health 2>/dev/null || echo "Health endpoint not available"
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

| Issue | Symptoms | Quick Fix |
|-------|----------|-----------|
| AADSTS500011 Error | Resource principal not found | Fix OAuth scope: use `access_as_user` not full URI |
| ConfigMap variables empty | Pods fail with missing ClientId | Check Helm values order, use --set for overrides |
| OAuth scope missing | Authentication fails at startup | Create OAuth scope in API app registration |
| 401 Unauthorized | API calls rejected | Check token audience and APIM named values |
| Pod not starting | ImagePullBackOff or startup errors | Check image pull, configuration, and logs |
| Login redirect loop | Endless redirects during sign-in | Verify redirect URIs match ingress URL |
| Ingress no external IP | Cannot access application | Enable Web Application Routing addon |
| Token acquisition fails | MSAL authentication errors | Check workload identity or client secret |
| Named values not syncing | APIM policy failures | Verify Key Vault RBAC permissions |
| Helm values not applied | Placeholder values in ConfigMap | Ensure proper values file loading order |
| High memory usage | Pods getting OOMKilled | Adjust resource limits in Helm values |
| Slow responses | Long authentication delays | Check token caching and APIM performance |

---

## OAuth Configuration Lessons Learned

### Key Insights from Implementation

1. **OAuth Scope Format is Critical**
   - ❌ **Never** use full URI in scope configuration: `api://app-id/scope-name`
   - ✅ **Always** use just the scope name: `scope-name`
   - The Microsoft Identity Web library automatically constructs the full scope URI

2. **Helm Values Loading Order Matters**
   - Values are applied in order, with later values overriding earlier ones
   - Always put environment-specific values (like `values-aks.yaml`) after base values
   - Use `--set` flags as the final override for critical values

3. **Azure AD App Registration Configuration**
   - API app must have `identifierUris` set to `api://app-id`
   - OAuth scopes must be defined in the API app's `api.oauth2PermissionScopes`
   - Client app must have permissions granted to the API app
   - Redirect URIs must exactly match the ingress URL format

4. **ConfigMap Environment Variables**
   - Pod startup failures are often due to missing environment variables
   - Always validate ConfigMap contents after Helm deployment
   - Use `kubectl get configmap -o yaml` to verify actual values vs templates

5. **Ingress and Redirect URI Synchronization**
   - Ingress external IP can take time to provision
   - Always update app registration redirect URIs after ingress is ready
   - Use both HTTP and HTTPS redirect URIs for flexibility

6. **Workload Identity vs Client Secret**
   - Workload Identity requires proper service account annotations
   - Federated credentials must match Kubernetes service account exactly
   - Client secrets are simpler for local development but less secure

### Debugging Workflow

When facing OAuth issues, follow this order:

1. **Check Pod Logs**: Look for specific error messages about missing configuration
2. **Validate ConfigMap**: Ensure all environment variables have actual values, not placeholders
3. **Verify App Registrations**: Check both API and client apps have correct configuration
4. **Test OAuth Flow**: Use browser developer tools to inspect redirect URLs and error codes
5. **Validate Tokens**: Decode JWT tokens to verify audience and scope claims

**Note**: For detailed operational procedures, see the [Operations Guide](operations/monitoring.md).
