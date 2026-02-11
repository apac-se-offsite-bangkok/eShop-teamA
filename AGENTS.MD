# eShop Agent Context Engineering Guide

This document provides essential context for AI agents working with the eShop reference application codebase.

## Repository Overview

eShop is a .NET 9-based microservices e-commerce reference application built with .NET Aspire. The application demonstrates cloud-native patterns including service orchestration, event-driven architecture, and container-based deployment.

## Project Organization

### Source Code Structure (`/src`)

The application follows a microservices architecture with the following components:

**Core Services (APIs)**
- `Basket.API` - Shopping basket management service using gRPC
- `Catalog.API` - Product catalog management with versioned REST APIs (v1.0, v2.0)
- `Ordering.API` - Order processing and management
- `Identity.API` - Authentication and user identity management
- `Webhooks.API` - Webhook notification system

**Background Processors**
- `OrderProcessor` - Asynchronous order processing worker
- `PaymentProcessor` - Payment handling background service

**Web Applications**
- `WebApp` - Primary customer-facing Blazor web application
- `WebAppComponents` - Reusable Blazor component library
- `WebhookClient` - Webhook consumer application
- `HybridApp` - .NET MAUI cross-platform mobile application
- `ClientApp` - Mobile client application

**Infrastructure & Shared**
- `eShop.AppHost` - .NET Aspire orchestration host (primary startup project)
- `eShop.ServiceDefaults` - Common service configuration and observability setup
- `EventBus` - Event bus abstraction layer
- `EventBusRabbitMQ` - RabbitMQ implementation of event bus
- `IntegrationEventLogEF` - Entity Framework-based integration event logging
- `Ordering.Domain` - DDD domain model for ordering
- `Ordering.Infrastructure` - Data access and persistence for ordering
- `Shared` - Cross-cutting shared utilities

### Test Organization (`/tests`)

**Unit Tests**
- `Basket.UnitTests` - Isolated gRPC service tests using NSubstitute mocking
- `Ordering.UnitTests` - Domain logic and business rule validation
- `ClientApp.UnitTests` - Mobile client unit tests

**Functional Tests**
- `Catalog.FunctionalTests` - API integration tests using WebApplicationFactory
- `Ordering.FunctionalTests` - API integration tests with middleware customization

**End-to-End Tests** (`/e2e`)
- Playwright-based browser automation tests
- Tests: `AddItemTest.spec.ts`, `BrowseItemTest.spec.ts`, `RemoveItemTest.spec.ts`
- Authentication setup: `login.setup.ts`

## Test Patterns and Frameworks

### Unit Testing Framework: MSTest SDK

The repository uses MSTest.Sdk 4.0.2 configured via `global.json` with Microsoft.Testing.Platform as the runner.

**Key Characteristics:**
- Test classes decorated with `[TestClass]`
- Test methods decorated with `[TestMethod]`
- Uses `Assert.` methods (IsInstanceOfType, HasCount, IsEmpty, etc.)
- NSubstitute for mocking dependencies (`Substitute.For<IInterface>()`)

**Example Pattern from Basket.UnitTests:**
```csharp
[TestMethod]
public async Task MethodName_Scenario_ExpectedBehavior()
{
    // Arrange
    var mockDependency = Substitute.For<IDependency>();
    mockDependency.Method("input").Returns(expectedValue);
    var service = new ServiceUnderTest(mockDependency, logger);
    
    // Act
    var result = await service.MethodToTest(parameters);
    
    // Assert
    Assert.IsInstanceOfType<ExpectedType>(result);
}
```

### Functional Testing Pattern

Functional tests use `WebApplicationFactory<Program>` to spin up test servers with real dependencies running in Docker containers via .NET Aspire.

**Requirements:**
- Docker must be running before executing functional tests
- Tests implement `IClassFixture<CustomApiFixture>` for shared test context
- API versioning tested across multiple versions using `ApiVersion` parameter
- Uses xUnit's `[Theory]` and `[InlineData]` for parameterized tests

**Example Pattern from Catalog.FunctionalTests:**
```csharp
[Theory]
[InlineData(1.0)]
[InlineData(2.0)]
public async Task TestName_WithApiVersion(double version)
{
    var httpClient = CreateHttpClient(new ApiVersion(version));
    var response = await httpClient.GetAsync("/api/endpoint", TestContext.Current.CancellationToken);
    response.EnsureSuccessStatusCode();
}
```

### End-to-End Testing with Playwright

Configuration: `playwright.config.ts`
- Base URL: `http://localhost:5045` (WebApp)
- Test directory: `./e2e`
- Uses Desktop Chrome device emulation
- Separate projects for authenticated vs. unauthenticated tests
- Auto-starts application via webServer configuration

**Authentication Flow:**
- Setup tests create authenticated session state
- Stored in `playwright/.auth/user.json`
- Authenticated tests depend on setup project completion

**Test Pattern:**
```typescript
test('descriptive test name', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('link', { name: 'Element Name' }).click();
  await expect(page.getByRole('heading', { name: 'Expected Heading' })).toBeVisible();
});
```

## Build Commands and Workflows

### Local Development

**Prerequisites:**
- .NET SDK 10.0.100+ (specified in `global.json`)
- Docker Desktop running
- Node.js LTS (for e2e tests)

**Primary Startup:**
```bash
dotnet run --project src/eShop.AppHost/eShop.AppHost.csproj
```
Access the Aspire dashboard at the URL shown in console output (typically http://localhost:19888/login?t=token)

**Building the Solution:**
```bash
# Build web-focused solution filter
dotnet build eShop.Web.slnf

# Build complete solution
dotnet build eShop.slnx
```

**Running Tests:**
```bash
# Run all tests
dotnet test --solution eShop.Web.slnf

# Run specific test project
dotnet test tests/Basket.UnitTests/Basket.UnitTests.csproj

# Run with detailed output
dotnet test --solution eShop.Web.slnf --no-build --output detailed
```

**E2E Testing:**
```bash
# Install dependencies
npm ci

# Install Playwright browsers
npx playwright install chromium

# Run e2e tests (auto-starts application)
npx playwright test

# Environment variables for e2e tests
export ESHOP_USE_HTTP_ENDPOINTS=1
export USERNAME1=bob
export PASSWORD=Pass123$
```

### Continuous Integration

**GitHub Actions Workflows** (`.github/workflows/`)

1. **pr-validation.yml** - Pull Request validation
   - Triggers: PR and push to main (excluding .md files and ClientApp)
   - Steps: checkout → setup .NET → build → test
   - Command: `dotnet build eShop.Web.slnf && dotnet test --solution eShop.Web.slnf`

2. **playwright.yml** - E2E test automation
   - Triggers: PR and push to main
   - Runtime: Ubuntu with 60-minute timeout
   - Installs: .NET 10.0.x preview, Node.js LTS, Playwright Chromium
   - Sets up HTTPS dev certificates
   - Runs: `npx playwright test`
   - Artifacts: playwright-report retained 30 days

3. **pr-validation-maui.yml** - MAUI client validation
   - Specific to mobile application changes

4. **markdownlint.yml** - Documentation linting
   - Validates markdown files against `.markdownlint.json` rules

**Azure Pipelines** (`ci.yml`)
- Uses 1ES Pipeline Templates
- Triggers on main branch
- Windows build on VS2019 with .NET from global.json
- Command: `dotnet build eShop.Web.slnf`

### Solution Files

- `eShop.slnx` - Complete solution including all 19 projects
- `eShop.Web.slnf` - Filtered solution excluding MAUI/mobile projects (faster builds)

### Package Management

- Central Package Management enabled via `Directory.Packages.props`
- Custom NuGet sources configured in `nuget.config`
- MSBuild customizations: `Directory.Build.props` and `Directory.Build.targets`

## Key Configuration Files

- `global.json` - SDK version (10.0.100), test runner (Microsoft.Testing.Platform), MSTest.Sdk version
- `.editorconfig` - Code style and formatting rules
- `playwright.config.ts` - E2E test configuration
- `.spectral.yml` - OpenAPI/API linting rules
- `.markdownlint.json` - Markdown documentation standards

## Development Tools Integration

**Visual Studio 2022 (Windows):**
1. Open `eShop.Web.slnf`
2. Set `eShop.AppHost` as startup project
3. Press F5 or Ctrl-F5 to run

**VS Code / Command Line:**
1. Use `dotnet run --project src/eShop.AppHost/eShop.AppHost.csproj`
2. Install recommended extensions for C# Dev Kit

## Important Notes for AI Agents

1. **Always start Docker** before running functional tests or the application
2. **Use solution filters** (.slnf) for faster iteration during development
3. **Functional tests modify state** - The catalog has 101 seeded items plus items added by tests
4. **API versioning is critical** - Catalog API supports both v1.0 and v2.0
5. **Cancellation token usage** - Access via `TestContext.Current.CancellationToken` in functional tests
6. **Aspire orchestration** - The AppHost project coordinates all services, databases, and message brokers
7. **E2E test authentication** - Some tests require login setup to run, managed via test dependencies
8. **HTTP-only mode** - E2E tests use `ESHOP_USE_HTTP_ENDPOINTS=1` to avoid HTTPS certificate issues in CI

## Common Development Workflows

**Adding a new unit test:**
1. Add test method with `[TestMethod]` attribute
2. Follow Arrange-Act-Assert pattern
3. Use descriptive name: `MethodName_Scenario_ExpectedOutcome`
4. Run: `dotnet test tests/[ProjectName]/[ProjectName].csproj`

**Adding a new API endpoint:**
1. Implement in appropriate API project
2. Add functional test in corresponding FunctionalTests project
3. Test both API versions if in Catalog.API
4. Update OpenAPI documentation if applicable

**Debugging integration issues:**
1. Launch AppHost project to start Aspire dashboard
2. View logs, traces, and metrics in dashboard
3. Check container health and resource allocation
4. Verify RabbitMQ message flow for event-driven scenarios

## Azure Deployment

Use Azure Developer CLI for cloud deployment:
```bash
azd auth login
azd init  # Select .NET Aspire project
azd up    # Provision and deploy
```

Refer to README.md for detailed Azure deployment instructions and OpenAI integration configuration.
