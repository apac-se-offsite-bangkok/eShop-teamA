# eShop Context Engineering — Demo Script

## 1. File Summaries

### AGENTS.MD

The `AGENTS.MD` file is a context engineering guide that gives AI agents a structured understanding of the eShop codebase. It documents the microservices architecture, project layout, test frameworks (MSTest, xUnit, Playwright), build commands, CI/CD workflows, and common development patterns. It also includes explicit guardrails — such as Docker prerequisites, API versioning rules, and cancellation token usage — so agents produce code consistent with existing conventions.

### copilot-instructions.md

A `.github/copilot-instructions.md` file does not yet exist in this repository. When added, it will serve as the repository-level instruction set for GitHub Copilot, providing scoped guidance on coding style, preferred libraries, and project-specific conventions. This is a recommended next step to complement the `AGENTS.MD` file and tailor Copilot suggestions directly within the IDE.

## 2. Prompt Governance and Customer Value

### How Prompts Are Governed

| Governance Layer | Mechanism | Example |
| --- | --- | --- |
| **Codebase context** | `AGENTS.MD` encodes architecture, test patterns, and build commands so agents inherit project conventions automatically. | Agents know to use MSTest with `[TestMethod]` and Arrange-Act-Assert, not a different framework. |
| **Guardrails** | Explicit "Important Notes for AI Agents" section lists hard constraints (Docker required, API versioning, solution filters). | Prevents agents from generating code that breaks CI or misuses API versions. |
| **Workflow templates** | Step-by-step workflows for adding tests, endpoints, and debugging are documented so agents follow the team's process. | A new unit test follows the `MethodName_Scenario_ExpectedOutcome` naming convention. |
| **CI enforcement** | GitHub Actions workflows (`pr-validation.yml`, `markdownlint.yml`, `playwright.yml`) validate every change. | Agent-generated PRs are automatically built, tested, and linted before merge. |

### Customer Value (Dev Team Delivering Product Features)

- **Faster onboarding** — New team members and AI agents get productive immediately with documented architecture, patterns, and commands.
- **Consistent code quality** — Governed prompts reduce review cycles by steering AI output toward established conventions from the start.
- **Reduced context-switching** — Developers don't need to manually explain project structure every time they use an AI tool; the context is always available.
- **Lower risk of regressions** — Guardrails and CI enforcement catch convention violations before they reach the main branch.
- **Scalable AI adoption** — As the team adds more AI-assisted workflows, the governance layer grows with them instead of relying on tribal knowledge.

## 3. Areas to Improve and Next Steps

### Areas to Improve

1. **Add `.github/copilot-instructions.md`** — Define repository-level Copilot instructions for IDE-integrated suggestions (coding style, preferred patterns, import conventions). This complements `AGENTS.MD` by targeting inline code completion rather than agent-level tasks.
2. **Prompt versioning and review process** — Treat `AGENTS.MD` and future instruction files as governed artifacts with PR reviews, ownership, and change history tracking.
3. **Measurable outcomes** — Establish metrics to track the impact of context engineering (e.g., PR review turnaround time, AI-generated code acceptance rate, number of CI failures on agent PRs).
4. **Security-scoped instructions** — Add explicit guidance on secrets handling, dependency scanning, and secure coding patterns so AI agents avoid introducing vulnerabilities.

### Recommended Next Steps

1. **Create `.github/copilot-instructions.md`** with coding style, naming conventions, and preferred library guidance specific to the eShop project.
2. **Add prompt testing** — Validate that `AGENTS.MD` produces correct agent behavior by running sample tasks and checking output against expected conventions.
3. **Expand to domain-specific agents** — Create focused instruction files for specialized tasks (e.g., database migrations, API design reviews, performance testing).
4. **Integrate feedback loops** — Capture which AI suggestions are accepted or rejected by developers and use that data to refine the context engineering files over time.
