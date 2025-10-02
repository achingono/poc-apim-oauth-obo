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

# Validate app registrations
if [ "$CLIENT_APP_ID" != "" ] && [ "$API_APP_ID" != "" ]; then
    echo "🔍 Validating Azure AD app registrations..."
    
    # Check if API app has OAuth scope configured
    SCOPE_CHECK=$(az ad app show --id "$API_APP_ID" --query "api.oauth2PermissionScopes[?value=='access_as_user'].id" --output tsv 2>/dev/null)
    if [ "$SCOPE_CHECK" != "" ]; then
        echo "✓ API app has 'access_as_user' OAuth scope configured"
    else
        echo "⚠ Warning: API app may be missing OAuth scope. This could cause authentication issues."
    fi
    
    # Check if client app has permissions to API app
    PERMISSION_CHECK=$(az ad app permission list --id "$CLIENT_APP_ID" --query "[?resourceAppId=='$API_APP_ID'].resourceAccess[0].id" --output tsv 2>/dev/null)
    if [ "$PERMISSION_CHECK" != "" ]; then
        echo "✓ Client app has permissions to API app"
    else
        echo "⚠ Warning: Client app may be missing permissions to API app"
    fi
else
    echo "⚠ Warning: App registration IDs not available for validation"
fi

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
  scope: "access_as_user"

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
    OAUTH_SCOPE: "access_as_user"
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

# Validate deployment
echo "🔍 Validating deployment..."
echo "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=oauth-obo-client -n $NAMESPACE --timeout=300s

if [ $? -eq 0 ]; then
    echo "✓ Pods are ready"
    
    # Check if ConfigMap has all required environment variables
    echo "Checking ConfigMap configuration..."
    CLIENT_ID_CHECK=$(kubectl get configmap -n $NAMESPACE -o jsonpath='{.data.AZURE_CLIENT_ID}' 2>/dev/null)
    TENANT_ID_CHECK=$(kubectl get configmap -n $NAMESPACE -o jsonpath='{.data.AZURE_TENANT_ID}' 2>/dev/null)
    API_APP_ID_CHECK=$(kubectl get configmap -n $NAMESPACE -o jsonpath='{.data.API_APP_ID}' 2>/dev/null)
    OAUTH_SCOPE_CHECK=$(kubectl get configmap -n $NAMESPACE -o jsonpath='{.data.OAUTH_SCOPE}' 2>/dev/null)
    
    if [ "$CLIENT_ID_CHECK" != "" ] && [ "$TENANT_ID_CHECK" != "" ] && [ "$API_APP_ID_CHECK" != "" ] && [ "$OAUTH_SCOPE_CHECK" == "access_as_user" ]; then
        echo "✓ ConfigMap has all required environment variables"
    else
        echo "⚠ Warning: ConfigMap may be missing required environment variables"
        echo "  AZURE_CLIENT_ID: $CLIENT_ID_CHECK"
        echo "  AZURE_TENANT_ID: $TENANT_ID_CHECK"
        echo "  API_APP_ID: $API_APP_ID_CHECK"
        echo "  OAUTH_SCOPE: $OAUTH_SCOPE_CHECK"
    fi
    
    # Check pod logs for any startup errors
    echo "Checking pod logs for startup errors..."
    POD_NAME=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=oauth-obo-client -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ "$POD_NAME" != "" ]; then
        kubectl logs $POD_NAME -n $NAMESPACE --tail=10 | grep -i "error\|exception\|fail" && echo "⚠ Warning: Found potential errors in pod logs" || echo "✓ No obvious errors in pod logs"
    fi
else
    echo "❌ Pods failed to become ready within timeout"
    kubectl get pods -n $NAMESPACE -o wide
    exit 1
fi

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
        
        # Validate the redirect URI was added successfully
        echo "Validating redirect URI configuration..."
        REDIRECT_CHECK=$(az ad app show --id "$CLIENT_APP_ID" --query "web.redirectUris[?contains(@, '$INGRESS_URL')]" --output tsv 2>/dev/null)
        if [ "$REDIRECT_CHECK" != "" ]; then
            echo "✓ Redirect URI successfully added to app registration"
        else
            echo "⚠ Warning: Failed to add redirect URI to app registration"
        fi
        
        echo ""
        echo "🔗 Application Access:"
        echo "   URL: $INGRESS_URL"
        echo "   Status: Ready for OAuth testing"
    else
        echo "⚠ Warning: Could not determine ingress URL"
        echo "  You may need to manually configure redirect URIs"
        echo "  Run this command to check ingress status:"
        echo "  kubectl get ingress $INGRESS_NAME -n $NAMESPACE"
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
    
    if [ "$INGRESS_URL" != "" ]; then
        echo "🧪 OAuth Testing Instructions:"
        echo "   1. Open browser to: $INGRESS_URL"
        echo "   2. You should be redirected to Azure AD login"
        echo "   3. After login, consent to the 'Access API as you' permission"
        echo "   4. You should be redirected back to the application"
        echo ""
        echo "🔧 Troubleshooting:"
        echo "   - If you get AADSTS errors, check the app registration configuration"
        echo "   - If pods are not ready, run: kubectl get pods -n $NAMESPACE"
        echo "   - To view logs: kubectl logs -l app.kubernetes.io/name=oauth-obo-client -n $NAMESPACE"
        echo ""
    fi
fi

duration=$SECONDS
echo "⏱️  Total deployment time: $(($duration / 60))m $(($duration % 60))s"
echo "End time: $(date)"

# Cleanup temporary files
if [ -f app-config-override.yaml ]; then
    echo ""
    echo "🧹 Cleaning up temporary configuration files..."
    # Only remove if deployment was successful and we have a running pod
    POD_COUNT=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=oauth-obo-client --no-headers 2>/dev/null | wc -l)
    if [ "$POD_COUNT" -gt 0 ]; then
        rm -f app-config-override.yaml
        echo "✓ Temporary files cleaned up"
    else
        echo "⚠ Keeping app-config-override.yaml for debugging (no running pods found)"
    fi
fi