# Getting Started Guide

This guide will help you get the OAuth OBO POC up and running quickly.

## Table of Contents

- [What You'll Build](#what-youll-build)
- [Quick Start (5 Minutes)](#quick-start-5-minutes)
- [Understanding the Components](#understanding-the-components)
- [Testing the Application](#testing-the-application)
- [Next Steps](#next-steps)

## What You'll Build

By following this guide, you'll deploy a complete OAuth 2.0 On-Behalf-Of flow demonstration that includes:

```
User → .NET Web App → Azure AD → APIM → HTTPBin
         (AKS)                  (Policies)
```

**What It Does:**
1. User authenticates via Azure AD
2. Application acquires OBO token using workload identity (no secrets!)
3. Application calls APIM with Bearer token
4. APIM validates JWT and injects headers based on user groups
5. Request forwarded to HTTPBin which echoes everything back
6. Response shows the injected headers proving the flow works

## Quick Start (5 Minutes)

### Option 1: Cloud Deployment (Recommended)

```bash
# 1. Clone repository
git clone https://github.com/achingono/poc-apim-oauth-obo.git
cd poc-apim-oauth-obo

# 2. Login to Azure
az login

# 3. Run deployment script
./deploy.sh -n myoauth -l eastus -s demo

# 4. Wait 3-4 minutes for deployment to complete

# 5. Get application URL
kubectl get ingress -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}'

# 6. Open in browser and sign in!
```

### Option 2: Local Development

```bash
# 1. Clone repository
git clone https://github.com/achingono/poc-apim-oauth-obo.git
cd poc-apim-oauth-obo

# 2. Login to Azure
az login

# 3. Start minikube
minikube start

# 4. Run local deployment
./deploy.sh -n myoauth -l eastus -s dev -c false

# 5. Add hosts entry
echo "$(minikube ip) local.oauth-obo.dev" | sudo tee -a /etc/hosts

# 6. Open http://local.oauth-obo.dev in browser
```

## Understanding the Components

### 1. Azure Active Directory

**What It Does:**
- Authenticates users
- Issues access tokens
- Handles OBO token exchange

**What Gets Created:**
- Client app registration (for user login)
- API app registration (backend identity)
- Security groups (admin and standard users)

**Configuration:**
```
Client App:
  - Type: Web application
  - Redirect URI: http://<app-url>/signin-oidc
  - Permissions: API permission for backend

API App:
  - Exposed Scope: access_as_user
  - Audience: api://<api-app-id>
```

### 2. .NET Client Application

**What It Does:**
- Provides chat UI for testing
- Authenticates users via OAuth
- Acquires tokens using workload identity
- Calls APIM with Bearer token

**Key Features:**
- Environment-aware token acquisition
- In-memory token caching
- Automatic token refresh
- Error handling and logging

**Technology:**
- ASP.NET Core 9.0
- Razor Pages
- Microsoft.Identity.Web
- MSAL

### 3. Azure API Management

**What It Does:**
- Validates JWT tokens
- Checks audience and scope
- Maps groups to access levels
- Injects custom headers

**Policy Flow:**
```
1. Validate JWT
   ├─ Verify signature
   ├─ Check expiration
   ├─ Validate audience
   └─ Validate scope

2. Check User Groups
   └─ Extract from token claims

3. Inject Headers
   ├─ X-API-Key: ADMIN or STANDARD
   └─ X-User-Role: admin or user

4. Forward to Backend
   └─ HTTPBin echoes request
```

### 4. Azure Kubernetes Service

**What It Does:**
- Runs containerized application
- Provides workload identity
- Manages ingress/routing

**Features:**
- OIDC issuer enabled
- Workload identity integration
- Web Application Routing
- Managed identity

### 5. HTTPBin Backend

**What It Does:**
- Test backend that echoes requests
- Shows all headers including injected ones
- No authentication required

**Why HTTPBin:**
- Perfect for testing
- Shows complete request details
- Easy to verify policy enforcement

## Testing the Application

### 1. Sign In

1. Navigate to application URL
2. Click "Sign In" button
3. Enter Azure AD credentials
4. Consent to permissions (first time only)
5. Redirected back to application

**What Happens:**
- Authorization Code Flow with PKCE
- Token stored in session and cache
- User profile loaded

### 2. Send Test Message

1. Type a message in the chat box
2. Click Send
3. Wait for response (1-2 seconds)

**What You'll See:**
```json
{
  "args": {},
  "headers": {
    "Authorization": "Bearer eyJ0eXAiOiJKV1Qi...",
    "Host": "httpbin.org",
    "X-Api-Key": "STANDARD",
    "X-User-Role": "user",
    "X-User-Message": "Hello World"
  },
  "url": "https://httpbin.org/get"
}
```

**Key Points:**
- ✅ Authorization header contains Bearer token
- ✅ X-API-Key shows STANDARD (or ADMIN if in admin group)
- ✅ X-User-Role shows user (or admin)
- ✅ Your custom X-User-Message appears

### 3. Verify Group-Based Authorization

**Test as Standard User:**
```json
{
  "headers": {
    "X-Api-Key": "STANDARD",
    "X-User-Role": "user"
  }
}
```

**Test as Admin User:**
1. Add yourself to admin group in Azure AD
2. Sign out and sign in again
3. Send message

```json
{
  "headers": {
    "X-Api-Key": "ADMIN",
    "X-User-Role": "admin"
  }
}
```

### 4. Test Token Validation

**Test Invalid Token:**
```bash
# Call APIM without token (should fail)
curl http://<app-url>/httpbin/test

# Expected: 401 Unauthorized
```

**Test Token Caching:**
1. Send first message (acquires token)
2. Send second message immediately
3. Check logs - should use cached token

```bash
kubectl logs -l app=oauth-obo-client --tail=50
```

Expected: No "Acquiring token" log for second call

## Verify Workload Identity

### Check Service Account

```bash
# View service account
kubectl get serviceaccount oauth-obo-client-sa -o yaml

# Should see annotation:
# azure.workload.identity/client-id: <managed-identity-client-id>
```

### Check Pod Labels

```bash
# View pod labels
kubectl get pods -l app=oauth-obo-client -o yaml | grep -A 5 labels

# Should see label:
# azure.workload.identity/use: "true"
```

### Check Token Acquisition Logs

```bash
# View application logs
kubectl logs -l app=oauth-obo-client --tail=100

# Should see:
# WorkloadIdentityTokenService initialized for AKS production environment
# Acquiring token for user using workload identity
```

## Common First-Time Issues

### Issue: Can't Access Application URL

**Symptom**: Browser shows "Cannot connect"

**Solutions:**
```bash
# Check ingress status
kubectl get ingress

# Wait for EXTERNAL-IP to be assigned (may take 2-3 minutes)
# If stuck in <pending>:
kubectl describe ingress oauth-obo-client

# For local deployment, verify /etc/hosts:
cat /etc/hosts | grep oauth-obo
```

### Issue: Authentication Redirect Loop

**Symptom**: Login keeps redirecting

**Solutions:**
1. Check redirect URIs match exactly in Azure AD
2. Verify client ID is correct
3. Clear browser cookies and try again

```bash
# Verify configuration
kubectl get configmap oauth-obo-client-config -o yaml
```

### Issue: 401 Unauthorized from APIM

**Symptom**: API calls return 401

**Solutions:**
```bash
# Check APIM named values
az apim nv list \
  --service-name <apim-name> \
  --resource-group <rg-name> \
  --query "[].{name:name,value:properties.value}"

# Verify Key Vault sync
az apim nv show \
  --service-name <apim-name> \
  --resource-group <rg-name> \
  --named-value-id api_app_id
```

### Issue: Pod Not Starting

**Symptom**: Pod in CrashLoopBackOff

**Solutions:**
```bash
# Check pod logs
kubectl logs <pod-name>

# Describe pod
kubectl describe pod <pod-name>

# Common causes:
# - Image pull error (check ACR access)
# - Configuration error (check ConfigMap)
# - Missing environment variables
```

## Next Steps

### 1. Explore the Code

**Application Code:**
```bash
cd src/client

# View token acquisition services
cat Services/WorkloadIdentityTokenService.cs
cat Services/ClientSecretTokenService.cs

# View API client
cat Services/ApiClient.cs

# View chat interface
cat Pages/Index.cshtml.cs
```

**Infrastructure Code:**
```bash
cd iac

# View main template
cat main.bicep

# View APIM module
cat modules/apim.bicep

# View OAuth policy
cat policies/oauth-policy.xml
```

### 2. Customize the Deployment

**Change Application Name:**
```bash
./deploy.sh -n mycustom -l eastus -s prod
```

**Use Different Region:**
```bash
./deploy.sh -n oauth -l westus2 -s demo
```

**Modify APIM Policy:**
1. Edit `iac/policies/oauth-policy.xml`
2. Redeploy infrastructure
3. Test changes

### 3. Add Custom Backend

Replace HTTPBin with your own API:

1. Update `iac/policies/oauth-policy.xml`:
```xml
<set-backend-service base-url="https://your-api.com" />
<rewrite-uri template="/your-endpoint" />
```

2. Add backend authentication if needed:
```xml
<authentication-managed-identity resource="https://your-api.com" />
```

3. Redeploy infrastructure

### 4. Implement Additional Features

**Add More User Groups:**
```xml
<when condition="@(context.User.Groups.Any(g => g.Id == "{{viewer_group_id}}"))">
    <set-header name="X-API-Key" exists-action="override">
        <value>VIEWER</value>
    </set-header>
</when>
```

**Add Rate Limiting:**
```xml
<rate-limit calls="100" renewal-period="60" />
```

**Add Request Validation:**
```xml
<validate-content unspecified-content-type-action="prevent" 
                  max-size="102400" 
                  size-exceeded-action="prevent" />
```

### 5. Monitor and Troubleshoot

**View Application Logs:**
```bash
kubectl logs -l app=oauth-obo-client --tail=100 -f
```

**View APIM Logs:**
```bash
# Enable APIM diagnostics in Azure Portal
# View logs in Application Insights
```

**Check Resource Health:**
```bash
# AKS cluster
az aks show --resource-group <rg> --name <aks-name> --query provisioningState

# APIM service
az apim show --resource-group <rg> --name <apim-name> --query provisioningState
```

### 6. Learn More

**Architecture:**
- [Architecture Overview](architecture/overview.md)
- [Application Architecture](architecture/application.md)
- [APIM Configuration](architecture/apim.md)

**Deployment:**
- [Deployment Overview](deployment/overview.md)
- [Infrastructure Deployment](deployment/infrastructure.md)

**Development:**
- [Developer Guide](development/guide.md)
- [Source Code Overview](../src/README.md)

**Operations:**
- [Troubleshooting Guide](troubleshooting.md)
- [Monitoring Guide](operations/monitoring.md)

## Getting Help

### Check Logs

**Application Logs:**
```bash
kubectl logs -l app=oauth-obo-client --tail=100
```

**Pod Status:**
```bash
kubectl get pods
kubectl describe pod <pod-name>
```

**Events:**
```bash
kubectl get events --sort-by='.lastTimestamp'
```

### Review Documentation

1. [Troubleshooting Guide](troubleshooting.md) - Common issues and solutions
2. [Lessons Learned](lessons-learned.md) - Known issues and workarounds
3. [Requirements](requirements.md) - Detailed requirements and design

### Ask Questions

- Open an issue on GitHub
- Review existing issues for similar problems
- Check Azure AD and APIM documentation

## Summary

You now have a fully functional OAuth OBO implementation with:

✅ User authentication via Azure AD  
✅ Token acquisition using workload identity  
✅ JWT validation in APIM  
✅ Group-based authorization  
✅ Header injection for backend  
✅ End-to-end testing capability  

The deployment is production-ready with modern security practices:
- No secrets in Kubernetes
- RBAC-based access control
- Federated credential authentication
- Comprehensive policy enforcement

**Next:** Customize it for your needs and explore the codebase!
