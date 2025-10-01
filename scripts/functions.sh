# Function to create Azure AD app registrations
create_app_registrations() {
    echo "Creating Azure AD App Registrations..."
    
    # Get tenant ID
    TENANT_ID=$(az account show --query tenantId -o tsv)
    echo "Using tenant: $TENANT_ID"
    
    # Function to generate UUID using Python
    generate_uuid() {
        python3 -c "import uuid; print(str(uuid.uuid4()))"
    }
    
    # App names
    API_APP_NAME="$DEPLOYMENT_NAME-$DEPLOYMENT_SUFFIX-api"
    CLIENT_APP_NAME="$DEPLOYMENT_NAME-$DEPLOYMENT_SUFFIX-client"
    
    # Check if API app already exists
    echo "Checking for existing API app registration: $API_APP_NAME"
    API_APP_ID=$(az ad app list --display-name "$API_APP_NAME" --query "[0].appId" -o tsv)
    
    if [ "$API_APP_ID" != "" ] && [ "$API_APP_ID" != "null" ]; then
        echo "✅ Found existing API app registration: $API_APP_ID"
        
        # Get existing scope UUID to reuse it
        SCOPE_UUID=$(az ad app show --id "$API_APP_ID" --query "api.oauth2PermissionScopes[?value=='access_as_user'].id" -o tsv)
        if [ "$SCOPE_UUID" == "" ] || [ "$SCOPE_UUID" == "null" ]; then
            SCOPE_UUID=$(generate_uuid)
            echo "⚠️  No existing scope found, will create new one: $SCOPE_UUID"
        else
            echo "✅ Reusing existing scope: $SCOPE_UUID"
        fi
    else
        echo "Creating API app registration: $API_APP_NAME"
        
        # Generate UUIDs for scopes and roles
        SCOPE_UUID=$(generate_uuid)
        USER_ROLE_UUID=$(generate_uuid)
        ADMIN_ROLE_UUID=$(generate_uuid)
        
        # Create API app with basic configuration first
        API_APP_ID=$(az ad app create \
            --display-name "$API_APP_NAME" \
            --identifier-uris "api://$API_APP_NAME" \
            --query appId -o tsv)
        
        if [ "$API_APP_ID" == "" ]; then
            echo "❌ Failed to create API app registration"
            exit 1
        fi
        
        echo "✅ API app registration created: $API_APP_ID"
        
        # Update with OAuth2 permissions and roles
        echo "Configuring OAuth2 permissions and roles..."
        az ad app update --id "$API_APP_ID" \
            --set api.oauth2PermissionScopes='[{"id":"'$SCOPE_UUID'","adminConsentDescription":"Allow the application to access the API on behalf of the signed-in user","adminConsentDisplayName":"Access API as user","isEnabled":true,"type":"User","userConsentDescription":"Allow the application to access the API on your behalf","userConsentDisplayName":"Access API as you","value":"access_as_user"}]' \
            --set appRoles='[{"allowedMemberTypes":["User"],"description":"Standard user access","displayName":"User","id":"'$USER_ROLE_UUID'","isEnabled":true,"value":"User"},{"allowedMemberTypes":["User"],"description":"Administrator access","displayName":"Admin","id":"'$ADMIN_ROLE_UUID'","isEnabled":true,"value":"Admin"}]' \
            --set groupMembershipClaims="SecurityGroup" \
            --set acceptMappedClaims=true \
            --set accessTokenAcceptedVersion=2 > /dev/null
        
        if [ $? -ne 0 ]; then
            echo "⚠️  Warning: Failed to update some API app settings, but continuing..."
        fi
    fi
    
    # Ensure service principal exists for API app
    az ad sp show --id "$API_APP_ID" > /dev/null 2>&1 || az ad sp create --id "$API_APP_ID" > /dev/null 2>&1
    
    # Check if client app already exists
    echo "Checking for existing client app registration: $CLIENT_APP_NAME"
    CLIENT_APP_ID=$(az ad app list --display-name "$CLIENT_APP_NAME" --query "[0].appId" -o tsv)
    
    if [ "$CLIENT_APP_ID" != "" ] && [ "$CLIENT_APP_ID" != "null" ]; then
        echo "✅ Found existing client app registration: $CLIENT_APP_ID"
    else
        echo "Creating client app registration: $CLIENT_APP_NAME"
        
        # Create client app registration
        CLIENT_APP_ID=$(az ad app create \
            --display-name "$CLIENT_APP_NAME" \
            --public-client-redirect-uris "http://localhost" \
            --web-redirect-uris "https://localhost:5001/signin-oidc" \
            --enable-access-token-issuance \
            --enable-id-token-issuance \
            --query appId -o tsv)
        
        if [ "$CLIENT_APP_ID" == "" ]; then
            echo "❌ Failed to create client app registration"
            exit 1
        fi
        
        echo "✅ Client app registration created: $CLIENT_APP_ID"
    fi
    
    # Ensure service principal exists for client app
    az ad sp show --id "$CLIENT_APP_ID" > /dev/null 2>&1 || az ad sp create --id "$CLIENT_APP_ID" > /dev/null 2>&1
    
    # Add required API permissions to client app (check if already exists)
    echo "Configuring API permissions..."
    
    EXISTING_PERMISSION=$(az ad app permission list --id "$CLIENT_APP_ID" --query "[?resourceAppId=='$API_APP_ID']" -o tsv)
    if [ "$EXISTING_PERMISSION" == "" ]; then
        echo "Adding API permission to client app..."
        az ad app permission add \
            --id "$CLIENT_APP_ID" \
            --api "$API_APP_ID" \
            --api-permissions "$SCOPE_UUID=Scope" > /dev/null 2>&1
        
        # Wait a moment for the permission to be registered
        sleep 5
        
        # Grant admin consent
        echo "Granting admin consent for API permissions..."
        az ad app permission admin-consent --id "$CLIENT_APP_ID" > /dev/null 2>&1 || echo "⚠️  Admin consent may need to be granted manually"
    else
        echo "✅ API permissions already configured"
    fi
    
    # Create or rotate client secret for development use
    echo "Creating client secret..."
    CLIENT_SECRET=$(az ad app credential reset --id "$CLIENT_APP_ID" --display-name "Development Secret" --query password -o tsv)
    
    # Export environment variables for Bicep
    export API_APP_ID="$API_APP_ID"
    export CLIENT_APP_ID="$CLIENT_APP_ID" 
    export CLIENT_SECRET="$CLIENT_SECRET"
    export TENANT_ID="$TENANT_ID"
    export SCOPE_UUID="$SCOPE_UUID"
    
    echo "✅ App registrations configured successfully"
    echo "   API App ID: $API_APP_ID"
    echo "   Client App ID: $CLIENT_APP_ID"
    echo "   Tenant ID: $TENANT_ID"
    echo "   OAuth Scope: api://$API_APP_ID/access_as_user"
}

build_and_push_images() {
    echo "Building container images..."
    COMMIT_HASH=$(git rev-parse HEAD)
    SHORT_HASH=${COMMIT_HASH::8}

    if [ "$REGISTRY_NAME" == "" ]; then
        echo "Building images locally (no registry specified)..."
        docker build -t poc/client:latest \
                    -t poc/client:$SHORT_HASH \
                    -f ./src/client/Dockerfile ./src/client
        echo "✅ Local container images built successfully"
    else 
        # Check if required registry environment variables are set
        if [ "$REGISTRY_RESOURCE_GROUP" == "" ] || [ "$REGISTRY_SUBSCRIPTION" == "" ]; then
            echo "❌ Registry environment variables not set. Required when REGISTRY_NAME is specified: REGISTRY_RESOURCE_GROUP, REGISTRY_SUBSCRIPTION"
            echo "Current values:"
            echo "  REGISTRY_NAME: $REGISTRY_NAME"
            echo "  REGISTRY_RESOURCE_GROUP: $REGISTRY_RESOURCE_GROUP"
            echo "  REGISTRY_SUBSCRIPTION: $REGISTRY_SUBSCRIPTION"
            exit 1
        fi
        
        echo "Building images for Azure Container Registry: $REGISTRY_NAME"
        docker build -t $REGISTRY_NAME.azurecr.io/poc/client:latest \
                    -t $REGISTRY_NAME.azurecr.io/poc/client:$SHORT_HASH \
                    -f ./src/client/Dockerfile ./src/client

        echo "Logging in to container registry..."
        az acr login --name $REGISTRY_NAME --resource-group $REGISTRY_RESOURCE_GROUP --subscription $REGISTRY_SUBSCRIPTION
        echo "Pushing images..."
        docker push $REGISTRY_NAME.azurecr.io/poc/client:latest
        docker push $REGISTRY_NAME.azurecr.io/poc/client:$SHORT_HASH
        echo "✅ Container images pushed to registry successfully"
    fi
}    

provision_infrastructure() {
    echo "Deploying to Azure..."
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
}

# Function to enable minikube ingress
enable_minikube_ingress() {
    echo "Attempting to enable minikube ingress addon..."
    if timeout 30s minikube addons enable ingress; then
        echo "✓ Ingress addon enabled successfully"
        
        # Configure NGINX controller for proper forwarded headers handling
        echo "Configuring NGINX controller for forwarded headers..."
        kubectl patch configmap ingress-nginx-controller -n ingress-nginx --patch='{"data":{"use-forwarded-headers":"true","compute-full-forwarded-for":"true","hsts":"false"}}' || echo "⚠ Warning: Could not configure NGINX forwarded headers"
        
        # Restart NGINX controller to apply configuration
        echo "Restarting NGINX controller to apply configuration..."
        kubectl rollout restart deployment/ingress-nginx-controller -n ingress-nginx || echo "⚠ Warning: Could not restart NGINX controller"
        kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=60s || echo "⚠ Warning: NGINX controller restart timed out"
        
        return 0
    else
        echo "⚠ Warning: Failed to enable ingress addon (likely due to network connectivity)"
        echo "  Continuing with NodePort services only..."
        return 1
    fi
}

# Function to enable AKS ingress (Web Application Routing addon)
enable_aks_ingress() {
    local resource_group="$1"
    local cluster_name="$2"
    
    echo "Enabling AKS Web Application Routing addon..."
    if az aks approuting enable \
        --resource-group "$resource_group" \
        --name "$cluster_name" > /dev/null 2>&1; then
        echo "✓ Web Application Routing addon enabled successfully"
        
        # Wait for the ingress controller to be ready
        echo "Waiting for ingress controller to be ready..."
        kubectl wait --for=condition=available deployment/nginx -n app-routing-system --timeout=300s || echo "⚠ Warning: Ingress controller readiness check timed out"
        
        return 0
    else
        echo "⚠ Warning: Failed to enable Web Application Routing addon"
        echo "  You may need to enable it manually or use a different ingress controller"
        return 1
    fi
}

# Function to get ingress URL
get_ingress_url() {
    local deployment_name="$1"
    local namespace="$2"
    local is_cloud="$3"
    
    if [ "$is_cloud" == "true" ] || [ "$is_cloud" == "1" ]; then
        # For AKS, get the external IP from the ingress
        echo "Waiting for AKS ingress to get external IP..." >&2
        local external_ip=""
        local attempts=0
        while [ "$external_ip" == "" ] || [ "$external_ip" == "<pending>" ] && [ $attempts -lt 30 ]; do
            external_ip=$(kubectl get ingress "$deployment_name" -n "$namespace" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
            if [ "$external_ip" == "" ] || [ "$external_ip" == "<pending>" ]; then
                sleep 10
                attempts=$((attempts + 1))
                echo "  Attempt $attempts/30: Waiting for external IP..." >&2
            fi
        done
        
        if [ "$external_ip" != "" ] && [ "$external_ip" != "<pending>" ]; then
            echo "https://$external_ip"
        else
            echo "Warning: Could not obtain external IP for AKS ingress" >&2
            return 1
        fi
    else
        # For minikube, use minikube ip with /etc/hosts entry
        local minikube_ip=$(minikube ip 2>/dev/null)
        if [ "$minikube_ip" != "" ]; then
            local host_name="local.oauth-obo.dev"
            echo "http://$host_name"
            echo "" >&2
            echo "Add this entry to your /etc/hosts file:" >&2
            echo "   $minikube_ip $host_name" >&2
        else
            echo "Warning: Could not get minikube IP" >&2
            return 1
        fi
    fi
}

# Function to update app registration redirect URIs
update_app_registration_redirects() {
    local client_app_id="$1"
    local redirect_url="$2"
    
    echo "Updating app registration redirect URIs..."
    
    # Add the new redirect URL to web redirects (for OIDC flows)
    local signin_redirect="$redirect_url/signin-oidc"
    local signout_redirect="$redirect_url/signout-callback-oidc"
    
    # Get current redirect URIs and add new ones
    local current_redirects=$(az ad app show --id "$client_app_id" --query "web.redirectUris" -o tsv 2>/dev/null | tr '\t' '\n')
    
    # Check if redirects already exist
    if echo "$current_redirects" | grep -q "^$signin_redirect$" && echo "$current_redirects" | grep -q "^$signout_redirect$"; then
        echo "✓ Redirect URIs already configured"
        return 0
    fi
    
    # Add new redirect URIs (this will replace existing ones, so we need to include them)
    local all_redirects="$signin_redirect $signout_redirect"
    if [ "$current_redirects" != "" ]; then
        all_redirects="$all_redirects $current_redirects"
    fi
    
    # Update the app registration
    if az ad app update --id "$client_app_id" \
        --web-redirect-uris $all_redirects > /dev/null 2>&1; then
        echo "✓ App registration redirect URIs updated successfully"
        echo "  Added: $signin_redirect"
        echo "  Added: $signout_redirect"
        return 0
    else
        echo "⚠ Warning: Failed to update app registration redirect URIs"
        echo "  Please manually add these URLs to your app registration:"
        echo "    $signin_redirect"
        echo "    $signout_redirect"
        return 1
    fi
}
