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
        --parameters apiAppId=$API_APP_ID \
        --parameters registry=null \
        --parameters vault=null

    # connect kubectl to the AKS cluster
    RESOURCE_GROUP=$(az deployment sub show --name $DEPLOYMENT_NAME --query properties.outputs.resourceGroupName.value -o tsv)
    CLUSTER_NAME=$(az deployment sub show --name $DEPLOYMENT_NAME --query properties.outputs.aksName.value -o tsv)
    az aks get-credentials --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --overwrite-existing
}