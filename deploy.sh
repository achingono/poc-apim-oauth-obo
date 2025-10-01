#!/bin/bash

# Source .env if available
if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

while getopts n:l:s:c:b: flag
do
    case "${flag}" in
        n) DEPLOYMENT_NAME=${OPTARG};;
        l) DEPLOYMENT_LOCATION=${OPTARG};;
        s) DEPLOYMENT_SUFFIX=${OPTARG};;
        c) CLOUD=${OPTARG};;
        b) BUILD=${OPTARG};;
    esac
done

if [ "$DEPLOYMENT_NAME" == "" ] || [ "$DEPLOYMENT_LOCATION" == "" ] || [ "$DEPLOYMENT_SUFFIX" == "" ]; then
 echo "❌ Missing required parameters"
 echo ""
 echo "Usage: $0 -n <name> -l <location> -s <unique suffix> [-c <cloud>] [-b <build>]"
 echo ""
 echo "Required Parameters:"
 echo "  -n <name>           Deployment name (3-21 characters)"
 echo "  -l <location>       Azure region (e.g., eastus, westus2)"
 echo "  -s <suffix>         Unique suffix (3-23 alphanumeric characters)"
 echo ""
 echo "Optional Parameters:"
 echo "  -c <cloud>          Deploy to cloud (true/false/0/1, default: true)"
 echo "  -b <build>          Build container images (true/false/0/1, default: true)"
 echo ""
 echo "Examples:"
 echo "  $0 -n myapp -l eastus -s dev123"
 echo "  $0 -n myapp -l eastus -s dev123 -c false -b false"
 echo ""
 exit 1;
elif [[ $DEPLOYMENT_SUFFIX =~ [^a-zA-Z0-9] ]]; then
 echo "❌ Invalid suffix: must contain ONLY letters and numbers"
 echo "Syntax: $0 -n <name> -l <location> -s <unique suffix> -c <true|false|0|1> -b <true|false|0|1>"
 exit 1;
fi

if [ "$CLOUD" == "" ]; then
    CLOUD="true"
elif [ "$CLOUD" != "true" ] && [ "$CLOUD" != "false" ] && [ "$CLOUD" != "0" ] && [ "$CLOUD" != "1" ]; then
    CLOUD="false"
fi

if [ "$BUILD" == "" ]; then
    BUILD="true"
elif [ "$BUILD" != "true" ] && [ "$BUILD" != "false" ] && [ "$BUILD" != "0" ] && [ "$BUILD" != "1" ]; then
    BUILD="false"
fi

SECONDS=0
echo "Start time: $(date)"

# Source functions
source ./scripts/functions.sh

# Create Azure AD app registrations first
create_app_registrations

if [ "$BUILD" == "true" ] || [ "$BUILD" == "1" ]; then
   build_and_push_images
fi

if [ "$CLOUD" == "true" ] || [ "$CLOUD" == "1" ]; then
    # Provision Azure infrastructure
    provision_infrastructure
    
    # Enable AKS ingress addon
    enable_aks_ingress "$RESOURCE_GROUP" "$CLUSTER_NAME"
else
    # start minikube if not running
    if ! minikube status &> /dev/null; then
        echo "Starting minikube..."
        minikube start --driver=docker
    fi
    
    # Enable minikube ingress
    enable_minikube_ingress
fi

echo "Deploying to Kubernetes..."

# Determine which values file to use based on deployment target
# Note: Don't set HELM_VALUES_ARGS here, we'll do it after creating overrides

if [ "$NAMESPACE" == "" ]; then
    NAMESPACE="default"
fi

# Get deployment outputs for cloud deployments
if [ "$CLOUD" == "true" ] || [ "$CLOUD" == "1" ]; then
    echo "Retrieving deployment outputs..."
    WORKLOAD_IDENTITY=$(az deployment sub show --name $DEPLOYMENT_NAME --query properties.outputs.workloadIdentityClientId.value -o tsv)
    GATEWAY_URL=$(az deployment sub show --name $DEPLOYMENT_NAME --query properties.outputs.gatewayUrl.value -o tsv)
    ACR_NAME=$(az deployment sub show --name $DEPLOYMENT_NAME --query properties.outputs.acrName.value -o tsv)
    
    # Build image repository path for AKS
    COMMIT_HASH=$(git rev-parse HEAD 2>/dev/null || echo "latest")
    SHORT_HASH=${COMMIT_HASH::8}
    if [ "$ACR_NAME" != "" ]; then
        IMAGE_REPOSITORY="$ACR_NAME.azurecr.io/poc/client"
        IMAGE_TAG="$SHORT_HASH"
    else
        IMAGE_REPOSITORY="poc/client"
        IMAGE_TAG="latest"
    fi
else
    # For local/minikube deployment
    IMAGE_REPOSITORY="poc/client"
    IMAGE_TAG="latest"
    WORKLOAD_IDENTITY=""
    GATEWAY_URL="https://your-apim-name.azure-api.net/httpbin"
fi

# Create values override file with app registration details if they exist
if [ "$CLIENT_APP_ID" != "" ] && [ "$API_APP_ID" != "" ]; then
    echo "Creating Helm values override with app registration details..."
    cat > app-config-override.yaml <<EOF
# Complete override to replace all placeholder values
image:
  repository: "$IMAGE_REPOSITORY"
  tag: "$IMAGE_TAG"

# Azure configuration with real values
azure:
  tenantId: "$TENANT_ID"
  clientId: "$CLIENT_APP_ID"
  apiAppId: "$API_APP_ID"
  scope: "api://$API_APP_ID/access_as_user"

# APIM configuration with real values
apim:
  baseUrl: "$GATEWAY_URL/httpbin"

# Workload Identity configuration with real values
workloadIdentity:
  enabled: true
  clientId: "$WORKLOAD_IDENTITY"

# Client configuration for ConfigMap/Secret
client:
  config:
    AZURE_CLIENT_ID: "$CLIENT_APP_ID"
    AZURE_TENANT_ID: "$TENANT_ID"
    API_APP_ID: "$API_APP_ID"
    OAUTH_SCOPE: "api://$API_APP_ID/access_as_user"
  secrets:
    AZURE_CLIENT_SECRET: "$CLIENT_SECRET"
EOF
fi

# Build Helm values arguments in the correct order
HELM_VALUES_ARGS="--values ./helm/values.yaml"

# Add environment-specific values
if [ "$CLOUD" == "true" ] || [ "$CLOUD" == "1" ]; then
    HELM_VALUES_ARGS="$HELM_VALUES_ARGS --values ./helm/values-aks.yaml"
else
    HELM_VALUES_ARGS="$HELM_VALUES_ARGS --values ./helm/values-local.yaml"
fi

# Add override values (this should be LAST to override everything else)
if [ "$CLIENT_APP_ID" != "" ] && [ "$API_APP_ID" != "" ]; then
    HELM_VALUES_ARGS="$HELM_VALUES_ARGS --values app-config-override.yaml"
fi

# Add overrides.yaml if it exists
if [ -f overrides.yaml ]; then
    HELM_VALUES_ARGS="$HELM_VALUES_ARGS --values overrides.yaml"
fi

# deploy to kubernetes
if ! helm upgrade --install $DEPLOYMENT_NAME ./helm \
    $HELM_VALUES_ARGS \
    --namespace $NAMESPACE \
    --create-namespace \
    --timeout=15m \
    --debug; then
    echo ""
    echo "❌ Helm deployment failed. Gathering debug information..."
    echo ""
    echo "=== Pod Status ==="
    kubectl get pods -n $NAMESPACE -o wide
    echo ""
    echo "=== Pod Logs (if any pods exist) ==="
    for pod in $(kubectl get pods -n $NAMESPACE -o name 2>/dev/null); do
        echo "--- Logs for $pod ---"
        kubectl logs $pod -n $NAMESPACE --tail=50 || echo "No logs available"
    done
    echo ""
    echo "=== Events ==="
    kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -20
    echo ""
    echo "=== Secret Status ==="
    kubectl get secrets -n $NAMESPACE
    echo ""
    echo "=== ConfigMap Status ==="
    kubectl get configmaps -n $NAMESPACE
    echo ""
    exit 1
fi

echo ""
echo "🎉 Deployment completed successfully!"
echo ""

# Get ingress URL and update app registration redirect URIs
if [ "$CLIENT_APP_ID" != "" ]; then
    echo "🌐 Configuring ingress and updating app registration..."
    # The ingress name follows Helm's fullname pattern: <release-name>-<chart-name>
    INGRESS_NAME="$DEPLOYMENT_NAME-oauth-obo-client"
    INGRESS_URL=$(get_ingress_url "$INGRESS_NAME" "$NAMESPACE" "$CLOUD")
    if [ $? -eq 0 ] && [ "$INGRESS_URL" != "" ]; then
        echo "✓ Ingress URL: $INGRESS_URL"
        
        # Update app registration redirect URIs
        update_app_registration_redirects "$CLIENT_APP_ID" "$INGRESS_URL"
        
        echo ""
        echo "🔗 Application Access:"
        echo "   URL: $INGRESS_URL"
    else
        echo "⚠ Warning: Could not determine ingress URL"
        echo "  You may need to manually configure redirect URIs"
    fi
    echo ""
fi

if [ "$CLIENT_APP_ID" != "" ] && [ "$API_APP_ID" != "" ]; then
    echo "📋 App Registration Details:"
    echo "   Client App ID: $CLIENT_APP_ID"
    echo "   API App ID: $API_APP_ID"
    echo "   Tenant ID: $TENANT_ID"
    echo "   API Scope: api://$API_APP_ID/access_as_user"
    echo ""
    echo "🔐 Client Secret (for development only): $CLIENT_SECRET"
    echo ""
    echo "💾 Configuration saved to: app-config-override.yaml"
    echo ""
fi

duration=$SECONDS
echo "⏱️  Total deployment time: $(($duration / 60))m $(($duration % 60))s"
echo "End time: $(date)"

# Cleanup temporary files
if [ -f app-config-override.yaml ]; then
    echo ""
    echo "🧹 Cleaning up temporary configuration files..."
    rm -f app-config-override.yaml
fi