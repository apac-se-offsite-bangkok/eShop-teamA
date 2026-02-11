# eShop Copilot Instructions

## Exclude Patterns

The following file patterns should be excluded from code assistance as they are documentation or configuration files that don't require code generation:

- `**/*.md` — Markdown documentation files
- `**/README.md` — Project readme files
- `**/CONTRIBUTING.md` — Contribution guidelines
- `**/CODE-OF-CONDUCT.md` — Code of conduct
- `**/.github/ISSUE_TEMPLATE/**` — GitHub issue templates
- `**/LICENSE` — License files
- `**/*.txt` — Text documentation files

## Code Review Guidance

When reviewing code changes in this repository, focus on the following key areas:

### Architecture & Design
- Verify that service-to-service communication uses the correct pattern (integration events for async, HTTP/gRPC for sync)
- Ensure new endpoints follow the Minimal APIs pattern with proper API versioning
- Check that DDD patterns are correctly applied in Ordering.API (aggregates, value objects, domain events)
- Validate that commands use the CQRS pattern with proper separation from queries

### Code Quality
- Confirm all new classes are `sealed` by default unless inheritance is required
- Verify primary constructors are used for dependency injection
- Check that file-scoped namespaces are used consistently
- Ensure `GlobalUsings.cs` is updated for new common imports
- Validate that DI extension methods are in `Microsoft.Extensions.Hosting` namespace

### Data & Persistence
- Review EF Core entity configurations are in separate `IEntityTypeConfiguration<T>` classes
- Verify migrations are created and will run automatically via `AddMigration<TContext, TSeed>()`
- Check that database schema conventions are followed (e.g., `ordering` schema for Ordering service)

### Testing
- Ensure unit tests use MSTest with `[TestClass]` and `[TestMethod]` attributes
- Verify functional tests use xUnit with proper fixture patterns
- Check that test names follow the correct convention (snake_case for unit tests, PascalCase for functional tests)
- Validate AAA (Arrange/Act/Assert) comments are present in test methods
- Confirm NSubstitute is used correctly for mocking (not in functional tests)

### Security & Best Practices
- Verify no secrets are committed to source code
- Check that package versions are not specified in individual `.csproj` files (use `Directory.Packages.props`)
- Ensure `TreatWarningsAsErrors` compliance - no new warnings introduced
- Validate proper error handling and logging patterns

### Integration Events
- Confirm events inherit from `IntegrationEvent` base class
- Verify subscriptions are registered in `AddApplicationServices()` via `AddSubscription<TEvent, THandler>()`
- Check that Catalog.API uses the outbox pattern for transactional consistency

### OpenTelemetry & Observability
- Ensure all services call `AddServiceDefaults()` in startup
- Verify health check endpoints are mapped via `MapDefaultEndpoints()`

## Architecture Overview

This is a .NET Aspire-orchestrated e-commerce reference app ("AdventureWorks") targeting .NET 10. The AppHost (`src/eShop.AppHost/Program.cs`) wires all services, infrastructure (PostgreSQL/pgvector, Redis, RabbitMQ), and reverse proxies (YARP mobile BFF). Services communicate asynchronously via integration events on RabbitMQ and synchronously via HTTP/gRPC.

**Services and their roles:**
| Service | Style | Data Store | Key Pattern |
|---|---|---|---|
| Catalog.API | Minimal APIs + thin service layer | PostgreSQL + pgvector | Direct EF Core queries, no MediatR |
| Ordering.API | Minimal APIs + CQRS | PostgreSQL | Full DDD + MediatR + FluentValidation |
| Basket.API | **gRPC only** (no HTTP APIs) | Redis | Protobuf contracts in `Proto/` |
| Identity.API | Duende IdentityServer | PostgreSQL | OAuth2/OIDC provider for all services |
| WebApp | Blazor Server (interactive) | — | BFF consuming all backend APIs |
| OrderProcessor | Background worker | — | Subscribes to integration events |
| PaymentProcessor | Background worker | — | Subscribes to integration events |

## Build & Run

```bash
# Run the full app (requires Docker for PostgreSQL, Redis, RabbitMQ)
dotnet run --project src/eShop.AppHost/eShop.AppHost.csproj

# Build web solution (excludes MAUI mobile apps)
dotnet build eShop.Web.slnf

# Run tests (Docker required for functional tests - they spin up real containers)
dotnet test eShop.Web.slnf

# E2E tests (Playwright, needs running app on localhost:5045)
npx playwright test
```

- SDK version pinned in `global.json` (.NET 10, `allowPrerelease: true`)
- `TreatWarningsAsErrors` is enabled globally in `Directory.Build.props`
- Package versions are centrally managed in `Directory.Packages.props` — never specify versions in individual `.csproj` files

## Key Conventions

### Service Startup Pattern
Every service follows the same `Program.cs` skeleton:
```csharp
builder.AddServiceDefaults();        // OpenTelemetry, health checks, resilience (from eShop.ServiceDefaults)
builder.AddApplicationServices();    // Service-specific DI (defined in Extensions/Extensions.cs)
// ...
app.MapDefaultEndpoints();           // /health and /alive
```

### Adding Application Services
Each service defines `AddApplicationServices(this IHostApplicationBuilder)` in `Extensions/Extensions.cs`. This is the single entry point for all service-specific registrations (DbContext, event bus subscriptions, MediatR, etc.).

### API Endpoints
All HTTP APIs use **Minimal APIs** with API versioning — never MVC controllers. Endpoints are defined as static methods in `Apis/` folder classes via `MapXxxApi()` extension methods on `IEndpointRouteBuilder`. Example: `src/Catalog.API/Apis/CatalogApi.cs`.

### Integration Events (Cross-Service Communication)
- Publish: inject `IEventBus`, call `PublishAsync(new SomeIntegrationEvent(...))`
- Subscribe: chain `.AddSubscription<TEvent, THandler>()` on the event bus builder in `Extensions.cs`
- Events inherit from `IntegrationEvent` (record base in `src/EventBus/Events/`)
- Catalog.API uses an **outbox pattern** via `IIntegrationEventLogService` for transactional consistency
- RabbitMQ exchange: `"eshop_event_bus"` (direct type)

### Ordering Service (DDD + CQRS)
The Ordering bounded context is the most complex — uses full DDD tactical patterns:
- **Domain model**: `src/Ordering.Domain/` — aggregates (`Order`, `Buyer`), value objects (`Address`), domain events, SeedWork base classes (`Entity`, `ValueObject`, `IAggregateRoot`)
- **CQRS**: Commands and queries in `src/Ordering.API/Application/` — commands are `IRequest<T>` handled by separate handler classes; queries bypass domain model returning flat view models
- **Pipeline behaviors** (MediatR): `LoggingBehavior` → `ValidatorBehavior` (FluentValidation) → `TransactionBehavior` → Handler
- **Idempotency**: Commands wrapped in `IdentifiedCommand<T>` with `x-requestid` header GUID
- **Domain events** dispatched inside `SaveEntitiesAsync()` before `SaveChanges` (single transaction)
- Endpoint parameter injection uses `[AsParameters]` attribute with a service record (e.g., `OrderServices`)

### Database & Migrations
- EF Core with PostgreSQL (Npgsql); Aspire helper `AddNpgsqlDbContext<T>()` or standard `AddDbContext<T>()` + `EnrichNpgsqlDbContext<T>()`
- Migrations run automatically on startup via `AddMigration<TContext, TSeed>()` from `src/Shared/MigrateDbContextExtensions.cs`
- Ordering uses `HasDefaultSchema("ordering")` and HiLo sequences for ID generation
- Entity configurations in separate `IEntityTypeConfiguration<T>` classes under `EntityConfigurations/`

## Testing

- **Unit tests**: MSTest + NSubstitute. Test builders pattern in `tests/Ordering.UnitTests/Builders.cs`
- **Functional tests**: xUnit + `WebApplicationFactory<Program>` with real Aspire-managed containers (Docker required)
- **E2E tests**: Playwright (TypeScript) in `e2e/` — config uses `ESHOP_USE_HTTP_ENDPOINTS=1` for CI
- Test runner: Microsoft Testing Platform (`global.json` → `"runner": "Microsoft.Testing.Platform"`)

## C# Style
- Primary constructors preferred for DI injection (e.g., `public sealed class MyService(ILogger logger)`)
- `sealed` classes by default; file-scoped namespaces
- `GlobalUsings.cs` in each project for shared imports
- DI extension methods placed in `Microsoft.Extensions.Hosting` namespace for discoverability
