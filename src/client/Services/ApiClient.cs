using System.Text.Json;
using Microsoft.Identity.Web;

namespace client.Services;

public class ApiClient
{
    private readonly HttpClient _httpClient;
    private readonly ITokenAcquisition _tokenAcquisition;
    private readonly IConfiguration _configuration;
    private readonly ILogger<ApiClient> _logger;

    public ApiClient(
        HttpClient httpClient,
        ITokenAcquisition tokenAcquisition,
        IConfiguration configuration,
        ILogger<ApiClient> logger)
    {
        _httpClient = httpClient;
        _tokenAcquisition = tokenAcquisition;
        _configuration = configuration;
        _logger = logger;
    }

    public async Task<string> CallApimAsync(string message)
    {
        try
        {
            var apimBaseUrl = _configuration["APIM_BASE_URL"] 
                ?? throw new InvalidOperationException("APIM_BASE_URL is not configured");
            var apiAppId = _configuration["API_APP_ID"] 
                ?? throw new InvalidOperationException("API_APP_ID is not configured");
            var oauthScope = _configuration["OAUTH_SCOPE"] 
                ?? throw new InvalidOperationException("OAUTH_SCOPE is not configured");

            var scope = $"api://{apiAppId}/{oauthScope}";
            _logger.LogInformation("Acquiring access token for scope: {Scope}", scope);

            var accessToken = await _tokenAcquisition.GetAccessTokenForUserAsync(new[] { scope });
            
            _logger.LogInformation("Access token acquired, calling APIM at {BaseUrl}", apimBaseUrl);

            var request = new HttpRequestMessage(HttpMethod.Get, $"{apimBaseUrl}/test");
            request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", accessToken);
            request.Headers.Add("X-User-Message", message);

            var response = await _httpClient.SendAsync(request);
            
            if (response.IsSuccessStatusCode)
            {
                var content = await response.Content.ReadAsStringAsync();
                _logger.LogInformation("APIM call successful");
                
                var jsonDocument = JsonDocument.Parse(content);
                var formattedJson = JsonSerializer.Serialize(jsonDocument, new JsonSerializerOptions 
                { 
                    WriteIndented = true 
                });
                
                return formattedJson;
            }
            else
            {
                var errorContent = await response.Content.ReadAsStringAsync();
                _logger.LogError("APIM call failed with status {StatusCode}: {Error}", 
                    response.StatusCode, errorContent);
                return $"Error: {response.StatusCode}\n{errorContent}";
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to call APIM");
            return $"Exception: {ex.Message}";
        }
    }
}
