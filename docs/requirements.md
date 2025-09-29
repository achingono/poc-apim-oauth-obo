# Proof of Concept Requirements: OAuth2 On-Behalf-Of with Azure APIM & Kubernetes Workload Identity

## 1. Purpose & Overview
Demonstrate an end-to-end delegated access (OAuth 2.0 On-Behalf-Of flow) from a .NET client workload running in Azure Kubernetes Service (AKS) in the target environment, with local developer iteration using a minikube cluster. The workload uses Azure Workload Identity (federated credentials) to obtain tokens from Azure Entra ID, invoking an Azure API Management (APIM) fronted Backend Python API. APIM enforces OAuth access tokens, maps user group membership to backend API keys via policy logic, and forwards the appropriate API key to the Python API which validates the key and authorizes the request.

## 2. In-Scope
- Single tenant Azure Entra ID configuration
- One .NET client (console/service) running in AKS (production / shared cluster) with Azure Workload Identity
- Local developer workflow mirrored on minikube (where true workload identity may be simulated or substituted)
- httpbin.org as the backend service (no custom API key validation required)
- Azure APIM instance (Consumption or Developer tier acceptable) acting as façade enforcing OAuth2 access token validation and injecting headers that can be observed via httpbin.org responses
- Azure Entra ID app registrations for: (a) Client App (public / daemon) (b) Downstream API (exposed scope)
- On-Behalf-Of (OBO) token exchange from client to call downstream scope via APIM
- APIM policies for: validate-jwt, conditionally selecting and injecting API key header based on user/group claims
- Azure Workload Identity configuration in AKS (federated credential linking service account)
- Local developer workflow using minikube & Azure CLI

## 3. Out-of-Scope
- Multi-tenant support
- Production-grade monitoring, scaling & HA
- Secrets rotation automation
- Multi-environment promotion pipelines
- Advanced API versioning or pagination

## 4. Success Criteria / Acceptance
| ID | Criterion |
|----|-----------|
| AC1 | Client pod acquires initial token using workload identity without client secrets |
| AC2 | OBO flow successfully retrieves downstream API access token (scope: api://backend-api/.default or specific)|
| AC3 | APIM validates JWT and forwards request with correct API key mapped from user group |
| AC4 | httpbin.org responds with injected headers visible in JSON response; APIM policies successfully modify requests |
| AC5 | Different user groups result in different injected headers (verified by httpbin.org response analysis) |
| AC6 | End-to-end run documented with reproducible commands |

## 5. Architecture Summary
Sequence:
1. User authenticates externally (or simulated) -> access token provided to client (if user context needed). Alternatively MSAL device code / interactive for POC.
2. .NET client in Kubernetes uses the user token + its own credentials (via workload identity federation) to perform OBO request to Entra (MSAL ConfidentialClient AcquireTokenOnBehalfOf).
3. Client calls APIM endpoint with OBO access token (Bearer).
4. APIM validate-jwt policy checks token issuer, audience (downstream API app id URI), scope/roles, extracts groups.
5. APIM policy maps group -> API key/role header; injects headers (e.g. X-API-Key, X-User-Role) that will be visible in httpbin.org response.
6. httpbin.org returns request details including all injected headers in JSON format for validation.
7. Response returned upstream with header injection proof visible to client.

## 6. Component Responsibilities
| Component | Responsibility |
|-----------|---------------|
| .NET Client | Acquire user token, perform OBO token exchange, call APIM endpoint |
| Kubernetes (minikube) | Host client workload with projected service account token enabling Azure Workload Identity federation |
| Azure Workload Identity | Federated identity credential linking K8s service account -> Entra app service principal |
| Entra Client App Reg | Defines redirect (if needed), allows public client (for device code), exposes permissions to downstream API |
| Entra API App Reg | Exposes scope(s) used by APIM audience validation |
| APIM | Validates JWT, enforces auth, injects headers based on group claims for httpbin.org inspection |
| httpbin.org | Returns request details including injected headers for APIM policy validation |

## 7. Identity & Security Model
### 7.1 Token Flow
**AKS Production Environment:**
- Initial User Token Acquisition: Authorization Code Flow with PKCE
- Client Authentication: Azure Workload Identity Federation (no client secrets)
- OBO Exchange: Uses federated credential assertion for confidential client flow

**Local Minikube Development:**
- Initial User Token Acquisition: Device code or interactive (MSAL) for POC
- Client Authentication: Traditional Client ID + Client Secret
- OBO Exchange: Uses client secret for confidential client flow

### 7.2 Claims Required
- aud: api://<backend-api-app-id-uri>
- scp or roles: contains required scope (e.g., access_as_user)
- groups: Azure AD group object IDs (ensure group overage not hitting 150 limit; if so use group claims via app manifest setting)

### 7.3 Header Injection Mapping
| Group Object ID | Logical Role | Headers Injected | Purpose |
|-----------------|-------------|------------------|---------|
| <GROUP_ID_A> | StandardUser | X-API-Key: STANDARD, X-User-Role: user | Visible in httpbin.org response for validation |
| <GROUP_ID_B> | AdminUser | X-API-Key: ADMIN, X-User-Role: admin | Visible in httpbin.org response for validation |

### 7.4 Secrets & Configuration Handling
- Header values stored as named values in APIM (for consistency) and/or directly in policy.
- No backend secrets required since httpbin.org simply echoes request details.
- **AKS**: No client secret used; workload identity federation replaces it.
- **Local**: Client secret stored in Kubernetes secret for development/testing only.

## 8. Azure Resources (Minimum)
| Resource | Purpose | Notes |
|----------|---------|-------|
| Resource Group | Containment | Single RG for POC |
| Managed Identity (User-assigned optional) | Alternative to federated credential | POC likely uses federation directly |
| APIM Instance | API gateway | Developer tier recommended |
| App Registrations (2) | Client & API | OBO config + scope exposure |
| Key Vault (optional) | Store API keys | Could be skipped if APIM named values suffice |
| Log Analytics (optional) | Diagnostics | Observability |

## 9. Kubernetes Setup (AKS & Local)
### 9.1 AKS (Target Environment)
Steps:
1. Create / select AKS cluster with OIDC issuer & workload identity enabled (AKS feature flags: `--enable-oidc-issuer --enable-workload-identity`).
2. Create namespace (e.g., `poc-client`).
3. Create Kubernetes ServiceAccount (e.g., `client-sa`).
4. In Entra ID, add Federated Credential to Client App referencing: issuer = AKS OIDC issuer, subject = `system:serviceaccount:poc-client:client-sa`, audience = `api://AzureADTokenExchange`.
5. Deploy .NET client Deployment (or Job) referencing `serviceAccountName: client-sa`.
6. Mount / inject configuration via ConfigMap & Secret (if any non-federated secrets needed). No client secret expected.
7. Validate token acquisition via pod logs (MSAL AcquireTokenOnBehalfOf success).

### 9.2 Local (minikube) Developer Flow
For local development, use traditional client secret authentication:

**Authentication Approach:**
- Client ID + Client Secret stored in Kubernetes Secret
- MSAL ConfidentialClientApplication with ClientCredential (secret)
- Authorization Code Flow for initial user authentication
- OBO flow using client secret instead of federated credentials

**Implementation Steps:**
1. Start minikube (standard settings).
2. Create namespace `poc-client`.
3. Create Kubernetes Secret with Client ID and Client Secret:
   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: azure-client-credentials
     namespace: poc-client
   data:
     clientId: <base64-encoded-client-id>
     clientSecret: <base64-encoded-client-secret>
   ```
4. Deploy .NET client with environment variable `ENVIRONMENT=Development`.
5. Application detects environment and uses ClientCredential instead of WorkloadIdentity.
6. Provide configuration via ConfigMap (APIM base URL, scope, tenant ID).
7. Test full OAuth2 Authorization Code + OBO flow.

### 9.3 Authentication Parity & Abstraction
- **Interface Abstraction**: Token acquisition abstracted behind ITokenAcquisitionService
- **Environment Detection**: Application automatically detects AKS vs local environment
- **Configuration-Driven**: Switch between WorkloadIdentity and ClientSecret via environment variables
- **Logging**: Clear indication of which authentication method is being used
- **Security**: Client secrets only used in development, never in production AKS

**Environment Variables:**
- `ENVIRONMENT`: "Production" (AKS) or "Development" (local)
- `AZURE_CLIENT_ID`: Client application ID (both environments)
- `AZURE_TENANT_ID`: Azure AD tenant ID (both environments)
- `AZURE_CLIENT_SECRET`: Client secret (local only)
- `AZURE_FEDERATED_TOKEN_FILE`: Workload identity token file (AKS only)

## 10. APIM Configuration
Policies (per API or operation):
```
<inbound>
	<base />
	<validate-jwt header-name="Authorization" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized">
		<openid-config url="https://login.microsoftonline.com/<tenant-id>/.well-known/openid-configuration" />
		<required-claims>
			<claim name="aud">
				<value>api://<backend-api-app-id-uri></value>
			</claim>
		</required-claims>
		<required-scopes>
			<scope>access_as_user</scope>
		</required-scopes>
	</validate-jwt>
	<set-variable name="groupId" value="@( (string)context.Request.Headers.GetValueOrDefault("x-ms-groups-claim") )" />
	<!-- Alternative: parse claims from context.Principal -->
	<choose>
		<when condition="@(context.Principal?.Claims.Any(c => c.Type == "groups" && c.Value == "<GROUP_ID_B>"))">
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
```

## 11. Backend Service (httpbin.org)
Using httpbin.org as the backend service provides several advantages:
- No custom backend deployment required
- Request inspection capabilities built-in
- Returns complete request details including headers injected by APIM
- JSON response format ideal for automated validation
- Available endpoints: /get, /post, /headers, /ip, etc.
- Headers injected by APIM policies will be visible in the response for verification

## 12. .NET Client Design
**Key Responsibilities:**
1. **User Authentication**: Authorization Code Flow with PKCE (web application)
2. **Environment-Aware Token Acquisition**: 
   - AKS: Use Azure Workload Identity (federated credentials)
   - Local: Use Client ID + Client Secret
3. **OBO Token Exchange**: Acquire downstream API token using appropriate credential type
4. **APIM Integration**: Call APIM endpoints with Bearer token
5. **Response Analysis**: Parse httpbin.org responses to validate header injection

**Libraries:** Microsoft.Identity.Client, Microsoft.Identity.Web, System.Net.Http, Azure.Identity

**Authentication Architecture:**
```csharp
public interface ITokenAcquisitionService 
{
    Task<string> AcquireTokenForUserAsync(string[] scopes);
    Task<string> AcquireTokenOnBehalfOfAsync(string userToken, string[] scopes);
}

// AKS Implementation
public class WorkloadIdentityTokenService : ITokenAcquisitionService { }

// Local Implementation  
public class ClientSecretTokenService : ITokenAcquisitionService { }
```

**Edge Cases:**
- Environment detection failure: fallback to development mode with logging
- Token cache absent: handle initial acquisition gracefully
- Group overage: if overage claim `_claim_names` present, fail fast for POC
- 401 from APIM: differentiate JWT invalid vs backend failure via response analysis
- Workload identity unavailable: clear error messaging for setup issues

## 13. Configuration Matrix
| Setting | AKS Location | Local Location | Example |
|---------|-------------|----------------|---------|
| Environment | env | env | "Production" / "Development" |
| Tenant ID | ConfigMap | ConfigMap | 11111111-2222-3333-4444-555555555555 |
| Client App ID | ConfigMap | ConfigMap | aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee |
| Client Secret | N/A (Workload Identity) | Secret | client-secret-value |
| API App ID URI | ConfigMap | ConfigMap | api://ffffffff-1111-2222-3333-444444444444 |
| Scope | ConfigMap | ConfigMap | api://ffffffff-1111-2222-3333-444444444444/access_as_user |
| APIM Base URL | ConfigMap | ConfigMap | https://poc-apim.azure-api.net/httpbin |
| Federated Token File | /var/run/secrets/azure/tokens/azure-identity-token | N/A | auto-mounted by workload identity |

## 14. Implementation Plan (Phased)
1. Azure Entra: Create API App Reg (expose scope) & Client App Reg (add API permission, grant admin consent; enable groups claim); defer federated credential until AKS namespace/service account decided.
2. APIM: Configure httpbin.org as backend, add JWT validation policy, implement group->header mapping policy.
3. Frontend UI: Update to parse httpbin.org responses and validate APIM header injection based on user groups.
4. .NET Client (Local / Simulation): Implement MSAL flows (device + OBO) using temporary simulation path.
5. AKS Workload Identity Enablement: Enable cluster flags, create namespace & ServiceAccount, add federated credential, redeploy client using real federation path.
6. APIM Integration Test (AKS): Validate real OBO from pod with no client secret present.
7. Minikube Path (Optional): Provide simulation manifest & doc verifying similar request flow (accepted differences documented).
8. Testing & Logging: Add APIM trace, backend request logging (key hash only), capture scenario outputs.
9. Documentation: Usage guide (AKS + local), cleanup steps.

## 15. Testing Scenarios
| ID | Scenario | Expected Result |
|----|----------|-----------------|
| T1 | Valid standard user | 200 + httpbin response showing X-API-Key: STANDARD, X-User-Role: user |
| T2 | Valid admin user | 200 + httpbin response showing X-API-Key: ADMIN, X-User-Role: admin |
| T3 | Missing header injection (manually disable policy) | 200 but no custom headers in httpbin response |
| T4 | Invalid group claim | Standard headers injected (fallback behavior) |
| T5 | Expired access token | 401 -> client refreshes via MSAL OBO refresh |
| T6 | Tampered token signature | 401 at APIM |

## 16. Non-Functional Requirements
- Security: No static secrets in repo; keys rotate by re-deploying named values
- Observability: Basic logging (client console, backend access log, APIM trace)
- Performance: Single user concurrency; latency < 2s acceptable for POC
- Maintainability: Clear environment variable usage; infra scripts idempotent
- Portability: Backend container runnable locally without Azure dependencies (API key check only)

## 17. Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|-----------|
| Workload identity harder on minikube | Delay | Provide alternative (client cert) path |
| Group claim overage | Authorization mapping fails | Limit test user groups / use app manifest groups assignment only |
| Clock skew | Token validation errors | Ensure NTP sync in cluster |
| Policy complexity | Errors in mapping | Add APIM trace & unit test snippet using policy expressions |

## 18. Open Questions
- Will production require RBAC beyond group->key (e.g. attribute-based)?
- Prefer per-user or per-group API keys long-term?
- Need Key Vault integration for rotation demonstration?

## 19. Deliverables
- Updated `REQUIREMENTS.md` (this document)
- .NET client UI with httpbin.org response analysis
- .NET client code & Dockerfile
- Kubernetes manifests (YAML)
- APIM policy XML for httpbin.org backend
- Setup & teardown scripts (bash / Azure CLI)
- Test run log / screenshots showing header validation

## 20. Cleanup Strategy
Document script to remove resource group, delete local images, and purge named values.

## 21. Next Steps After POC
- Add CI/CD pipeline
- Integrate Key Vault for API keys
- Implement per-operation scope enforcement
- Add distributed tracing (App Insights + OpenTelemetry)

---
Status: Draft v1.0

