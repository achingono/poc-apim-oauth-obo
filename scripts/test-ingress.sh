#!/bin/bash

# Test script for ingress deployment
# Usage: ./scripts/test-ingress.sh <deployment-name> <namespace> [cloud]

DEPLOYMENT_NAME="$1"
NAMESPACE="${2:-default}"
CLOUD="${3:-false}"

if [ "$DEPLOYMENT_NAME" == "" ]; then
    echo "Usage: $0 <deployment-name> <namespace> [cloud]"
    echo "  deployment-name: Name of the Helm deployment"
    echo "  namespace: Kubernetes namespace (default: default)"
    echo "  cloud: true for AKS, false for minikube (default: false)"
    exit 1
fi

echo "Testing ingress deployment: $DEPLOYMENT_NAME in namespace: $NAMESPACE"
echo "Cloud deployment: $CLOUD"
echo ""

# Check if deployment exists
echo "Checking Helm deployment..."
if ! helm status "$DEPLOYMENT_NAME" -n "$NAMESPACE" > /dev/null 2>&1; then
    echo "❌ Helm deployment '$DEPLOYMENT_NAME' not found in namespace '$NAMESPACE'"
    exit 1
fi
echo "✓ Helm deployment found"

# Check pods
echo ""
echo "Checking pod status..."
POD_STATUS=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/instance="$DEPLOYMENT_NAME" -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
if [ "$POD_STATUS" != "Running" ]; then
    echo "❌ Pod is not running (status: $POD_STATUS)"
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/instance="$DEPLOYMENT_NAME"
    exit 1
fi
echo "✓ Pod is running"

# Check service
echo ""
echo "Checking service..."
if ! kubectl get service "$DEPLOYMENT_NAME" -n "$NAMESPACE" > /dev/null 2>&1; then
    echo "❌ Service '$DEPLOYMENT_NAME' not found"
    exit 1
fi
echo "✓ Service found"

# Check ingress
echo ""
echo "Checking ingress..."
if ! kubectl get ingress "$DEPLOYMENT_NAME" -n "$NAMESPACE" > /dev/null 2>&1; then
    echo "❌ Ingress '$DEPLOYMENT_NAME' not found"
    exit 1
fi

# Get ingress details
INGRESS_CLASS=$(kubectl get ingress "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.ingressClassName}')
INGRESS_HOST=$(kubectl get ingress "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.rules[0].host}')

echo "✓ Ingress found"
echo "  Class: $INGRESS_CLASS"
echo "  Host: $INGRESS_HOST"

# Check ingress IP/endpoint
echo ""
echo "Checking ingress endpoint..."
if [ "$CLOUD" == "true" ]; then
    # AKS - check for external IP
    EXTERNAL_IP=$(kubectl get ingress "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    if [ "$EXTERNAL_IP" == "" ] || [ "$EXTERNAL_IP" == "<none>" ]; then
        echo "⚠ Warning: No external IP assigned yet"
        echo "  This may take a few minutes for AKS to assign an IP"
    else
        echo "✓ External IP: $EXTERNAL_IP"
        INGRESS_URL="https://$EXTERNAL_IP"
    fi
else
    # Minikube - check minikube IP and /etc/hosts
    MINIKUBE_IP=$(minikube ip 2>/dev/null)
    if [ "$MINIKUBE_IP" == "" ]; then
        echo "❌ Could not get minikube IP"
        exit 1
    fi
    echo "✓ Minikube IP: $MINIKUBE_IP"
    
    # Check /etc/hosts entry
    if grep -q "$MINIKUBE_IP.*$INGRESS_HOST" /etc/hosts; then
        echo "✓ /etc/hosts entry found"
        INGRESS_URL="http://$INGRESS_HOST"
    else
        echo "⚠ Warning: Missing /etc/hosts entry"
        echo "  Add this line to /etc/hosts:"
        echo "  $MINIKUBE_IP $INGRESS_HOST"
        INGRESS_URL="http://$INGRESS_HOST"
    fi
fi

# Test connectivity
if [ "$INGRESS_URL" != "" ]; then
    echo ""
    echo "Testing connectivity to: $INGRESS_URL"
    if curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$INGRESS_URL" | grep -q "200\|302\|401"; then
        echo "✓ Application is responding"
    else
        echo "⚠ Warning: Application may not be responding correctly"
        echo "  This could be normal if authentication is required"
    fi
fi

echo ""
echo "🎉 Ingress test completed!"
if [ "$INGRESS_URL" != "" ]; then
    echo "Access your application at: $INGRESS_URL"
fi