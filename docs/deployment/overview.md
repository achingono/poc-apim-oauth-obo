# Deployment Overview

This document provides a comprehensive overview of the deployment process for the OAuth OBO POC.

## Table of Contents

- [Deployment Options](#deployment-options)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Deployment Architecture](#deployment-architecture)
- [Deployment Steps](#deployment-steps)
- [Post-Deployment Validation](#post-deployment-validation)
- [Related Documentation](#related-documentation)

## Deployment Options

The POC supports two primary deployment scenarios:

### 1. Cloud Deployment (Azure AKS)

**Best For**: Production-like testing, full workload identity validation

**Components Deployed:**
- Azure API Management
- Azure Kubernetes Service (AKS)
- Azure Key Vault
- Azure Container Registry
- Azure Active Directory App Registrations
- Managed Identity with Federated Credentials
- Application Insights

**Deployment Time**: ~3-4 minutes (automated)

**Cost**: ~$2-5/day (Developer SKU APIM + AKS)

### 2. Local Deployment (Minikube)

**Best For**: Local development, testing changes quickly

**Components Deployed:**
- Minikube Kubernetes cluster (local)
- Client application in Kubernetes
- Uses cloud-based APIM and Azure AD

**Deployment Time**: ~2-3 minutes

**Cost**: Free (uses existing Azure resources)

## Prerequisites

### Required Tools

| Tool | Minimum Version | Purpose |
|------|-----------------|---------|
| Azure CLI | 2.47.0+ | Azure resource management |
| .NET SDK | 9.0+ | Build client application |
| Docker | 20.10+ | Container image building |
| Helm | 3.0+ | Kubernetes package management |
| kubectl | 1.19+ | Kubernetes cluster management |
| Minikube | 1.25+ | Local Kubernetes (local deployment only) |
| jq | 1.6+ | JSON processing in scripts |
| git | 2.0+ | Source code management |

### Azure Requirements

**Azure Subscription:**
- Active Azure subscription
- Permissions to create resource groups
- Permissions to create Azure AD app registrations

**Azure AD Permissions:**
- Application.ReadWrite.All (or Application.ReadWrite.OwnedBy minimum)
- Group.ReadWrite.All

**Resource Providers:**
- Microsoft.ContainerRegistry
- Microsoft.ContainerService
- Microsoft.ApiManagement
- Microsoft.KeyVault
- Microsoft.Insights
- Microsoft.OperationalInsights

### Install Required Tools

**macOS:**
```bash
# Install Homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install tools
brew install azure-cli
brew install dotnet
brew install docker
brew install helm
brew install kubectl
brew install minikube
brew install jq
```

**Ubuntu/Debian:**
```bash
# Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# .NET SDK
wget https://dot.net/v1/dotnet-install.sh
chmod +x dotnet-install.sh
./dotnet-install.sh --channel 9.0

# Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# jq
sudo apt-get install jq
```

**Windows (PowerShell):**
```powershell
# Install Chocolatey
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Install tools
choco install azure-cli
choco install dotnet-sdk
choco install docker-desktop
choco install kubernetes-helm
choco install kubernetes-cli
choco install minikube
choco install jq
```

## Quick Start

### Automated Deployment (Recommended)

The repository includes a fully automated deployment script that handles everything:

```bash
# Clone repository
git clone https://github.com/achingono/poc-apim-oauth-obo.git
cd poc-apim-oauth-obo

# Authenticate with Azure
az login

# Deploy everything (3-4 minutes)
./deploy.sh -n oauth-obo -l eastus -s poc -c true -b true
```

**Script Parameters:**
- `-n`: Deployment name (3-21 characters)
- `-l`: Azure region (e.g., eastus, westus2)
- `-s`: Unique suffix (3-23 alphanumeric characters)
- `-c`: Deploy to cloud (true/false, default: true)
- `-b`: Build container images (true/false, default: true)

### Local Development Deployment

```bash
# Start minikube and deploy to local cluster
./deploy.sh -n oauth-obo -l eastus -s dev -c false -b true
```

## Deployment Architecture

### Cloud Deployment Flow

```
┌─────────────────────────────────────────────────────────┐
│ 1. Create Azure AD App Registrations                    │
│    - Client app (for user authentication)               │
│    - API app (backend representation)                    │
│    - Security groups (admin, standard users)            │
│    - Permissions and consent                            │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│ 2. Deploy Azure Infrastructure (Bicep)                  │
│    - Resource Group                                      │
│    - Azure Kubernetes Service (AKS)                      │
│    - API Management (APIM)                               │
│    - Key Vault with secrets                              │
│    - Container Registry                                  │
│    - Managed Identity                                    │
│    - Federated Credentials                               │
│    - Application Insights                                │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│ 3. Build and Push Container Images                      │
│    - Build .NET application                              │
│    - Create Docker image                                 │
│    - Push to Azure Container Registry                    │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│ 4. Configure Kubernetes Ingress                         │
│    - Enable Web Application Routing                      │
│    - Create Ingress resource                             │
│    - Configure DNS and SSL                               │
│    - Update Azure AD redirect URIs                       │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│ 5. Deploy Application to Kubernetes (Helm)              │
│    - Create namespace                                    │
│    - Deploy Helm chart                                   │
│    - Configure workload identity                         │
│    - Create service account                              │
│    - Deploy pods                                         │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│ 6. Validate Deployment                                   │
│    - Check pod status                                    │
│    - Verify ingress                                      │
│    - Test authentication                                 │
│    - Validate API calls                                  │
└──────────────────────────────────────────────────────────┘
```

### Local Deployment Flow

```
┌─────────────────────────────────────────────────────────┐
│ 1. Start Minikube (if not running)                      │
│    - Docker driver                                       │
│    - Enable ingress addon                                │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│ 2. Build Container Image                                │
│    - Build .NET application                              │
│    - Create Docker image                                 │
│    - Load into minikube                                  │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│ 3. Deploy Application (Helm)                            │
│    - Use values-local.yaml                               │
│    - Include client secret                               │
│    - Configure ingress                                   │
│    - Deploy to default namespace                         │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│ 4. Configure Local Access                               │
│    - Add /etc/hosts entry                                │
│    - Update Azure AD redirect URIs                       │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│ 5. Validate Deployment                                   │
│    - Check pod status                                    │
│    - Test local URL                                      │
│    - Verify authentication                               │
└──────────────────────────────────────────────────────────┘
```

## Deployment Steps

### Step 1: Clone Repository

```bash
git clone https://github.com/achingono/poc-apim-oauth-obo.git
cd poc-apim-oauth-obo
```

### Step 2: Authenticate with Azure

```bash
# Login to Azure
az login

# Set default subscription (if you have multiple)
az account set --subscription "Your Subscription Name"

# Verify authentication
az account show
```

### Step 3: Run Deployment Script

**Cloud Deployment:**
```bash
./deploy.sh -n oauth-obo -l eastus -s poc -c true -b true
```

**Local Deployment:**
```bash
./deploy.sh -n oauth-obo -l eastus -s dev -c false -b true
```

### Step 4: Monitor Deployment

The script provides real-time output for each step:

```
🚀 Starting deployment: oauth-obo-poc
📍 Region: eastus
☁️  Mode: Cloud deployment

📝 Creating Azure AD app registrations...
   ✅ API app created: oauth-obo-poc-api
   ✅ Client app created: oauth-obo-poc-client
   ✅ Permissions configured

🏗️  Deploying Azure infrastructure...
   ✅ Resource group created
   ✅ AKS cluster deployed
   ✅ APIM service deployed
   ✅ Key Vault created
   ✅ Secrets populated

🐳 Building container images...
   ✅ .NET application built
   ✅ Docker image created
   ✅ Image pushed to ACR

🌐 Configuring ingress...
   ✅ Ingress enabled
   ✅ External IP assigned
   ✅ Redirect URIs updated

📦 Deploying to Kubernetes...
   ✅ Helm chart installed
   ✅ Pods running
   ✅ Service created

✅ Deployment completed successfully!
⏱️  Total time: 3m 42s
```

### Step 5: Access Application

**Cloud Deployment:**
```bash
# Get ingress URL
INGRESS_URL=$(kubectl get ingress -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
echo "Application URL: http://$INGRESS_URL"

# Open in browser
open "http://$INGRESS_URL"
```

**Local Deployment:**
```bash
# Add hosts entry (Linux/macOS)
echo "$(minikube ip) local.oauth-obo.dev" | sudo tee -a /etc/hosts

# Open in browser
open "http://local.oauth-obo.dev"
```

## Post-Deployment Validation

### 1. Verify Kubernetes Resources

```bash
# Check namespace
kubectl get namespaces

# Check pods
kubectl get pods -n default

# Check services
kubectl get services -n default

# Check ingress
kubectl get ingress -n default

# View pod logs
kubectl logs -l app=oauth-obo-client -n default --tail=50
```

### 2. Verify Azure Resources

```bash
# List resource groups
az group list --query "[?contains(name,'oauth-obo')].name" -o table

# Check AKS cluster
az aks list --query "[?contains(name,'oauth-obo')].[name,provisioningState]" -o table

# Check APIM service
az apim list --query "[?contains(name,'oauth-obo')].[name,provisioningState]" -o table

# Check Key Vault
az keyvault list --query "[?contains(name,'oauth-obo')].[name,properties.provisioningState]" -o table
```

### 3. Test Authentication Flow

```bash
# Get application URL
APP_URL=$(kubectl get ingress -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')

# Test unauthenticated access (should redirect to login)
curl -I "http://$APP_URL"

# Expected: 302 redirect to login.microsoftonline.com
```

### 4. Test API Calls

After signing in via browser:

1. Navigate to application URL
2. Sign in with Azure AD credentials
3. Send a test message in the chat interface
4. Verify response shows injected headers:
   - `X-API-Key`: ADMIN or STANDARD
   - `X-User-Role`: admin or user

### 5. Verify Workload Identity (Cloud Only)

```bash
# Check service account
kubectl get serviceaccount -n default

# Check service account annotations
kubectl get serviceaccount oauth-obo-client-sa -n default -o yaml

# Check pod labels
kubectl get pods -n default -l app=oauth-obo-client -o yaml | grep -A 5 labels

# Check pod logs for token acquisition
kubectl logs -l app=oauth-obo-client -n default | grep "WorkloadIdentityTokenService"
```

Expected log output:
```
info: client.Services.WorkloadIdentityTokenService[0]
      WorkloadIdentityTokenService initialized for AKS production environment
```

## Troubleshooting Common Issues

### Issue: Deployment Script Fails

**Symptoms**: Script exits with error

**Solutions**:
1. Check Azure CLI authentication: `az account show`
2. Verify Azure AD permissions
3. Check script permissions: `chmod +x deploy.sh`
4. Review error messages in output

### Issue: Pods Not Starting

**Symptoms**: Pods in CrashLoopBackOff or Error state

**Solutions**:
```bash
# Check pod status
kubectl get pods -n default

# View pod logs
kubectl logs <pod-name> -n default

# Describe pod
kubectl describe pod <pod-name> -n default

# Common causes:
# - Image pull errors (check ACR access)
# - Configuration errors (check ConfigMap/Secret)
# - Missing environment variables
```

### Issue: Authentication Redirects Fail

**Symptoms**: Login redirects to error page

**Solutions**:
1. Verify redirect URIs in Azure AD app registration
2. Check ingress URL matches redirect URI
3. Ensure HTTPS redirect URIs (if using TLS)
4. Verify client ID and tenant ID configuration

### Issue: API Calls Return 401

**Symptoms**: APIM returns Unauthorized

**Solutions**:
```bash
# Check APIM named values
az apim nv list --service-name <apim-name> --resource-group <rg-name>

# Verify Key Vault sync
az apim nv show --service-name <apim-name> --resource-group <rg-name> --named-value-id api_app_id

# Check token audience
# Token should have aud: api://<api-app-id>

# Verify JWT validation policy
# Check policy in Azure Portal
```

See: [Troubleshooting Guide](../troubleshooting.md) for more details

## Cleanup

### Automated Cleanup

```bash
# Remove Azure resources only
./scripts/cleanup.sh -n oauth-obo -s poc

# Remove Azure resources AND app registrations
./scripts/cleanup.sh -n oauth-obo -s poc -a
```

### Manual Cleanup

**Azure Resources:**
```bash
# Delete resource group (removes all resources)
az group delete --name rg-oauth-obo-poc-eastus --yes --no-wait
```

**Azure AD App Registrations:**
```bash
# List app registrations
az ad app list --display-name oauth-obo

# Delete apps
az ad app delete --id <client-app-id>
az ad app delete --id <api-app-id>
```

**Local Resources:**
```bash
# Delete Helm release
helm uninstall oauth-obo-client -n default

# Stop minikube
minikube stop

# Delete minikube cluster
minikube delete
```

## Related Documentation

### Architecture
- [Architecture Overview](../architecture/overview.md)
- [Application Architecture](../architecture/application.md)
- [APIM Configuration](../architecture/apim.md)
- [Security Architecture](../architecture/security.md)

### Detailed Deployment Guides
- [Prerequisites](prerequisites.md)
- [Infrastructure Deployment](infrastructure.md)
- [Application Deployment](application.md)

### Operations
- [Troubleshooting Guide](../troubleshooting.md)
- [Monitoring and Logging](../operations/monitoring.md)

### Reference
- [Deployment Script Documentation](../deployment-script.md)
- [Helm Chart Documentation](../helm.md)
- [Infrastructure as Code](../../iac/README.md)
