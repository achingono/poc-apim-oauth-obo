# Azure AD App Registration Module

This module creates the necessary Azure AD app registrations for the OAuth On-Behalf-Of (OBO) flow proof of concept.

## What it creates

### 1. API App Registration (Backend API)
- **Purpose**: Represents the backend API that will receive tokens
- **Name**: `{name}-api` (e.g., `appregmypoc-api`)
- **Identifier URI**: `api://{api-app-id}`
- **Exposed Scope**: `access_as_user` - Allows applications to access the API on behalf of users
- **Claims**: Configured to include group membership claims in access tokens
- **Audience**: Single tenant (AzureADMyOrg)

### 2. Client App Registration (Frontend Client)
- **Purpose**: Represents the client application running in AKS
- **Name**: `{name}-client` (e.g., `appregmypoc-client`)
- **Type**: Public client with fallback support
- **Redirect URIs**: 
  - `http://localhost:8080/auth/callback` (for local development)
  - `http://{publicFqdn}/auth/callback` (for AKS deployment)
  - `urn:ietf:wg:oauth:2.0:oob` (for device code flow)
- **Permissions**: 
  - API permission to access the backend API with `access_as_user` scope
  - Microsoft Graph `User.Read` permission
- **Claims**: Configured to include group membership claims
- **Client Secret**: Generated for development environment use

### 3. Security Groups
- **Admin Group**: `{name}-admin-users` - Users with administrative privileges
- **Standard Group**: `{name}-standard-users` - Users with standard privileges
- **Assignment**: Current deploying user is automatically added to the admin group

### 4. Permissions and Consent
- Admin consent is automatically granted for the client app's API permissions
- The API app exposes the required scope for OBO flows
- Group claims are configured for both access and ID tokens

## Outputs

The module outputs the following values for use by other components:

```bicep
// Client App
output appId string              // Client application ID
output objectId string           // Client application object ID  
output clientSecret string       // Client secret for development

// API App
output apiAppId string           // API application ID
output apiObjectId string        // API application object ID

// Security Groups
output adminGroupId string       // Admin group object ID
output standardGroupId string    // Standard group object ID

// OAuth Configuration
output scope string              // Full scope URI (api://{api-app-id}/access_as_user)
```

## Usage in APIM Policies

The created groups and app IDs are used in APIM policies for:

1. **JWT Validation**: Validates tokens issued for the API app (`apiAppId`)
2. **Group-based Authorization**: Maps user group membership to different API keys/roles
3. **Header Injection**: Adds `X-API-Key` and `X-User-Role` headers based on group membership

Example policy snippet:
```xml
<validate-jwt header-name="Authorization">
    <required-claims>
        <claim name="aud">
            <value>api://{{api-app-id}}</value>
        </claim>
    </required-claims>
</validate-jwt>
<choose>
    <when condition="@(context.User.Groups.Any(g => g == '{{admin-group-id}}'))">
        <set-header name="X-API-Key" exists-action="override">
            <value>ADMIN</value>
        </set-header>
    </when>
    <otherwise>
        <set-header name="X-API-Key" exists-action="override">
            <value>STANDARD</value>
        </set-header>
    </otherwise>
</choose>
```

## Manual Steps Required After Deployment

1. **Assign Users to Groups**: Add test users to the created security groups in the Azure portal
2. **Review Permissions**: Verify that admin consent was granted successfully
3. **Environment Variables**: Update your deployment with the generated IDs:
   - `API_APP_ID`: Use the `apiAppId` output
   - `CLIENT_APP_ID`: Use the `appId` output  
   - `ADMIN_GROUP_ID`: Use the `adminGroupId` output

## Development vs Production

- **Development**: Uses client ID + client secret authentication
- **Production (AKS)**: Uses Azure Workload Identity (federated credentials)
- The client secret should only be used in development environments
- In production, the workload identity federation replaces the need for client secrets

## Security Considerations

- Client secrets are generated with 1-year expiration
- Group membership claims are included in tokens (watch for token size limits)
- Admin consent is granted automatically (requires appropriate permissions)
- The current user is automatically added to the admin group for testing

## Dependencies

The deployment script requires:
- Azure CLI (`az`) version 2.47.0 or later
- `jq` for JSON processing
- `python3` for UUID generation
- Sufficient Azure AD permissions to create app registrations and groups