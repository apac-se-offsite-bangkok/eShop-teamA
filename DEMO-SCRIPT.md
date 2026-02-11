# eShop Context Engineering — Demo Script

## 1. File Summaries

### copilot-instructions.md (`.github/copilot-instructions.md`)

Provides repository-level instructions that GitHub Copilot automatically loads in the IDE. It describes the .NET Aspire architecture, service roles (Catalog, Ordering, Basket, Identity), build/run commands, and key conventions — Minimal APIs with versioning, DDD+CQRS in Ordering, integration events via RabbitMQ, and EF Core migrations. It also prescribes C# style (primary constructors, sealed classes, file-scoped namespaces) so every Copilot suggestion aligns with the team's patterns.

### AGENTS.MD

Gives AI coding agents (e.g., Copilot Coding Agent) a full project map: source structure, test organization, CI/CD workflows, and step-by-step development workflows for adding tests, endpoints, and debugging. Includes an "Important Notes for AI Agents" section with hard constraints — Docker prerequisites, API versioning rules, solution filter usage, and cancellation token patterns — acting as guardrails that prevent agent-generated code from breaking builds.

### test.instructions.md (`.github/instructions/test.instructions.md`)

A path-scoped instruction file that applies only to files under `tests/`. It codifies testing conventions: MSTest v4 for unit tests with snake_case names and `//Arrange //Act //Assert` comments, xUnit v3 for functional tests with PascalCase names and real Aspire containers, NSubstitute mocking patterns, builder pattern for test data, and specific assertion API preferences (e.g., `Assert.HasCount` over manual count checks).

### Bicep Skill (`.github/skills/bicep-skill/`)

A reusable Copilot skill for generating Azure Bicep infrastructure-as-code. It maps the local Aspire dev topology (PostgreSQL, Redis, RabbitMQ) to production Azure equivalents (Flexible Server, Azure Cache, Service Bus) with modular templates, enabling developers to ask Copilot to scaffold or modify IaC without leaving the editor.

## 2. Prompt Governance and Customer Value

### How Prompts Are Governed

| Governance Layer | Mechanism | Example |
| --- | --- | --- |
| **Global Copilot instructions** | `copilot-instructions.md` is auto-loaded for every Copilot interaction, encoding architecture, conventions, and C# style. | Copilot suggests `sealed class` with primary constructors and Minimal API endpoints — not MVC controllers. |
| **Path-scoped instructions** | `test.instructions.md` applies only under `tests/`, enforcing test-specific conventions without cluttering other contexts. | Unit test suggestions use `[TestMethod]` with snake_case names and `Assert.HasCount`, not `[Fact]` or manual `.Count` checks. |
| **Agent guardrails** | `AGENTS.MD` "Important Notes" section lists hard constraints (Docker required, API versioning, solution filters). | Prevents agents from generating code that breaks CI or misuses API versions. |
| **Reusable skills** | The Bicep skill provides a template and resource mapping so Copilot generates correct IaC on demand. | Asking "add a new Azure resource" produces a Bicep module following the established pattern. |
| **CI enforcement** | GitHub Actions workflows (`pr-validation.yml`, `markdownlint.yml`, `playwright.yml`) validate every change. | Agent-generated PRs are automatically built, tested, and linted before merge. |

### Customer Value (Dev Team Delivering Product Features)

- **Faster onboarding** — New team members and AI agents get productive immediately with documented architecture, patterns, and commands across all context files.
- **Consistent code quality** — Layered instructions (global, path-scoped, agent-level) reduce review cycles by steering AI output toward established conventions from the start.
- **Reduced context-switching** — Developers don't need to manually explain project structure every time they use an AI tool; the context is always available and auto-loaded.
- **Lower risk of regressions** — Guardrails and CI enforcement catch convention violations before they reach the main branch.
- **Infrastructure parity** — The Bicep skill ensures production IaC stays aligned with the local Aspire dev topology, reducing deployment surprises.
- **Scalable AI adoption** — As the team adds more AI-assisted workflows, the governance layer grows with them instead of relying on tribal knowledge.

## 3. Areas to Improve and Next Steps

### Areas to Improve

1. **Prompt versioning and review process** — Treat instruction files and skills as governed artifacts with PR reviews, ownership, and change history tracking.
2. **Measurable outcomes** — Establish metrics to track the impact of context engineering (e.g., PR review turnaround time, AI-generated code acceptance rate, number of CI failures on agent PRs).
3. **Security-scoped instructions** — Add explicit guidance on secrets handling, dependency scanning, and secure coding patterns so AI agents avoid introducing vulnerabilities.
4. **Additional path-scoped instructions** — Create instruction files for other areas (e.g., `src/Ordering.API/` for DDD patterns, `infra/` for Bicep conventions) to deepen contextual coverage.

### Recommended Next Steps

1. **Add prompt testing** — Validate that instruction files produce correct AI behavior by running sample tasks and checking output against expected conventions.
2. **Expand skills library** — Create additional Copilot skills for recurring tasks (e.g., database migrations, API design reviews, performance testing).
3. **Integrate feedback loops** — Capture which AI suggestions are accepted or rejected by developers and use that data to refine the context engineering files over time.
4. **Cross-team sharing** — Package the context engineering pattern (instructions + skills + agents) as a template other teams can adopt for their own repositories.
