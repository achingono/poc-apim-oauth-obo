namespace client.Services;

public interface ITokenAcquisitionService
{
    Task<string> AcquireTokenForUserAsync(string[] scopes);
    Task<string> AcquireTokenOnBehalfOfAsync(string userToken, string[] scopes);
}
