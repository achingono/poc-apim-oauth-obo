using Azure.Core;
using Azure.Identity;
using Microsoft.Identity.Client;

namespace client.Services;

public class WorkloadIdentityTokenService : ITokenAcquisitionService
{
    private readonly IConfidentialClientApplication _confidentialClientApp;
    private readonly DefaultAzureCredential _azureCredential;
    private readonly ILogger<WorkloadIdentityTokenService> _logger;
    private readonly string _apiScope;

    public WorkloadIdentityTokenService(
        IConfiguration configuration,
        ILogger<WorkloadIdentityTokenService> logger)
    {
        _logger = logger;
        
        var clientId = configuration["AZURE_CLIENT_ID"] 
            ?? throw new InvalidOperationException("AZURE_CLIENT_ID is not configured");
        var tenantId = configuration["AZURE_TENANT_ID"] 
            ?? throw new InvalidOperationException("AZURE_TENANT_ID is not configured");
        var apiAppId = configuration["API_APP_ID"] 
            ?? throw new InvalidOperationException("API_APP_ID is not configured");
        var oauthScope = configuration["OAUTH_SCOPE"] 
            ?? throw new InvalidOperationException("OAUTH_SCOPE is not configured");

        _apiScope = $"api://{apiAppId}/{oauthScope}";

        var authority = $"https://login.microsoftonline.com/{tenantId}";

        _azureCredential = new DefaultAzureCredential(new DefaultAzureCredentialOptions
        {
            ManagedIdentityClientId = clientId
        });

        _confidentialClientApp = ConfidentialClientApplicationBuilder
            .Create(clientId)
            .WithAuthority(new Uri(authority))
            .WithClientAssertion(async (AssertionRequestOptions options) =>
            {
                // For workload identity, we need to get a token for the Azure AD token exchange scope
                var tokenRequestContext = new TokenRequestContext(new[] { "api://AzureADTokenExchange/.default" });
                var token = await _azureCredential.GetTokenAsync(tokenRequestContext, options.CancellationToken);
                return token.Token;
            })
            .Build();

        _logger.LogInformation("WorkloadIdentityTokenService initialized for AKS production environment");
    }

    public async Task<string> AcquireTokenForUserAsync(string[] scopes)
    {
        try
        {
            _logger.LogInformation("Acquiring token for user using workload identity (AKS production mode)");
            
            var tokenRequestContext = new TokenRequestContext(scopes);
            var token = await _azureCredential.GetTokenAsync(tokenRequestContext);

            return token.Token;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to acquire token for user using workload identity");
            throw new InvalidOperationException(
                "Failed to acquire token using workload identity. Ensure AKS workload identity is properly configured.", ex);
        }
    }

    public async Task<string> AcquireTokenOnBehalfOfAsync(string userToken, string[] scopes)
    {
        try
        {
            _logger.LogInformation("Acquiring token on behalf of user using workload identity (AKS production mode)");
            
            var userAssertion = new UserAssertion(userToken);
            var result = await _confidentialClientApp
                .AcquireTokenOnBehalfOf(scopes, userAssertion)
                .ExecuteAsync();

            return result.AccessToken;
        }
        catch (MsalException ex)
        {
            _logger.LogError(ex, "Failed to acquire OBO token using workload identity");
            throw;
        }
    }
}
