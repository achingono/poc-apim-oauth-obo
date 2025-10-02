# Azure API Management Architecture

This document details the Azure API Management (APIM) configuration and its role in the OAuth 2.0 On-Behalf-Of flow.

## Table of Contents

- [Overview](#overview)
- [APIM Configuration](#apim-configuration)
- [OAuth Policy Implementation](#oauth-policy-implementation)
- [Named Values Integration](#named-values-integration)
- [Backend Configuration](#backend-configuration)
- [Request Flow](#request-flow)
- [Related Documentation](#related-documentation)

## Overview

Azure API Management serves as the gateway and policy enforcement point for all API requests in this architecture.

**Key Responsibilities:**
- Validate JWT tokens from Azure AD
- Enforce audience and scope requirements
- Map user group membership to access levels
- Inject custom headers for backend authorization
- Route requests to backend services
- Provide observability and monitoring

**APIM SKU**: Developer (for POC), Standard/Premium recommended for production

## APIM Configuration

### Resource Structure

```
API Management Instance
├── APIs
│   └── HTTPBin API
│       ├── Operations
│       │   └── Test Operation (GET /test)
│       └── Policies
│           └── OAuth Policy (oauth-policy.xml)
├── Named Values
│   ├── tenant_id (from Key Vault)
│   ├── api_app_id (from Key Vault)
│   ├── client_app_id (from Key Vault)
│   ├── admin_group_id (from Key Vault)
│   └── standard_group_id (from Key Vault)
├── Backends
│   └── HTTPBin Backend (https://httpbin.org)
└── Products
    └── Default (unlimited access)
```

### Infrastructure Deployment

APIM is deployed via Bicep templates in the `iac/` directory.

**Main Module**: `iac/modules/apim.bicep`

**Key Features:**
- Managed identity for Key Vault access
- RBAC-based secret retrieval
- Named values synchronized from Key Vault
- Application Insights integration
- Global CORS policy

**Deployment Parameters:**
```bicep
module apim 'modules/apim.bicep' = {
  params: {
    name: 'apim-${resourceName}'
    location: location
    publisherEmail: 'admin@example.com'
    publisherName: 'OAuth OBO POC'
    sku: 'Developer'
    skuCapacity: 1
    namedValues: processedNamedValues
  }
}
```

## OAuth Policy Implementation

### Policy File Structure

The OAuth policy is defined in `iac/policies/oauth-policy.xml` and applied to the HTTPBin API.

### Complete Policy XML

```xml
<policies>
    <inbound>
        <base />
        <!-- JWT Validation -->
        <validate-jwt header-name="Authorization" 
                      failed-validation-httpcode="401" 
                      failed-validation-error-message="Unauthorized">
            <openid-config url="https://login.microsoftonline.com/{{tenant_id}}/.well-known/openid-configuration" />
            <required-claims>
                <claim name="aud">
                    <value>api://{{api_app_id}}</value>
                </claim>
                <claim name="scp" match="any">
                    <value>access_as_user</value>
                </claim>
            </required-claims>
        </validate-jwt>
        
        <!-- Group-Based Header Injection -->
        <choose>
            <when condition="@(context.Request.Headers.GetValueOrDefault("Authorization","").Contains("Bearer") && 
                              context.User.Groups.Any(g => g.Id == "{{admin_group_id}}"))">
                <set-header name="X-API-Key" exists-action="override">
                    <value>ADMIN</value>
                </set-header>
                <set-header name="X-User-Role" exists-action="override">
                    <value>admin</value>
                </set-header>
            </when>
            <otherwise>
                <set-header name="X-API-Key" exists-action="override">
                    <value>STANDARD</value>
                </set-header>
                <set-header name="X-User-Role" exists-action="override">
                    <value>user</value>
                </set-header>
            </otherwise>
        </choose>
        
        <!-- Backend Configuration -->
        <set-backend-service base-url="https://httpbin.org" />
        <rewrite-uri template="/get" />
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <base />
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>
```

### Policy Sections Explained

#### 1. JWT Validation

```xml
<validate-jwt header-name="Authorization" 
              failed-validation-httpcode="401" 
              failed-validation-error-message="Unauthorized">
    <openid-config url="https://login.microsoftonline.com/{{tenant_id}}/.well-known/openid-configuration" />
    <required-claims>
        <claim name="aud">
            <value>api://{{api_app_id}}</value>
        </claim>
        <claim name="scp" match="any">
            <value>access_as_user</value>
        </claim>
    </required-claims>
</validate-jwt>
```

**Purpose**: Validate JWT tokens from Azure AD

**Validation Steps:**
1. Extract Bearer token from Authorization header
2. Retrieve public keys from Azure AD OpenID configuration
3. Verify token signature
4. Validate token expiration
5. Check audience claim matches API app ID
6. Verify scope claim contains `access_as_user`

**Named Value Substitution:**
- `{{tenant_id}}`: Replaced with actual tenant ID from Key Vault
- `{{api_app_id}}`: Replaced with API application ID from Key Vault

#### 2. Group-Based Authorization

```xml
<choose>
    <when condition="@(context.Request.Headers.GetValueOrDefault("Authorization","").Contains("Bearer") && 
                      context.User.Groups.Any(g => g.Id == "{{admin_group_id}}"))">
        <set-header name="X-API-Key" exists-action="override">
            <value>ADMIN</value>
        </set-header>
        <set-header name="X-User-Role" exists-action="override">
            <value>admin</value>
        </set-header>
    </when>
    <otherwise>
        <!-- Standard user headers -->
    </otherwise>
</choose>
```

**Purpose**: Map Azure AD group membership to API access levels

**Logic:**
1. Check if request has Bearer token
2. Retrieve user's group memberships from token
3. If user is in admin group:
   - Set `X-API-Key: ADMIN`
   - Set `X-User-Role: admin`
4. Otherwise (standard user):
   - Set `X-API-Key: STANDARD`
   - Set `X-User-Role: user`

**Header Injection:**
- Headers are visible in HTTPBin response
- Headers can be used by backend for authorization
- Demonstrates group-based policy enforcement

#### 3. Backend Routing

```xml
<set-backend-service base-url="https://httpbin.org" />
<rewrite-uri template="/get" />
```

**Purpose**: Configure backend routing and URL rewriting

**Actions:**
- Set backend URL to HTTPBin
- Rewrite all requests to `/get` endpoint
- HTTPBin `/get` endpoint echoes request details

## Named Values Integration

### Overview

Named values are configuration parameters that can be referenced in policies using `{{name}}` syntax.

### Key Vault Integration

Named values are synchronized from Azure Key Vault using managed identity authentication.

**Bicep Configuration:**
```bicep
resource namedValueResource 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apimService
  name: namedValue.name
  properties: {
    displayName: namedValue.displayName
    secret: namedValue.secret
    keyVault: namedValue.secret ? {
      secretIdentifier: 'https://${keyVaultName}.vault.azure.net/secrets/${namedValue.keyVaultSecretName}'
    } : null
  }
}
```

### Named Values List

| Display Name | Key Vault Secret | Purpose |
|--------------|------------------|---------|
| `tenant_id` | `tenant-id` | Azure AD tenant identifier |
| `api_app_id` | `api-app-id` | Backend API application ID (audience) |
| `client_app_id` | `client-app-id` | Client application ID |
| `admin_group_id` | `admin-group-id` | Admin security group ID |
| `standard_group_id` | `standard-group-id` | Standard user group ID |

### Access Control

**RBAC Role**: `Key Vault Secrets User`

**Assigned To**: APIM managed identity

**Permissions**:
- Read secrets from Key Vault
- List secrets (for synchronization)
- No write or delete permissions

### Synchronization

- **Automatic**: Named values sync automatically from Key Vault
- **Status Check**: Use Azure Portal or CLI to verify sync status
- **Refresh**: Manually trigger refresh if values change

**Check Sync Status:**
```bash
az apim nv show \
  --service-name apim-oauthpoc \
  --resource-group rg-oauth-obo-poc-eastus \
  --named-value-id api_app_id \
  --query "properties.value"
```

## Backend Configuration

### HTTPBin Backend

**Purpose**: Test backend that echoes request details

**URL**: `https://httpbin.org`

**Endpoint Used**: `/get`

**Why HTTPBin:**
- Returns complete request details in JSON
- Shows all headers including injected ones
- No authentication required
- Reliable and well-maintained service

**Response Example:**
```json
{
  "args": {},
  "headers": {
    "Authorization": "Bearer eyJ0eXAiOiJKV1QiLCJhbGci...",
    "Host": "httpbin.org",
    "X-Api-Key": "STANDARD",
    "X-User-Role": "user",
    "X-Amzn-Trace-Id": "Root=1-..."
  },
  "origin": "x.x.x.x",
  "url": "https://httpbin.org/get"
}
```

### Custom Backend Integration

For production use, replace HTTPBin with custom backend:

**Policy Changes Required:**
```xml
<set-backend-service base-url="https://your-backend-api.com" />
<rewrite-uri template="/your-endpoint" />

<!-- Add authentication if needed -->
<authentication-managed-identity resource="https://your-backend-api.com" />
```

## Request Flow

### Detailed Request Flow

```
1. Client → APIM: HTTP GET with Bearer Token
   ├── Header: Authorization: Bearer <jwt-token>
   └── Header: X-User-Message: <user-message>

2. APIM: Execute Inbound Policy
   ├── Validate JWT
   │   ├── Get public keys from Azure AD
   │   ├── Verify signature
   │   ├── Check expiration
   │   ├── Validate audience (api://api-app-id)
   │   └── Validate scope (access_as_user)
   ├── Check User Groups
   │   └── Extract groups from token claims
   ├── Inject Headers
   │   ├── X-API-Key: ADMIN or STANDARD
   │   └── X-User-Role: admin or user
   └── Set Backend URL and URI

3. APIM → HTTPBin: Forward Request
   ├── All original headers
   ├── Injected X-API-Key header
   ├── Injected X-User-Role header
   └── Rewritten URI (/get)

4. HTTPBin → APIM: Return Response
   └── JSON with request details

5. APIM: Execute Outbound Policy
   └── No modifications (base policy only)

6. APIM → Client: Return Response
   └── JSON response with all headers visible
```

### Error Scenarios

#### JWT Validation Failure

**Trigger**: Invalid, expired, or missing token

**Response:**
```http
HTTP/1.1 401 Unauthorized
Content-Type: application/json

{
  "statusCode": 401,
  "message": "Unauthorized"
}
```

#### Audience Mismatch

**Trigger**: Token audience doesn't match API app ID

**Response:**
```http
HTTP/1.1 401 Unauthorized
Content-Type: application/json

{
  "statusCode": 401,
  "message": "Unauthorized. Invalid audience claim."
}
```

#### Missing Scope

**Trigger**: Token doesn't contain required scope

**Response:**
```http
HTTP/1.1 401 Unauthorized
Content-Type: application/json

{
  "statusCode": 401,
  "message": "Unauthorized. Required scope not present."
}
```

## Monitoring and Diagnostics

### Application Insights Integration

APIM sends telemetry to Application Insights:

**Metrics Collected:**
- Request count
- Response time
- Success rate
- Error rate
- Dependency calls

**Traces Available:**
- Policy execution traces
- JWT validation results
- Header injection logs
- Backend call details

### Diagnostic Settings

**Enable Diagnostics:**
```bash
az monitor diagnostic-settings create \
  --name apim-diagnostics \
  --resource /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.ApiManagement/service/{apim} \
  --logs '[{"category":"GatewayLogs","enabled":true}]' \
  --metrics '[{"category":"AllMetrics","enabled":true}]' \
  --workspace /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.OperationalInsights/workspaces/{workspace}
```

### Testing Policies

**Test JWT Validation:**
```bash
# Get access token
TOKEN=$(az account get-access-token --resource api://api-app-id --query accessToken -o tsv)

# Call APIM endpoint
curl -H "Authorization: Bearer $TOKEN" https://apim-name.azure-api.net/httpbin/test
```

**Test Without Token:**
```bash
# Should return 401 Unauthorized
curl https://apim-name.azure-api.net/httpbin/test
```

**Test With Invalid Token:**
```bash
# Should return 401 Unauthorized
curl -H "Authorization: Bearer invalid-token" https://apim-name.azure-api.net/httpbin/test
```

## Performance Considerations

### Token Validation Performance

- **Public Key Caching**: APIM caches Azure AD public keys
- **Token Parsing**: Minimal overhead (1-5ms)
- **Group Lookup**: Extracted from token claims (no external call)
- **Overall Overhead**: 10-50ms per request

### Scalability

**Developer SKU:**
- Single gateway unit
- No auto-scaling
- Rate limit: 50 requests/second

**Standard/Premium SKU:**
- Multiple gateway units
- Auto-scaling support
- Higher rate limits
- Multi-region deployment

### Caching Strategies

**Token Validation Results:**
- Not cached (security requirement)
- Each request validated independently

**Named Values:**
- Cached in APIM memory
- Synced from Key Vault periodically
- Refresh interval: Configurable

## Security Considerations

### JWT Validation Best Practices

✅ **Always Validate:**
- Token signature
- Token expiration
- Audience claim
- Scope/permission claims

✅ **Use Strong Validation:**
- Retrieve keys from OpenID configuration
- Verify issuer matches Azure AD
- Check token lifetime

❌ **Avoid:**
- Trusting tokens without validation
- Accepting tokens for wrong audience
- Ignoring token expiration

### Group-Based Authorization

✅ **Best Practices:**
- Store group IDs in Key Vault
- Use display names in policies for readability
- Document group-to-permission mapping
- Audit group membership regularly

❌ **Avoid:**
- Hardcoding group IDs in policies
- Granting access based on claims alone
- Over-permissive default policies

### Named Values Security

✅ **Best Practices:**
- Mark sensitive values as secret
- Use Key Vault integration
- Use RBAC for Key Vault access
- Rotate secrets periodically

❌ **Avoid:**
- Storing secrets in plain text
- Using access policies (use RBAC instead)
- Hardcoding secrets in policies

## Related Documentation

- [Architecture Overview](overview.md)
- [Security Architecture](security.md)
- [Azure AD Configuration](azure-ad.md)
- [Infrastructure Deployment](../../iac/README.md)
- [Policy Reference](https://docs.microsoft.com/en-us/azure/api-management/api-management-policies)
- [Lessons Learned](../lessons-learned.md)
