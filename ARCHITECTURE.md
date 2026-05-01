# Architecture

## konflux-ci/release-service-catalog

**Languages:** Shell (100%), Dockerfile (0%)

## Directory Structure

```
release-service-catalog/
  .github/ (42 files)
  .tekton/ (5 files)
  docs/ (1 files)
  hub/ (5 files)
  integration-tests/ (369 files)
  pipelines/ (116 files)
  schema/ (1 files)
  scripts/ (3 files)
  stepactions/ (8 files)
  tasks/ (1069 files)
```

## Components

### `.github/`

Github config & workflows (42 files)

### `docs/`

Documentation (1 files)

### `scripts/`

Utility scripts (3 files)

## CI/CD

This project uses GitHub Actions with 9 workflow(s):

- Check README.md
- Hot Fix PR
- Linters
- PR AI Labeler
- Assign PR
- Promote branch
- Tekton Task Tests
- Copilot code review
- Dependabot Updates

## Design Decisions

<!-- Document key architectural decisions here -->
<!-- Format: ### Decision Title -->
<!-- **Context:** Why was this decision needed? -->
<!-- **Decision:** What was decided? -->
<!-- **Consequences:** What are the trade-offs? -->
