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
 echo "Syntax: $0 -n <name> -l <location> -s <unique suffix> -c <true|false|0|1> -b <true|false|0|1>"
 exit 1;
elif [[ $DEPLOYMENT_SUFFIX =~ [^a-zA-Z0-9] ]]; then
 echo "Unique suffix must contain ONLY letters and numbers. No special characters."
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

if [ "$BUILD" == "true" ] || [ "$BUILD" == "1" ]; then
    echo "Building container images..."
    COMMIT_HASH=$(git rev-parse HEAD)
    SHORT_HASH=${COMMIT_HASH::8}

    if [ "$REGISTRY_NAME" == "" ]; then
        docker build -t poc/client:latest \
                    -t poc/client:$SHORT_HASH \
                    -f ./src/client/Dockerfile .
    else 
        docker build -t $REGISTRY_NAME.azurecr.io/poc/client:latest \
                    -t $REGISTRY_NAME.azurecr.io/poc/client:$SHORT_HASH \
                    -f ./src/client/Dockerfile .

        echo "Logging in to container registry..."
        az acr login --name $REGISTRY_NAME --resource-group $REGISTRY_RESOURCE_GROUP --subscription $REGISTRY_SUBSCRIPTION
        echo "Pushing images..."
        docker push $REGISTRY_NAME.azurecr.io/poc/client:latest
        docker push $REGISTRY_NAME.azurecr.io/poc/client:$SHORT_HASH
    fi
fi

if [ "$CLOUD" == "true" ] || [ "$CLOUD" == "1" ]; then
    # provision infrastructure
    az deployment sub create \
        --name $DEPLOYMENT_NAME \
        --location $DEPLOYMENT_LOCATION \
        --template-file ./iac/main.bicep \
        --parameters ./iac/main.bicepparam \
        --parameters name=$DEPLOYMENT_NAME \
        --parameters location=$DEPLOYMENT_LOCATION \
        --parameters suffix=$DEPLOYMENT_SUFFIX 

    # connect kubectl to the AKS cluster
    RESOURCE_GROUP=$(az deployment sub show --name $DEPLOYMENT_NAME --query properties.outputs.resourceGroupName.value -o tsv)
    CLUSTER_NAME=$(az deployment sub show --name $DEPLOYMENT_NAME --query properties.outputs.aksName.value -o tsv)
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

# deploy to kubernetes
if ! helm upgrade --install $DEPLOYMENT_NAME ./helm \
    --values ./helm/values.yaml \
    --values overrides.yaml \
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