using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using OAuthOboClient.Services;

namespace OAuthOboClient.Pages;

[Authorize]
public class IndexModel : PageModel
{
    private readonly ILogger<IndexModel> _logger;
    private readonly ApiClient _apiClient;

    [BindProperty]
    public string? UserMessage { get; set; }

    public string? ApiResponse { get; set; }

    public List<ChatMessage> ChatHistory { get; set; } = new();

    public IndexModel(ILogger<IndexModel> logger, ApiClient apiClient)
    {
        _logger = logger;
        _apiClient = apiClient;
    }

    public void OnGet()
    {
        LoadChatHistory();
    }

    public async Task<IActionResult> OnPostAsync()
    {
        if (string.IsNullOrWhiteSpace(UserMessage))
        {
            return Page();
        }

        LoadChatHistory();

        _logger.LogInformation("User message: {Message}", UserMessage);

        ChatHistory.Add(new ChatMessage
        {
            Timestamp = DateTime.UtcNow,
            IsUser = true,
            Message = UserMessage
        });

        try
        {
            ApiResponse = await _apiClient.CallApimAsync(UserMessage);
            
            ChatHistory.Add(new ChatMessage
            {
                Timestamp = DateTime.UtcNow,
                IsUser = false,
                Message = ApiResponse
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error calling API");
            ApiResponse = $"Error: {ex.Message}";
            
            ChatHistory.Add(new ChatMessage
            {
                Timestamp = DateTime.UtcNow,
                IsUser = false,
                Message = ApiResponse
            });
        }

        SaveChatHistory();
        UserMessage = string.Empty;

        return Page();
    }

    public IActionResult OnPostClear()
    {
        HttpContext.Session.Remove("ChatHistory");
        ChatHistory.Clear();
        return RedirectToPage();
    }

    private void LoadChatHistory()
    {
        var json = HttpContext.Session.GetString("ChatHistory");
        if (!string.IsNullOrEmpty(json))
        {
            ChatHistory = System.Text.Json.JsonSerializer.Deserialize<List<ChatMessage>>(json) ?? new();
        }
    }

    private void SaveChatHistory()
    {
        var json = System.Text.Json.JsonSerializer.Serialize(ChatHistory);
        HttpContext.Session.SetString("ChatHistory", json);
    }
}

public class ChatMessage
{
    public DateTime Timestamp { get; set; }
    public bool IsUser { get; set; }
    public string Message { get; set; } = string.Empty;
}
