# Architecture Overview

This document provides a comprehensive overview of the OAuth 2.0 On-Behalf-Of (OBO) proof of concept architecture with Azure API Management and Kubernetes Workload Identity.

## Table of Contents

- [System Architecture](#system-architecture)
- [Component Architecture](#component-architecture)
- [Authentication Flow](#authentication-flow)
- [Deployment Architecture](#deployment-architecture)
- [Security Architecture](#security-architecture)
- [Related Documentation](#related-documentation)

## System Architecture

The system implements a complete OAuth 2.0 On-Behalf-Of flow with the following high-level architecture:

```
┌─────────────┐
│ User Browser│
└──────┬──────┘
       │ 1. OAuth Login (PKCE)
       ↓
┌─────────────────────────────┐
│ .NET Client Application     │
│ (ASP.NET Core Web App)      │
│ - Razor Pages UI            │
│ - Token Acquisition Service │
│ - API Client                │
└──────┬──────────────────────┘
       │ 2. Azure AD Authentication
       ↓
┌─────────────────────────────┐
│ Azure Active Directory      │
│ - User Authentication       │
│ - Token Issuance            │
│ - OBO Token Exchange        │
└──────┬──────────────────────┘
       │ 3. Bearer Token (OBO)
       ↓
┌─────────────────────────────┐
│ Azure API Management        │
│ - JWT Validation            │
│ - Group-Based Authorization │
│ - Header Injection          │
│ - Policy Enforcement        │
└──────┬──────────────────────┘
       │ 4. Forwarded Request + Headers
       ↓
┌─────────────────────────────┐
│ Backend Service             │
│ (HTTPBin for testing)       │
└─────────────────────────────┘
```

## Component Architecture

### 1. Client Application

The .NET client application is an ASP.NET Core web application deployed as a containerized workload.

**Key Components:**
- **Razor Pages UI**: Chat-like interface for user interaction
- **Token Acquisition Services**: Environment-aware token acquisition
  - `WorkloadIdentityTokenService`: Production (AKS) using federated credentials
  - `ClientSecretTokenService`: Development (Local) using client secrets
- **API Client**: Service for making authenticated calls to APIM
- **Authentication Middleware**: Microsoft Identity Web for OAuth/OIDC

**Configuration:**
- Environment-based service selection (Production vs Development)
- In-memory token caching for performance
- Session management for user state

See: [Application Architecture](application.md)

### 2. Azure Active Directory

**App Registrations:**
- **Client App**: User authentication and token acquisition
  - Type: Web application with public/confidential client capabilities
  - Redirect URIs: Configured for both local and cloud deployments
  - Permissions: API permission to backend API scope
- **API App**: Backend API representation
  - Exposed Scope: `access_as_user`
  - Token Version: v2.0

**Security Groups:**
- Admin Group: For elevated permissions
- Standard Group: For regular user access

See: [Azure AD Configuration](azure-ad.md)

### 3. Azure Kubernetes Service (AKS)

**Features:**
- OIDC Issuer enabled for workload identity
- Managed identity integration
- Web Application Routing (ingress controller)
- Container Registry integration

**Workload Identity:**
- Federated credentials linking K8s service account to managed identity
- Service account annotations for identity binding
- Pod labels for workload identity activation

See: [Kubernetes Architecture](kubernetes.md)

### 4. Azure API Management

**Components:**
- **Gateway**: Entry point for all API requests
- **Policies**: OAuth validation and header injection
  - JWT validation against Azure AD
  - Audience and scope verification
  - Group-based authorization
  - Custom header injection
- **Named Values**: Configuration from Key Vault
- **Backend**: HTTPBin for testing

**Policy Flow:**
```xml
<inbound>
  1. Validate JWT token
  2. Check audience and scope
  3. Evaluate user group membership
  4. Inject X-API-Key and X-User-Role headers
  5. Set backend URL and rewrite URI
</inbound>
```

See: [APIM Configuration](apim.md)

### 5. Azure Key Vault

**Purpose:**
- Secure storage for OAuth configuration
- RBAC-based access control
- Named values synchronization to APIM

**Stored Secrets:**
- `tenant-id`: Azure AD tenant identifier
- `api-app-id`: Backend API application ID
- `client-app-id`: Client application ID
- `admin-group-id`: Admin security group ID
- `standard-group-id`: Standard user group ID

See: [Security Architecture](security.md)

## Authentication Flow

### User Authentication Flow

```
1. User accesses application
   ↓
2. Application redirects to Azure AD login
   ↓
3. User authenticates with Azure AD
   ↓
4. Azure AD redirects back with authorization code
   ↓
5. Application exchanges code for tokens (PKCE)
   ↓
6. Tokens stored in session and token cache
```

### Token Acquisition Flow (Production - AKS)

```
1. Application requests token for API scope
   ↓
2. WorkloadIdentityTokenService uses DefaultAzureCredential
   ↓
3. Workload Identity exchanges service account token for Azure AD token
   ↓
4. Token acquired via federated credential (no secrets)
   ↓
5. Token cached in memory for reuse
```

### Token Acquisition Flow (Development - Local)

```
1. Application requests token for API scope
   ↓
2. ClientSecretTokenService uses client secret
   ↓
3. MSAL builds confidential client application
   ↓
4. Token acquired via client credentials or OBO flow
   ↓
5. Token cached in memory for reuse
```

### API Call Flow

```
1. User sends message via chat interface
   ↓
2. ApiClient acquires access token from token cache
   ↓
3. HTTP request created with Bearer token
   ↓
4. Request sent to APIM endpoint
   ↓
5. APIM validates JWT and injects headers
   ↓
6. Request forwarded to HTTPBin
   ↓
7. Response returned with all headers visible
   ↓
8. Application parses and displays response
```

## Deployment Architecture

### Cloud Deployment (AKS)

```
┌─────────────────────────────────────────────────┐
│ Azure Subscription                              │
│                                                 │
│ ┌──────────────────────────────────────────┐   │
│ │ Resource Group                           │   │
│ │                                          │   │
│ │ ┌──────────────┐  ┌──────────────┐      │   │
│ │ │ AKS Cluster  │  │ APIM Service │      │   │
│ │ │              │  │              │      │   │
│ │ │ - Client Pod │  │ - Gateway    │      │   │
│ │ │ - Service    │  │ - Policies   │      │   │
│ │ │ - Ingress    │  │ - Named Vals │      │   │
│ │ └──────────────┘  └──────────────┘      │   │
│ │                                          │   │
│ │ ┌──────────────┐  ┌──────────────┐      │   │
│ │ │ Key Vault    │  │ ACR Registry │      │   │
│ │ │              │  │              │      │   │
│ │ │ - Secrets    │  │ - Images     │      │   │
│ │ │ - RBAC       │  │              │      │   │
│ │ └──────────────┘  └──────────────┘      │   │
│ │                                          │   │
│ │ ┌──────────────┐  ┌──────────────┐      │   │
│ │ │ App Insights │  │ Managed ID   │      │   │
│ │ └──────────────┘  └──────────────┘      │   │
│ └──────────────────────────────────────────┘   │
│                                                 │
│ ┌──────────────────────────────────────────┐   │
│ │ Azure Active Directory                   │   │
│ │ - App Registrations                      │   │
│ │ - Security Groups                        │   │
│ │ - Federated Credentials                  │   │
│ └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

### Local Deployment (Minikube)

```
┌─────────────────────────────────────────────────┐
│ Local Machine                                   │
│                                                 │
│ ┌──────────────────────────────────────────┐   │
│ │ Minikube Cluster                         │   │
│ │                                          │   │
│ │ ┌──────────────┐                         │   │
│ │ │ Client Pod   │                         │   │
│ │ │              │                         │   │
│ │ │ - Uses Secret│                         │   │
│ │ │ - Ingress    │                         │   │
│ │ └──────────────┘                         │   │
│ └──────────────────────────────────────────┘   │
│                                                 │
│           │                                     │
│           │ HTTPS                               │
│           ↓                                     │
│                                                 │
│ ┌──────────────────────────────────────────┐   │
│ │ Azure (Cloud Resources)                  │   │
│ │ - APIM Service                           │   │
│ │ - Azure Active Directory                 │   │
│ └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

See: [Deployment Guide](../deployment/overview.md)

## Security Architecture

### Authentication Security

- **Authorization Code Flow with PKCE**: Protects against authorization code interception
- **No Client Secrets in Production**: Workload identity uses federated credentials
- **Token Caching**: In-memory caching with automatic refresh
- **HTTPS/TLS**: All communication encrypted in transit

### Authorization Security

- **JWT Validation**: APIM validates all tokens before processing
- **Audience Validation**: Ensures tokens are for the correct API
- **Scope Validation**: Verifies required permissions
- **Group-Based Access Control**: Maps Azure AD groups to access levels

### Infrastructure Security

- **RBAC Access**: Key Vault uses role-based access control
- **Managed Identity**: Service-to-service authentication without secrets
- **Federated Credentials**: Kubernetes service account to Azure AD mapping
- **Network Isolation**: Resources deployed in Azure virtual networks (optional)

### Secrets Management

- **Key Vault Integration**: All secrets stored in Azure Key Vault
- **Named Values Sync**: APIM synchronizes configuration from Key Vault
- **No Hardcoded Secrets**: All credentials injected at runtime
- **Time-Limited Secrets**: Client secrets expire after 1 year

See: [Security Architecture](security.md)

## Technology Stack

### Application Layer
- **Language**: C# / .NET 9.0
- **Framework**: ASP.NET Core
- **UI**: Razor Pages
- **Authentication**: Microsoft.Identity.Web
- **Token Acquisition**: MSAL (Microsoft Authentication Library)
- **HTTP Client**: System.Net.Http

### Infrastructure Layer
- **Container Runtime**: Docker
- **Orchestration**: Kubernetes (AKS / Minikube)
- **Package Manager**: Helm
- **Infrastructure as Code**: Bicep
- **Identity**: Azure Workload Identity

### Azure Services
- **API Management**: OAuth policy enforcement
- **Kubernetes Service**: Container orchestration
- **Key Vault**: Secret management
- **Container Registry**: Image storage
- **Active Directory**: Identity and access management
- **Application Insights**: Monitoring and logging

## Key Design Decisions

### 1. Environment-Aware Token Acquisition

**Decision**: Use different token acquisition strategies based on environment.

**Rationale**: 
- Production environments should not use client secrets
- Workload identity provides better security in Kubernetes
- Local development still needs traditional authentication

**Implementation**: Interface-based service selection at startup

### 2. Chat Interface for Testing

**Decision**: Build a chat-like UI instead of traditional web forms.

**Rationale**:
- More engaging user experience
- Easy to test multiple API calls
- Shows real-time authentication flow
- Demonstrates header injection visually

### 3. HTTPBin as Backend

**Decision**: Use HTTPBin instead of custom API.

**Rationale**:
- HTTPBin echoes all request details including headers
- No need to implement custom validation logic
- Easy to verify APIM policy enforcement
- Well-known, reliable test service

### 4. Bicep for IaC

**Decision**: Use Bicep instead of ARM templates or Terraform.

**Rationale**:
- Native Azure tooling
- Better readability than ARM JSON
- Type safety and IntelliSense support
- Converts to ARM templates automatically

### 5. In-Memory Token Caching

**Decision**: Use in-memory token caching instead of distributed cache.

**Rationale**:
- Sufficient for POC/demo purposes
- Simplifies deployment
- Reduces dependencies
- Production would use distributed cache (Redis)

## Performance Characteristics

### Token Acquisition
- **First Token**: 1-3 seconds (authentication flow)
- **Cached Token**: <100ms (memory lookup)
- **Token Refresh**: 500ms-1s (automatic via MSAL)

### API Calls
- **APIM Processing**: 50-200ms (JWT validation + policies)
- **HTTPBin Response**: 100-300ms (network latency)
- **Total Round Trip**: 200-500ms (typical)

### Resource Usage
- **Client Pod**: 100-200MB memory, 0.1-0.2 CPU cores
- **Startup Time**: 5-10 seconds (container start + initialization)

## Scalability Considerations

### Current State (POC)
- Single pod deployment
- No horizontal scaling
- In-memory caching per pod
- Developer SKU APIM (no SLA)

### Production Recommendations
- **Horizontal Pod Autoscaling**: Scale based on CPU/memory
- **APIM Standard/Premium**: Better performance and SLA
- **Distributed Caching**: Redis for token caching across pods
- **Application Gateway**: WAF and additional security
- **Multiple Regions**: For global availability

## Related Documentation

### Getting Started
- [Getting Started Guide](../getting-started.md)
- [Prerequisites](../deployment/prerequisites.md)
- [Quick Start](../deployment/quickstart.md)

### Component Documentation
- [Application Architecture](application.md)
- [Azure AD Configuration](azure-ad.md)
- [APIM Configuration](apim.md)
- [Kubernetes Architecture](kubernetes.md)
- [Security Architecture](security.md)

### Deployment
- [Deployment Overview](../deployment/overview.md)
- [Infrastructure Deployment](../deployment/infrastructure.md)
- [Application Deployment](../deployment/application.md)
- [Helm Charts](../helm.md)

### Operations
- [Troubleshooting Guide](../troubleshooting.md)
- [Monitoring and Logging](../operations/monitoring.md)
- [Maintenance](../operations/maintenance.md)

### Development
- [Developer Guide](../development/guide.md)
- [Source Code Overview](../../src/README.md)

### Reference
- [Requirements](../requirements.md)
- [Lessons Learned](../lessons-learned.md)
- [Deployment Script](../deployment-script.md)
- [Ingress Configuration](../ingress.md)
