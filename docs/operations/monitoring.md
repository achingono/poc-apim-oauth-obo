# Monitoring and Operations Guide

This document covers monitoring, logging, and operational aspects of the OAuth OBO POC.

## Table of Contents

- [Monitoring Overview](#monitoring-overview)
- [Application Monitoring](#application-monitoring)
- [Infrastructure Monitoring](#infrastructure-monitoring)
- [Logging](#logging)
- [Alerting](#alerting)
- [Performance Metrics](#performance-metrics)
- [Troubleshooting Operations](#troubleshooting-operations)

## Monitoring Overview

The OAuth OBO POC uses Azure native monitoring services for comprehensive observability.

**Monitoring Stack:**
- **Application Insights**: Application telemetry and logs
- **Log Analytics**: Centralized log aggregation
- **Azure Monitor**: Infrastructure metrics
- **Kubernetes Metrics**: Container and pod monitoring

## Application Monitoring

### Application Insights

**Resource Name**: `appi-{name}-{suffix}`

**Integrated Components:**
- .NET Client Application (optional)
- Azure API Management
- AKS Container Insights

**Key Metrics:**
- Request count and duration
- Success/failure rates
- Dependency calls
- Exceptions
- Custom events

### View Application Insights

**Azure Portal:**
1. Navigate to Application Insights resource
2. Select "Application Map" for topology view
3. Select "Live Metrics" for real-time monitoring
4. Select "Failures" for error analysis
5. Select "Performance" for response times

**Azure CLI:**
```bash
# Query traces
az monitor app-insights query \
  --app <app-insights-name> \
  --analytics-query "traces | where timestamp > ago(1h)" \
  --offset 1h

# Query requests
az monitor app-insights query \
  --app <app-insights-name> \
  --analytics-query "requests | summarize count() by resultCode" \
  --offset 24h
```

### Key Queries

**Failed Requests:**
```kusto
requests
| where timestamp > ago(1h)
| where success == false
| project timestamp, name, resultCode, duration, url
| order by timestamp desc
```

**Slow Requests:**
```kusto
requests
| where timestamp > ago(1h)
| where duration > 1000  // Over 1 second
| project timestamp, name, duration, url
| order by duration desc
```

**Exception Analysis:**
```kusto
exceptions
| where timestamp > ago(24h)
| summarize count() by type, outerMessage
| order by count_ desc
```

**Dependency Failures:**
```kusto
dependencies
| where timestamp > ago(1h)
| where success == false
| project timestamp, name, type, data, resultCode
| order by timestamp desc
```

## Infrastructure Monitoring

### Azure Kubernetes Service

**Monitoring Options:**
- Container Insights (enabled by default)
- Kubernetes metrics
- Node metrics
- Pod logs

**View AKS Metrics:**
```bash
# Get cluster metrics
az monitor metrics list \
  --resource /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.ContainerService/managedClusters/<aks> \
  --metric "node_cpu_usage_percentage"

# Get pod metrics via kubectl
kubectl top pods
kubectl top nodes
```

**Key Metrics:**
- Node CPU usage
- Node memory usage
- Pod count
- Container restarts
- Network I/O

### APIM Monitoring

**Metrics:**
- Gateway requests
- Backend requests
- Capacity utilization
- Request latency
- Failed requests

**View APIM Metrics:**
```bash
# Get request metrics
az monitor metrics list \
  --resource /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.ApiManagement/service/<apim> \
  --metric "Requests"

# Get capacity
az monitor metrics list \
  --resource /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.ApiManagement/service/<apim> \
  --metric "Capacity"
```

**APIM Specific Queries:**
```kusto
ApiManagementGatewayLogs
| where TimeGenerated > ago(1h)
| where ResponseCode >= 400
| project TimeGenerated, Method, Url, ResponseCode, BackendResponseCode
| order by TimeGenerated desc
```

### Key Vault Monitoring

**Metrics:**
- Service API hits
- Service API latency
- Availability

**View Key Vault Metrics:**
```bash
az monitor metrics list \
  --resource /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<kv> \
  --metric "ServiceApiHit"
```

## Logging

### Application Logs

**View Application Logs:**
```bash
# View pod logs
kubectl logs -l app=oauth-obo-client --tail=100

# Follow logs
kubectl logs -l app=oauth-obo-client -f

# View logs from previous pod instance
kubectl logs -l app=oauth-obo-client --previous

# View logs for specific container
kubectl logs <pod-name> -c <container-name>
```

**Log Levels:**
- **Trace**: Very detailed debugging information
- **Debug**: Detailed debugging information
- **Information**: Normal application flow
- **Warning**: Unusual but expected events
- **Error**: Errors requiring attention
- **Critical**: Application failures

**Key Log Patterns:**

**Token Acquisition:**
```
info: client.Services.WorkloadIdentityTokenService[0]
      Acquiring token for user using workload identity (AKS production mode)
```

**API Calls:**
```
info: client.Services.ApiClient[0]
      Acquiring access token for scope: api://xxx/access_as_user
info: client.Services.ApiClient[0]
      Access token acquired, calling APIM at https://...
info: client.Services.ApiClient[0]
      APIM call successful
```

**Errors:**
```
error: client.Services.ApiClient[0]
      Failed to call APIM
      System.Exception: ...
```

### APIM Logs

**Enable APIM Logging:**
```bash
# Create diagnostic setting
az monitor diagnostic-settings create \
  --name apim-diagnostics \
  --resource /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.ApiManagement/service/<apim> \
  --logs '[{"category":"GatewayLogs","enabled":true}]' \
  --workspace /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<workspace>
```

**Query APIM Logs:**
```kusto
ApiManagementGatewayLogs
| where TimeGenerated > ago(1h)
| project TimeGenerated, Method, Url, BackendUrl, ResponseCode, BackendResponseCode, TotalTime
| order by TimeGenerated desc
```

**Policy Execution Logs:**
```kusto
ApiManagementGatewayLogs
| where TimeGenerated > ago(1h)
| where IsRequestSuccess == false
| extend Reason = parse_json(LastErrorReason)
| project TimeGenerated, Method, Url, ResponseCode, Reason
```

### AKS Logs

**Container Logs:**
```bash
# All container logs
kubectl logs --all-containers=true -l app=oauth-obo-client

# Logs from all pods matching label
kubectl logs -l app=oauth-obo-client --prefix=true
```

**Event Logs:**
```bash
# Recent events
kubectl get events --sort-by='.lastTimestamp'

# Events for specific pod
kubectl describe pod <pod-name>
```

### Centralized Logging

**Log Analytics Queries:**
```kusto
// Container logs
ContainerLog
| where TimeGenerated > ago(1h)
| where ContainerName contains "oauth-obo"
| project TimeGenerated, LogEntry, ContainerName
| order by TimeGenerated desc

// Container performance
Perf
| where TimeGenerated > ago(1h)
| where ObjectName == "K8SContainer"
| summarize avg(CounterValue) by CounterName, bin(TimeGenerated, 5m)
```

## Alerting

### Recommended Alerts

#### Application Alerts

**High Error Rate:**
```kusto
requests
| where timestamp > ago(5m)
| summarize total = count(), failures = countif(success == false)
| extend error_rate = todouble(failures) / total
| where error_rate > 0.05  // Alert if >5% errors
```

**Slow Requests:**
```kusto
requests
| where timestamp > ago(5m)
| where duration > 2000  // Over 2 seconds
| summarize slow_requests = count()
| where slow_requests > 10  // Alert if >10 slow requests
```

**Token Acquisition Failures:**
```kusto
traces
| where timestamp > ago(5m)
| where message contains "Failed to acquire token"
| summarize count()
| where count_ > 5  // Alert if >5 failures
```

#### Infrastructure Alerts

**Pod Restarts:**
```bash
# Create alert for pod restarts
az monitor metrics alert create \
  --name pod-restart-alert \
  --resource-group <rg> \
  --scopes /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.ContainerService/managedClusters/<aks> \
  --condition "avg Pod Status == Restarting" \
  --description "Alert when pods restart frequently"
```

**High CPU Usage:**
```bash
az monitor metrics alert create \
  --name high-cpu-alert \
  --resource-group <rg> \
  --scopes /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.ContainerService/managedClusters/<aks> \
  --condition "avg node_cpu_usage_percentage > 80" \
  --description "Alert when node CPU exceeds 80%"
```

**APIM Capacity:**
```bash
az monitor metrics alert create \
  --name apim-capacity-alert \
  --resource-group <rg> \
  --scopes /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.ApiManagement/service/<apim> \
  --condition "avg Capacity > 80" \
  --description "Alert when APIM capacity exceeds 80%"
```

### Alert Actions

**Action Group:**
```bash
# Create action group for email notifications
az monitor action-group create \
  --name oauth-obo-alerts \
  --resource-group <rg> \
  --short-name oauthOBO \
  --email-receiver email admin@example.com
```

## Performance Metrics

### Application Performance

**Key Metrics:**
- **Response Time**: 200-500ms typical
- **Token Acquisition**: 1-3s first time, <100ms cached
- **APIM Processing**: 50-200ms
- **Backend Response**: 100-300ms

**Monitor Performance:**
```bash
# View response times
kubectl logs -l app=oauth-obo-client | grep "APIM call"

# Analyze with Application Insights
# Navigate to Performance blade in Azure Portal
```

### Resource Utilization

**Pod Resources:**
```bash
# Current usage
kubectl top pods -l app=oauth-obo-client

# Resource requests/limits
kubectl describe pod -l app=oauth-obo-client | grep -A 5 Limits
```

**Expected Values:**
- CPU: 0.1-0.2 cores under load
- Memory: 100-200MB
- Network: Minimal (<10Mbps)

### Capacity Planning

**Scaling Indicators:**
- CPU usage consistently >70%
- Memory usage consistently >80%
- Response time >1 second
- High pod restart rate

**Scale Application:**
```bash
# Scale deployment
kubectl scale deployment oauth-obo-client --replicas=3

# Or update Helm chart
helm upgrade oauth-obo-client ./helm \
  --set replicaCount=3
```

## Troubleshooting Operations

### Common Issues

#### Issue: High Memory Usage

**Diagnose:**
```bash
# Check memory usage
kubectl top pods -l app=oauth-obo-client

# Check for memory leaks
kubectl logs -l app=oauth-obo-client | grep -i "out of memory"
```

**Solutions:**
- Increase memory limits
- Check for memory leaks in code
- Verify token cache isn't growing indefinitely

#### Issue: Slow Response Times

**Diagnose:**
```bash
# Check pod performance
kubectl top pods -l app=oauth-obo-client

# Check APIM response times
az monitor metrics list \
  --resource <apim-resource-id> \
  --metric "BackendDuration"
```

**Solutions:**
- Scale application horizontally
- Optimize token caching
- Check network latency
- Review APIM policy complexity

#### Issue: Authentication Failures

**Diagnose:**
```bash
# Check application logs
kubectl logs -l app=oauth-obo-client | grep -i "authentication\|token"

# Check workload identity configuration
kubectl get serviceaccount oauth-obo-client-sa -o yaml
```

**Solutions:**
- Verify workload identity annotations
- Check federated credential configuration
- Validate Azure AD app registration
- Ensure proper RBAC assignments

### Health Checks

**Application Health:**
```bash
# Check pod status
kubectl get pods -l app=oauth-obo-client

# Check readiness
kubectl describe pod -l app=oauth-obo-client | grep -A 5 Readiness

# Test endpoint
curl http://<app-url>/
```

**Infrastructure Health:**
```bash
# AKS cluster health
az aks show \
  --resource-group <rg> \
  --name <aks> \
  --query "{status:provisioningState,health:powerState.code}"

# APIM health
az apim show \
  --resource-group <rg> \
  --name <apim> \
  --query "{status:provisioningState}"
```

## Best Practices

### Monitoring Best Practices

✅ **Do:**
- Monitor all critical metrics
- Set up alerts for failures
- Review logs regularly
- Track performance trends
- Use dashboards for visualization

❌ **Don't:**
- Ignore warning signs
- Over-alert (alert fatigue)
- Log sensitive information
- Disable monitoring in production
- Forget to test alerts

### Logging Best Practices

✅ **Do:**
- Use structured logging
- Include correlation IDs
- Log errors with context
- Set appropriate log levels
- Centralize logs

❌ **Don't:**
- Log access tokens or secrets
- Log personally identifiable information
- Use console logging in production
- Ignore log storage costs
- Over-log in hot paths

### Operational Best Practices

✅ **Do:**
- Automate routine tasks
- Document operational procedures
- Test disaster recovery
- Maintain runbooks
- Review metrics regularly

❌ **Don't:**
- Make changes without testing
- Ignore capacity planning
- Skip documentation
- Forget to backup configurations
- Neglect security updates

## Related Documentation

- [Troubleshooting Guide](../troubleshooting.md)
- [Architecture Overview](../architecture/overview.md)
- [Deployment Overview](../deployment/overview.md)
- [Developer Guide](../development/guide.md)
