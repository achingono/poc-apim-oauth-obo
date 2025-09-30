using Microsoft.Identity.Client;
using Microsoft.Identity.Web;

namespace client.Services;

public class ClientSecretTokenService : ITokenAcquisitionService
{
    private readonly IConfidentialClientApplication _confidentialClientApp;
    private readonly ILogger<ClientSecretTokenService> _logger;
    private readonly string _apiScope;

    public ClientSecretTokenService(
        IConfiguration configuration,
        ILogger<ClientSecretTokenService> logger)
    {
        _logger = logger;
        
        var clientId = configuration["AZURE_CLIENT_ID"] 
            ?? throw new InvalidOperationException("AZURE_CLIENT_ID is not configured");
        var clientSecret = configuration["AZURE_CLIENT_SECRET"] 
            ?? throw new InvalidOperationException("AZURE_CLIENT_SECRET is not configured");
        var tenantId = configuration["AZURE_TENANT_ID"] 
            ?? throw new InvalidOperationException("AZURE_TENANT_ID is not configured");
        var apiAppId = configuration["API_APP_ID"] 
            ?? throw new InvalidOperationException("API_APP_ID is not configured");
        var oauthScope = configuration["OAUTH_SCOPE"] 
            ?? throw new InvalidOperationException("OAUTH_SCOPE is not configured");

        _apiScope = $"api://{apiAppId}/{oauthScope}";

        var authority = $"https://login.microsoftonline.com/{tenantId}";

        _confidentialClientApp = ConfidentialClientApplicationBuilder
            .Create(clientId)
            .WithClientSecret(clientSecret)
            .WithAuthority(new Uri(authority))
            .Build();

        _logger.LogInformation("ClientSecretTokenService initialized for local development");
    }

    public async Task<string> AcquireTokenForUserAsync(string[] scopes)
    {
        try
        {
            _logger.LogInformation("Acquiring token for user using client secret (local development mode)");
            
            var result = await _confidentialClientApp
                .AcquireTokenForClient(scopes)
                .ExecuteAsync();

            return result.AccessToken;
        }
        catch (MsalException ex)
        {
            _logger.LogError(ex, "Failed to acquire token for user");
            throw;
        }
    }

    public async Task<string> AcquireTokenOnBehalfOfAsync(string userToken, string[] scopes)
    {
        try
        {
            _logger.LogInformation("Acquiring token on behalf of user using client secret (local development mode)");
            
            var userAssertion = new UserAssertion(userToken);
            var result = await _confidentialClientApp
                .AcquireTokenOnBehalfOf(scopes, userAssertion)
                .ExecuteAsync();

            return result.AccessToken;
        }
        catch (MsalException ex)
        {
            _logger.LogError(ex, "Failed to acquire OBO token");
            throw;
        }
    }
}
