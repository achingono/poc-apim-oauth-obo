# Build stage
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src

# Copy csproj and restore dependencies
COPY ["client.csproj", "./"]
RUN dotnet restore "client.csproj"

# Copy everything else and build
COPY . .
RUN dotnet build "client.csproj" -c Release -o /app/build

# Publish stage
FROM build AS publish
RUN dotnet publish "client.csproj" -c Release -o /app/publish /p:UseAppHost=false

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS final
WORKDIR /app
EXPOSE 8080
EXPOSE 8081

COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "client.dll"]
