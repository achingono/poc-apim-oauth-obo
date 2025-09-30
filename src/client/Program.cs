using Microsoft.AspNetCore.Authentication.OpenIdConnect;
using Microsoft.Identity.Web;
using Microsoft.Identity.Web.UI;
using OAuthOboClient.Services;

var builder = WebApplication.CreateBuilder(args);

// Determine environment - check ENVIRONMENT variable
var environment = builder.Configuration["ENVIRONMENT"] ?? "Development";
var isProduction = environment.Equals("Production", StringComparison.OrdinalIgnoreCase);

// Add session support
builder.Services.AddDistributedMemoryCache();
builder.Services.AddSession(options =>
{
    options.IdleTimeout = TimeSpan.FromMinutes(30);
    options.Cookie.HttpOnly = true;
    options.Cookie.IsEssential = true;
});

// Add authentication services
var apiAppId = builder.Configuration["API_APP_ID"];
var oauthScope = builder.Configuration["OAUTH_SCOPE"] ?? "access_as_user";
var downstreamApiScopes = new[] { $"api://{apiAppId}/{oauthScope}" };

builder.Services.AddAuthentication(OpenIdConnectDefaults.AuthenticationScheme)
    .AddMicrosoftIdentityWebApp(options =>
    {
        builder.Configuration.Bind("AzureAd", options);
        options.ClientId = builder.Configuration["AZURE_CLIENT_ID"];
        options.TenantId = builder.Configuration["AZURE_TENANT_ID"];
        options.Instance = "https://login.microsoftonline.com/";
        
        if (!isProduction)
        {
            options.ClientSecret = builder.Configuration["AZURE_CLIENT_SECRET"];
        }
    })
    .EnableTokenAcquisitionToCallDownstreamApi(downstreamApiScopes)
    .AddInMemoryTokenCaches();

// Register token acquisition service based on environment
if (isProduction)
{
    builder.Services.AddSingleton<ITokenAcquisitionService, WorkloadIdentityTokenService>();
    builder.Logging.AddConsole().SetMinimumLevel(LogLevel.Information);
    Console.WriteLine("Using WorkloadIdentityTokenService for AKS production environment");
}
else
{
    builder.Services.AddSingleton<ITokenAcquisitionService, ClientSecretTokenService>();
    builder.Logging.AddConsole().SetMinimumLevel(LogLevel.Information);
    Console.WriteLine("Using ClientSecretTokenService for local development environment");
}

// Register API client
builder.Services.AddHttpClient<ApiClient>();

builder.Services.AddRazorPages()
    .AddMicrosoftIdentityUI();

builder.Services.AddAuthorization(options =>
{
    options.FallbackPolicy = options.DefaultPolicy;
});

var app = builder.Build();

// Configure the HTTP request pipeline.
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error");
    app.UseHsts();
}

app.UseHttpsRedirection();

app.UseRouting();

app.UseSession();

app.UseAuthentication();
app.UseAuthorization();

app.MapStaticAssets();
app.MapRazorPages()
   .WithStaticAssets();

app.Run();
