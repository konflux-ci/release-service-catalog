# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the Release Service Catalog - a collection of Tekton resources (Tasks, Pipelines, StepActions) for the Konflux CI Release Service. The repository facilitates and streamlines software release processes using Kubernetes-native CI/CD with Tekton.

## Key Development Commands

### Essential Linting (run before commits)
```bash
# YAML validation (required)
yamllint .

# Git commit message validation
gitlint --commits origin/development..HEAD

# JSON schema validation
check-jsonschema --check-metaschema schema/dataKeys.json

# Pre-commit hooks (install once, runs automatically)
pip install pre-commit && pre-commit install
```

### Security Requirements
```bash
# Encrypt vault files before commit (MANDATORY)
ansible-vault encrypt integration-tests/*/vault/secrets.yaml

# Check vault encryption
scripts/check-vault-encrypted.sh path/to/vault/file.yaml
```

### Testing
```bash
# Local testing (mirrors CI logic exactly)
./scripts/run-local-tests.sh                              # Auto-detect changes
./scripts/run-local-tests.sh --pr-mode                    # Test with CI-identical change detection
./scripts/run-local-tests.sh --parallel 2 tasks/managed/  # Parallel execution
./scripts/run-local-tests.sh tasks/managed/add-fbc-contribution  # Specific task

# Validation
.github/scripts/tkn_check_compute_resources.sh
.github/scripts/tkn_check_task_runasuser.sh
```

### Testing Best Practices
- **Test locally first** - faster feedback than CI
- **Use `--pr-mode`** for pre-merge validation
- **Check `test-results/summary.txt`** after each run
- **Sequential by default** - use `--parallel N` only for stable tests

## Architecture and Structure

### Directory Organization
- `tasks/managed/` - Production release tasks (60+ tasks: signing, publishing, advisory management)
- `tasks/collectors/` - Data collection and aggregation tasks  
- `tasks/internal/` - Internal workflow tasks
- `pipelines/managed/` - Production release pipelines
- `pipelines/run-collectors/` - Data collection pipelines
- `hub/` - Tekton Hub resources
- `stepactions/` - Reusable step actions
- `integration-tests/` - Test configurations with encrypted vault files

### Key Patterns
- **Task Types**: Managed (production), Collectors (data gathering), Internal (workflows)
- **Security Model**: Ansible Vault encryption for all secrets, mandatory pre-commit hooks
- **Testing**: Dual approach for Trusted Artifacts vs PVC-based tasks
- **Validation**: Multi-layer (YAML, Tekton, security, compute resources)

## Critical Conventions

### Git Workflow
- **Main branch**: `development` (not main)
- **Commit format**: Conventional commits enforced by gitlint
- **Examples**: `feat(ISV-6027): bump version`, `fix(ISV-6032): update task names`

### YAML Style (yamllint enforced)
- Max 120 character lines
- Consistent space indentation
- Required `---` document start
- Max 1 consecutive empty line

### Tekton Security Requirements
- All tasks MUST specify `runAsUser` for security compliance
- Tasks SHOULD specify compute resource requirements
- Vault files matching `.*vault.*\.(yaml|yml)$` MUST be encrypted

### Testing Requirements
- README.md required for all task/pipeline directories
- Integration tests for task changes
- Both Trusted Artifacts and PVC-based workflow support

## Security Critical Points
- Never commit unencrypted vault files
- Pre-commit hooks prevent accidental secret exposure
- All sensitive data must use Ansible Vault encryption
- Security validation runs automatically in CI/CD

## When Task Complete
Run this validation sequence:
```bash
yamllint .
gitlint --commits origin/development..HEAD  
pre-commit run --all-files
check-jsonschema --check-metaschema schema/dataKeys.json
```