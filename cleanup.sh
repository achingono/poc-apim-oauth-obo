#!/bin/bash

# Cleanup script for OAuth OBO POC deployment
# This script removes Azure resources and app registrations created by deploy.sh

# Source .env if available
if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

while getopts n:s:a flag
do
    case "${flag}" in
        n) DEPLOYMENT_NAME=${OPTARG};;
        s) DEPLOYMENT_SUFFIX=${OPTARG};;
        a) CLEANUP_APPS=true;;
    esac
done

if [ "$DEPLOYMENT_NAME" == "" ] || [ "$DEPLOYMENT_SUFFIX" == "" ]; then
 echo "Syntax: $0 -n <name> -s <suffix> [-a]"
 echo "  -a: Also cleanup Azure AD app registrations"
 exit 1;
fi

echo "🧹 Starting cleanup for deployment: $DEPLOYMENT_NAME-$DEPLOYMENT_SUFFIX"
echo ""

# Cleanup Azure resources
echo "🗑️  Cleaning up Azure resources..."
RESOURCE_GROUP="rg-${DEPLOYMENT_NAME:0:10}-${DEPLOYMENT_SUFFIX:0:24}-eastus"

if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
    echo "   Deleting resource group: $RESOURCE_GROUP"
    az group delete --name "$RESOURCE_GROUP" --yes --no-wait
    echo "   ✅ Resource group deletion initiated (running in background)"
else
    echo "   ℹ️  Resource group $RESOURCE_GROUP does not exist or already deleted"
fi

# Cleanup app registrations if requested
if [ "$CLEANUP_APPS" == "true" ]; then
    echo ""
    echo "🗑️  Cleaning up Azure AD app registrations..."
    
    API_APP_NAME="$DEPLOYMENT_NAME-$DEPLOYMENT_SUFFIX-api"
    CLIENT_APP_NAME="$DEPLOYMENT_NAME-$DEPLOYMENT_SUFFIX-client"
    
    # Find and delete API app
    API_APP_ID=$(az ad app list --display-name "$API_APP_NAME" --query "[0].appId" -o tsv 2>/dev/null)
    if [ "$API_APP_ID" != "" ] && [ "$API_APP_ID" != "null" ]; then
        echo "   Deleting API app registration: $API_APP_NAME ($API_APP_ID)"
        az ad app delete --id "$API_APP_ID"
        echo "   ✅ API app registration deleted"
    else
        echo "   ℹ️  API app registration $API_APP_NAME not found"
    fi
    
    # Find and delete Client app
    CLIENT_APP_ID=$(az ad app list --display-name "$CLIENT_APP_NAME" --query "[0].appId" -o tsv 2>/dev/null)
    if [ "$CLIENT_APP_ID" != "" ] && [ "$CLIENT_APP_ID" != "null" ]; then
        echo "   Deleting client app registration: $CLIENT_APP_NAME ($CLIENT_APP_ID)"
        az ad app delete --id "$CLIENT_APP_ID"
        echo "   ✅ Client app registration deleted"
    else
        echo "   ℹ️  Client app registration $CLIENT_APP_NAME not found"
    fi
fi

# Cleanup local Docker images if they exist
echo ""
echo "🗑️  Cleaning up local Docker images..."
if docker images --format "table {{.Repository}}" | grep -q "poc/client"; then
    echo "   Removing poc/client Docker images..."
    docker rmi $(docker images "poc/client" -q) 2>/dev/null || true
    echo "   ✅ Local Docker images cleaned up"
else
    echo "   ℹ️  No poc/client Docker images found"
fi

# Cleanup minikube if running
echo ""
echo "🗑️  Checking minikube status..."
if minikube status &>/dev/null; then
    echo "   Minikube is running. You may want to clean it up manually with:"
    echo "   minikube delete"
else
    echo "   ℹ️  Minikube is not running"
fi

# Cleanup temporary files
echo ""
echo "🗑️  Cleaning up temporary files..."
rm -f app-config-override.yaml
rm -f main.json  # Compiled Bicep output
echo "   ✅ Temporary files cleaned up"

echo ""
echo "🎉 Cleanup completed!"
echo ""
echo "ℹ️  Note: Azure resource group deletion is running in the background."
echo "   You can check the progress in the Azure portal or with:"
echo "   az group show --name '$RESOURCE_GROUP'"