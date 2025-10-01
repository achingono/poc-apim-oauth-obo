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
    echo "Deploying to Azure..."
    # provision infrastructure
    az deployment sub create \
        --name $DEPLOYMENT_NAME \
        --location $DEPLOYMENT_LOCATION \
        --template-file ./iac/main.bicep \
        --parameters ./iac/main.bicepparam \
        --parameters name=$DEPLOYMENT_NAME \
        --parameters location=$DEPLOYMENT_LOCATION \
        --parameters suffix=$DEPLOYMENT_SUFFIX \
        --parameters clientAppId=$CLIENT_APP_ID \
        --parameters apiAppId=$API_APP_ID

    # connect kubectl to the AKS cluster
    echo "Configuring kubectl to connect to AKS cluster..."
    RESOURCE_GROUP=$(az deployment sub show --name $DEPLOYMENT_NAME --query properties.outputs.resourceGroupName.value -o tsv)
    if [ "$RESOURCE_GROUP" == "" ]; then
        RESOURCE_GROUP="rg-${DEPLOYMENT_NAME:0:10}-${DEPLOYMENT_SUFFIX:0:24}-$DEPLOYMENT_LOCATION"
    fi
    CLUSTER_NAME=$(az deployment sub show --name $DEPLOYMENT_NAME --query properties.outputs.aksName.value -o tsv)
    if [ "$CLUSTER_NAME" == "" ]; then
        CLUSTER_NAME="aks-${DEPLOYMENT_NAME:0:10}-${DEPLOYMENT_SUFFIX:0:24}"
    fi
    echo "AKS Cluster: $CLUSTER_NAME in Resource Group: $RESOURCE_GROUP"
    az aks get-credentials --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --overwrite-existing
else
    # start minikube if not running
    if ! minikube status &> /dev/null; then
        echo "Starting minikube..."
        minikube start --driver=docker
    fi
fi

echo "Deploying to Kubernetes..."

if [ "$NAMESPACE" == "" ]; then
    NAMESPACE="default"
fi

# Create values override file with app registration details if they exist
if [ "$CLIENT_APP_ID" != "" ] && [ "$API_APP_ID" != "" ]; then
    echo "Creating Helm values override with app registration details..."
    cat > app-config-override.yaml <<EOF
client:
  config:
    AZURE_CLIENT_ID: "$CLIENT_APP_ID"
    AZURE_TENANT_ID: "$TENANT_ID"
    API_APP_ID: "$API_APP_ID"
    OAUTH_SCOPE: "api://$API_APP_ID/access_as_user"
  secrets:
    AZURE_CLIENT_SECRET: "$CLIENT_SECRET"
EOF
    HELM_VALUES_ARGS="--values ./helm/values.yaml --values app-config-override.yaml"
else
    HELM_VALUES_ARGS="--values ./helm/values.yaml"
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