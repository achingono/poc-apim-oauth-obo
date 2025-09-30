# Build stage
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src

# Copy csproj and restore dependencies
COPY ["OAuthOboClient.csproj", "./"]
RUN dotnet restore "OAuthOboClient.csproj"

# Copy everything else and build
COPY . .
RUN dotnet build "OAuthOboClient.csproj" -c Release -o /app/build

# Publish stage
FROM build AS publish
RUN dotnet publish "OAuthOboClient.csproj" -c Release -o /app/publish /p:UseAppHost=false

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS final
WORKDIR /app
EXPOSE 8080
EXPOSE 8081

COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "OAuthOboClient.dll"]
