# AGENTS.md

> Agent guidance for **konflux-ci/release-service-catalog**

This file helps AI coding agents (Cursor, Copilot, Codex, Claude, etc.) 
navigate and contribute to this repository effectively.

**Primary language:** Shell, Dockerfile

## Repository Map

```
konflux-ci/release-service-catalog/
  .github/ # GitHub config & workflows
  .tekton/ 
  docs/ # documentation
  hub/ 
  integration-tests/ 
  pipelines/ 
  schema/ 
  scripts/ # utility scripts
  stepactions/ 
  tasks/ 
  .github
  .gitignore
  .gitlint
  .pr_agent.toml
  .pre-commit-config.yaml
  .tekton
  .yamllint
  CLAUDE.md
  CODEOWNERS
  CODE_OF_CONDUCT.md
```

## Key Directories

- **`.github/`** -- Github config & workflows (42 files)
- **`docs/`** -- Documentation (1 files)
- **`scripts/`** -- Utility scripts (3 files)

## Development Workflow

1. Dependencies: (check project documentation)
2. CI: GitHub Actions (9 workflows)
3. Tests: see `integration-tests/`

## Conventions

- Follow existing code style and patterns in this repository
- Write tests for new functionality
- Keep PRs focused on a single concern
- See `CONTRIBUTING.md` for detailed submission guidelines

## Where to Look

- Documentation: `docs/`
- CI config: `.github/workflows/`
- Code ownership: `CODEOWNERS`
