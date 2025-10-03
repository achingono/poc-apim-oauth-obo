# Groups Claim Configuration

## Overview

This document explains how the groups claim is configured in the OAuth flow to enable group-based authorization in Azure API Management (APIM) policies.

## Problem

By default, Azure AD does not include the `groups` claim in JWT access tokens. Without this claim, APIM policies cannot make authorization decisions based on user group membership.

## Solution

The groups claim is enabled through Azure AD app registration configuration using two key settings:

### 1. Group Membership Claims

The `groupMembershipClaims` property specifies which groups should be included in the token:

- `SecurityGroup`: Include security groups and directory roles
- `ApplicationGroup`: Include only groups assigned to the application
- `All`: Include security groups, directory roles, and distribution lists
- `DirectoryRole`: Include directory roles only (in the `wids` claim)

For this project, we use `SecurityGroup` to include all security groups the user is a member of.

### 2. Optional Claims (For Access Tokens)

The `optionalClaims.accessToken` configuration explicitly requests the groups claim to be included in **access tokens** (not just ID tokens):

```json
{
  "name": "groups",
  "source": null,
  "essential": false,
  "additionalProperties": []
}
```

**Important**: While `groupMembershipClaims` alone often works for ID tokens, explicitly configuring `optionalClaims.accessToken` is recommended to ensure the groups claim appears in access tokens, which is what your API and APIM receive.

The `optionalClaims` section allows you to:
- Specify which token types (ID, access, SAML) should include groups
- Optionally modify the group format (e.g., using `additionalProperties` to emit as roles or include SAM account names)

## Implementation

Both configurations work together to ensure groups appear in access tokens:

1. **`groupMembershipClaims`**: Declares which groups should be included
2. **`optionalClaims.accessToken`**: Ensures groups appear in access tokens specifically

The configuration is automatically applied by the `scripts/functions.sh` script in the `create_app_registrations` function:

### For New API App Registrations

```bash
az ad app update --id "$API_APP_ID" \
    --set groupMembershipClaims="SecurityGroup" \
    --set optionalClaims.accessToken='[{"name":"groups","source":null,"essential":false,"additionalProperties":[]}]' \
    ...
```

### For Existing API App Registrations

The script checks for existing app registrations and applies the same configuration to ensure groups claims are enabled.

## Verification

After running the deployment script, you can verify the groups claim is included in the JWT token:

1. **Sign in to the application** and trigger an API call
2. **Inspect the JWT token** (you can decode it at https://jwt.ms)
3. **Look for the `groups` claim** in the token payload

Example token with groups claim:

```json
{
  "aud": "api://379eb22e-22d4-4990-8fdc-caef12894896",
  "iss": "https://sts.windows.net/7b0501ff-fd85-4889-8f3f-d1c93f3b5315/",
  "groups": [
    "a1b2c3d4-e5f6-7890-1234-567890abcdef",
    "b2c3d4e5-f6a7-8901-2345-67890abcdef0"
  ],
  "scp": "access_as_user",
  "oid": "348f445c-75b9-452e-b8ce-80688eb4f743",
  ...
}
```

## Group Overage Considerations

### Token Size Limits

Azure AD limits the number of groups included in tokens:

- **OAuth 2.0 tokens**: Maximum 200 groups
- **SAML tokens**: Maximum 150 groups
- **Implicit grant flow**: Maximum 6 groups

### Group Overage Claim

If a user is a member of more groups than the limit, Azure AD will:

1. **Not include the groups claim** in the token
2. **Include a group overage indicator** (`_claim_names` and `_claim_sources`)
3. **Require a separate call to Microsoft Graph** to retrieve all groups

### Handling Group Overage

To handle group overage scenarios:

1. **Use "Groups assigned to the application"** option to limit groups to only those assigned to your app
2. **Implement Microsoft Graph fallback** in your application to retrieve groups when overage occurs
3. **Use app roles instead of groups** for fine-grained authorization

For this POC, we use the default `SecurityGroup` setting. For production scenarios with many groups, consider switching to `ApplicationGroup`:

```bash
--set groupMembershipClaims="ApplicationGroup"
```

## APIM Policy Usage

Once the groups claim is included in the token, the APIM policy can use it for authorization:

```xml
<validate-jwt header-name="Authorization">
    <openid-config url="https://login.microsoftonline.com/{{tenant_id}}/.well-known/openid-configuration" />
    <required-claims>
        <claim name="groups" match="any">
            <value>{{admin_group_id}}</value>
        </claim>
    </required-claims>
</validate-jwt>
```

Or conditionally based on group membership:

```xml
<choose>
    <when condition="@(((Jwt)context.Variables.GetValueOrDefault("jwt"))?.Claims.GetValueOrDefault("groups", new string[0]).Contains("{{admin_group_id}}") ?? false)">
        <set-header name="X-User-Role" exists-action="override">
            <value>admin</value>
        </set-header>
    </when>
    <otherwise>
        <set-header name="X-User-Role" exists-action="override">
            <value>user</value>
        </set-header>
    </otherwise>
</choose>
```

## Manual Configuration (Azure Portal)

If you need to configure this manually via the Azure Portal:

1. Navigate to **Azure AD** > **App registrations**
2. Select your **API app registration**
3. Go to **Token configuration**
4. Click **Add groups claim**
5. Select **Security groups** (or your preferred option)
6. Select **Access** token type
7. Click **Add**

Alternatively, you can edit the manifest directly:

1. Go to **Manifest** in your app registration
2. Update the following properties:
   ```json
   {
     "groupMembershipClaims": "SecurityGroup",
     "optionalClaims": {
       "accessToken": [
         {
           "name": "groups",
           "source": null,
           "essential": false,
           "additionalProperties": []
         }
       ]
     }
   }
   ```
3. Click **Save**

## Testing

To test the groups claim:

1. **Create a test security group** in Azure AD
2. **Add the test user** to the security group
3. **Run the deployment script** to update the app registration
4. **Sign out and sign in again** to get a fresh token
5. **Call the API** through the client application
6. **Inspect the token** to verify the groups claim is present

## References

- [Configure group claims for applications](https://learn.microsoft.com/en-us/entra/identity-platform/optional-claims#configure-groups-optional-claims)
- [Microsoft Entra optional claims](https://learn.microsoft.com/en-us/entra/identity-platform/optional-claims)
- [Configure tokens with group claims and app roles](https://learn.microsoft.com/en-us/security/zero-trust/develop/configure-tokens-group-claims-app-roles)
- [Group overage claims](https://learn.microsoft.com/en-us/entra/identity-platform/id-token-claims-reference#groups-overage-claim)
