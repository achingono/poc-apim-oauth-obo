using Microsoft.AspNetCore.Authentication.OpenIdConnect;
using Microsoft.Identity.Web;
using Microsoft.Identity.Web.UI;
using client.Services;
using Azure.Identity;

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
        builder.Configuration.GetSection("AzureAd").Bind(options);
    })
    .EnableTokenAcquisitionToCallDownstreamApi(downstreamApiScopes)
    .AddInMemoryTokenCaches();


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