# App Registration Deployment Script Summary

## Overview

The `deploy-appregistrations.sh` script has been generated to automate the creation of Azure AD app registrations required for the OAuth On-Behalf-Of (OBO) flow proof of concept. This script is executed by the Azure Deployment Script resource in the Bicep template.

## What the Script Creates

### 1. API App Registration (`{name}-api`)
- **Purpose**: Backend API that receives OBO tokens
- **Identifier URI**: `api://{api-app-id}`
- **Exposed Scope**: `access_as_user`
- **Token Version**: v2.0
- **Group Claims**: Enabled for access tokens
- **Service Principal**: Created automatically

### 2. Client App Registration (`{name}-client`)
- **Purpose**: Client application running in AKS/Kubernetes
- **Type**: Public client with confidential client capabilities
- **Redirect URIs**: 
  - Local development: `http://localhost:8080/auth/callback`
  - AKS deployment: `http://{publicFqdn}/auth/callback`
  - Device code flow: `urn:ietf:wg:oauth:2.0:oob`
- **Permissions**: 
  - API permission to backend API (`access_as_user` scope)
  - Microsoft Graph `User.Read`
- **Client Secret**: Generated for development use (1-year expiration)
- **Group Claims**: Enabled for access and ID tokens

### 3. Security Groups
- **Admin Group**: `{name}-admin-users`
- **Standard Group**: `{name}-standard-users`
- Current user automatically added to admin group

### 4. Permissions Configuration
- Admin consent granted automatically
- OAuth2 permission scopes properly configured
- Required resource access set up for OBO flow

## Script Outputs

The script generates a JSON output that includes:

```json
{
  "appId": "client-app-id",
  "objectId": "client-object-id", 
  "apiAppId": "api-app-id",
  "apiObjectId": "api-object-id",
  "adminGroupId": "admin-group-object-id",
  "standardGroupId": "standard-group-object-id",
  "clientSecret": "generated-client-secret",
  "scope": "api://{api-app-id}/access_as_user"
}
```

These values are consumed by:
- Bicep template outputs
- APIM policy configurations (via named values)
- Kubernetes application configuration
- Development environment setup

## Integration with Infrastructure

### Bicep Template Integration
The script is embedded in the `application.bicep` module using:
```bicep
resource deploymentScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  properties: {
    scriptContent: loadTextContent('deploy-appregistrations.sh')
    environmentVariables: [
      { name: 'APP_NAME', value: name }
      { name: 'PUBLIC_FQDN', value: publicFqdn }
    ]
  }
}
```

### APIM Policy Integration
The generated group IDs are used in APIM policies for role-based header injection:
```xml
<when condition="@(context.User.Groups.Any(g => g == '{{admin-group-id}}'))">
    <set-header name="X-API-Key" exists-action="override">
        <value>ADMIN</value>
    </set-header>
</when>
```

### Application Configuration
The client app uses different authentication methods based on environment:
- **Development**: Client ID + Client Secret
- **Production (AKS)**: Azure Workload Identity (federated credentials)

## Security Features

1. **No Hardcoded Secrets**: All sensitive values are generated dynamically
2. **Time-Limited Secrets**: Client secret expires in 1 year
3. **Principle of Least Privilege**: Groups and permissions are scoped to POC requirements
4. **Environment Separation**: Different auth methods for dev vs production
5. **Group-Based Access Control**: Role mapping via Azure AD groups

## Error Handling

The script includes:
- Exit on error (`set -e`)
- Graceful handling of admin consent failures
- Warning messages for manual steps required
- Cleanup of temporary files
- Detailed logging of all operations

## Dependencies

- Azure CLI 2.47.0+
- `jq` for JSON processing
- `python3` for UUID generation
- Sufficient Azure AD permissions:
  - Application.ReadWrite.All
  - Group.ReadWrite.All
  - Application.ReadWrite.OwnedBy (minimum)

## Post-Deployment Steps

After the script runs successfully:

1. **Verify Groups**: Check that security groups were created in Azure AD
2. **Assign Users**: Add test users to the appropriate groups
3. **Review Consent**: Confirm admin consent was granted in Azure portal
4. **Update Configuration**: Use the output values to configure other components
5. **Test Authentication**: Verify the OBO flow works end-to-end

## Troubleshooting

Common issues and solutions:

1. **Permission Denied**: Ensure the executing identity has Azure AD admin permissions
2. **Admin Consent Failed**: Grant consent manually in Azure portal
3. **Group Creation Failed**: Check for naming conflicts with existing groups
4. **UUID Generation**: Script uses Python3 instead of `uuidgen` for broader compatibility

## Environment Variables Used

- `APP_NAME`: Base name for app registrations and groups
- `PUBLIC_FQDN`: Public FQDN of the AKS cluster for redirect URIs
- `AZ_SCRIPTS_OUTPUT_PATH`: Azure Deployment Scripts output path (set automatically)

The script is designed to be idempotent where possible, but re-running will create duplicate resources unless the existing ones are cleaned up first.