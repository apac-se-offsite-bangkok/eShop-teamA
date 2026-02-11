# eShop Copilot Instructions

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
