# Copilot Instructions for AI Coding Agents

## Project Overview
This repository is a proof-of-concept (POC) for OAuth On-Behalf-Of (OBO) flows with Azure API Management (APIM). The codebase is currently minimal and primarily contains documentation. The main focus is on demonstrating authentication and authorization patterns for service-to-service communication using OAuth OBO.

## Key Directories and Files
- `README.md`: Project summary and high-level goals.
- `docs/requirements.md`: Details on requirements, expected flows, and integration points.
- `.github/`: Contains configuration for repository automation (e.g., Dependabot).

## Architecture & Patterns
- The project is structured for extensibility. Expect future additions of sample code, scripts, or infrastructure-as-code for APIM and OAuth flows.
- Documentation-first: Requirements and integration details are captured in markdown files before code implementation.
- Azure-centric: All authentication flows and integration patterns should align with Azure best practices, especially for APIM and OAuth OBO.

## Developer Workflows
- No build or test scripts are present yet. When adding code, prefer using Makefiles or shell scripts for repeatable workflows.
- Document any new workflow in `README.md` and/or `docs/requirements.md`.
- Use markdown for all requirements, architecture decisions, and integration notes.

## Conventions
- All new code and documentation should be placed in clearly named directories (e.g., `src/`, `infra/`, `scripts/`, `docs/`).
- Use descriptive commit messages focused on the "why" behind changes.
- When implementing OAuth OBO flows, reference Azure documentation and provide code comments explaining key steps.

## Integration Points
- Azure API Management (APIM)
- OAuth 2.0 On-Behalf-Of (OBO) flow
- Any future code should clearly document external dependencies and configuration requirements in `docs/requirements.md`.

## Example Patterns
- When adding a sample OBO flow, include:
  - Step-by-step comments in code
  - Configuration samples for Azure resources
  - Integration test instructions in markdown

## How to Extend
- Add new components in their own directories with a README.md explaining their purpose.
- Update `docs/requirements.md` with any new requirements or integration details.
- Keep `.github/copilot-instructions.md` up to date as the project evolves.

---
For questions or unclear conventions, review `README.md` and `docs/requirements.md` first, then update this file as needed.
