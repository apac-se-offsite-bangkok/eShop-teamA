---
description: Guidelines for writing and modifying tests in the eShop codebase
applyTo: 'tests/**'
---

# eShop Testing Guidelines

## Frameworks & Tools

- **Unit tests** use **MSTest v4** (`MSTest.Sdk`). **Functional tests** use **xUnit v3** (`xunit.v3.mtp-v2`) with `Aspire.AppHost.Sdk`.
- **Mocking**: NSubstitute 5.x for unit tests. Functional tests use **no mocks** — real infrastructure via Aspire test containers.
- **Test runner**: Microsoft Testing Platform (configured in `global.json` → `"runner": "Microsoft.Testing.Platform"`).
- **Package versions**: Centrally managed in `Directory.Packages.props` — never add versions in test `.csproj` files.

## Unit Test Conventions (MSTest)

### Structure & Attributes
```csharp
[TestClass]
public sealed class OrderAggregateTest
{
    [TestMethod]
    public void Create_order_item_success()
    {
        //Arrange
        var productId = 1;
        //Act
        var orderItem = new OrderItem(productId, "Product", 10.5m, 0m, "pic.png", 5);
        //Assert
        Assert.IsNotNull(orderItem);
    }
}
```
- Use `[TestClass]` and `[TestMethod]` — never `[Fact]`/`[Theory]` in unit tests.
- Use `[DynamicData(nameof(...))]` for parameterized unit tests (not `[DataRow]`).
- All MSTest unit test projects enable method-level parallelism in `GlobalUsings.cs`:
  ```csharp
  [assembly: Parallelize(Workers = 0, Scope = ExecutionScope.MethodLevel)]
  ```

### Naming
- Domain/Application tests: **snake_case** descriptive names — `Create_order_item_success`, `when_add_two_times_on_the_same_item_then_the_total_of_order_should_be_the_sum_of_the_two_items`
- The name should describe the scenario and expected outcome, not just the method under test.

### AAA Comments
Always use explicit `//Arrange`, `//Act`, `//Assert` comments in test methods. When Act and Assert are a single expression, combine as `//Act - Assert`.

### Assertions (MSTest v4)
Prefer the MSTest v4 assertion API:
- `Assert.IsNotNull(obj)`, `Assert.IsNull(obj)`
- `Assert.AreEqual(expected, actual)`, `Assert.AreSame(expected, actual)`
- `Assert.IsTrue(condition)`, `Assert.IsFalse(condition)`
- `Assert.ThrowsExactly<TException>(() => ...)` — not `Assert.ThrowsException`
- `Assert.HasCount(expected, collection)` — not `Assert.AreEqual(n, list.Count)`
- `Assert.IsEmpty(collection)`
- `Assert.IsInstanceOfType<T>(obj)` — generic form, not `Assert.IsInstanceOfType(obj, typeof(T))`

### NSubstitute Mocking Patterns
```csharp
// Setup
var repository = Substitute.For<IOrderRepository>();
repository.GetAsync(Arg.Any<int>()).Returns(Task.FromResult(new Order()));

// Verification
await mediator.Received().Send(Arg.Any<IRequest<bool>>(), default);
await mediator.DidNotReceive().Send(Arg.Any<IRequest<bool>>(), default);

// Exception simulation
repository.GetAsync(Arg.Any<int>()).Throws(new KeyNotFoundException());
```
- Create substitutes as class fields initialized in the constructor — not in each test method.
- Use `Arg.Any<T>()` for flexible matching.
- Use `NullLogger<T>.Instance` instead of substituting `ILogger<T>`.

### Test Data
- Use **builder pattern** for domain aggregates (see `tests/Ordering.UnitTests/Builders.cs`):
  ```csharp
  var address = new AddressBuilder().Build();
  var order = new OrderBuilder(address).AddOne(...).Build();
  ```
- Use private helper methods prefixed with `Fake` for command/DTO creation: `FakeOrder()`, `FakeOrderRequest()`.
- Use `"fake"` prefix for inline test strings: `"fakeStreet"`, `"fakeName"`.

### Testing Minimal API Endpoints
Test endpoint methods directly as static method calls, not via HTTP:
```csharp
var result = await OrdersApi.CancelOrderAsync(Guid.NewGuid(), services);
Assert.IsInstanceOfType<Ok>(result.Result);
```

### Testing gRPC Services
Use the custom `TestServerCallContext` helper to create fake gRPC contexts:
```csharp
var context = TestServerCallContext.Create(cancellationToken: TestContext.CancellationToken);
var httpContext = new DefaultHttpContext();
httpContext.User = new ClaimsPrincipal(new ClaimsIdentity([new Claim("sub", "1")]));
context.SetUserState("__HttpContext", httpContext);
```

## Functional Test Conventions (xUnit)

### Fixture Pattern
Every functional test project has a fixture class extending `WebApplicationFactory<Program>` with `IAsyncLifetime`:
```csharp
public sealed class CatalogApiFixture : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly IHost _app;
    public async Task InitializeAsync()
    {
        // Start Aspire resources (PostgreSQL, etc.)
    }
}
```
- Spin up real containers via Aspire: `AddPostgres("CatalogDB").WithImage("ankane/pgvector")`
- Override connection strings via `ConfigureHostConfiguration` → `AddInMemoryCollection`
- **Docker is required** to run functional tests.

### Auth Bypass (Ordering)
Ordering functional tests inject `AutoAuthorizeMiddleware` via `IStartupFilter` to set a fake authenticated identity — no real Identity.API auth flow.

### Attributes & Naming
- Use `[Fact]` for single-case tests, `[Theory]` + `[InlineData]` for parameterized (e.g., testing API v1 and v2).
- Class implements `IClassFixture<TFixture>` for shared fixture injection.
- **PascalCase** descriptive names: `GetCatalogItemsRespectsPageSize`, `CancelWithEmptyGuidFails`.

### Assertions (xUnit)
- `Assert.Equal(expected, actual)`, `Assert.NotEqual(...)`
- `Assert.NotNull(obj)`
- `Assert.Contains(item, collection)`, `Assert.All(collection, predicate)`
- `Assert.Equal(HttpStatusCode.OK, response.StatusCode)` for status code validation.

### CancellationToken
Use `TestContext.Current.CancellationToken` (xUnit v3) in functional tests — not `CancellationToken.None`.

### API Versioning in Tests
Use `ApiVersionHandler` with `QueryStringApiVersionWriter` to inject API version as a query parameter:
```csharp
var client = fixture.CreateDefaultClient(
    new ApiVersionHandler(new QueryStringApiVersionWriter(), new ApiVersion(1.0)));
```

## File & Project Organization

- Test files mirror the source structure: `Domain/`, `Application/`, `Services/`, `ViewModels/`
- One test class per file, file name matches class name.
- `GlobalUsings.cs` in each test project for common imports and assembly-level attributes.
- Builders and helpers live in the test project root or `Helpers/` folder.
- Test project references use `IsAspireProjectResource="false"` for libraries that shouldn't be treated as Aspire resources.

## Running Tests

```bash
# All tests (Docker required for functional tests)
dotnet test eShop.Web.slnf

# Specific test project
dotnet test tests/Ordering.UnitTests

# E2E tests (Playwright, needs running app on localhost:5045)
npx playwright test
```