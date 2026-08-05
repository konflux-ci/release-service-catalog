# AGENTS.md

This is the Release Service Catalog - a collection of Tekton resources (Tasks, Pipelines, StepActions) for the Konflux CI Release Service. The repository facilitates and streamlines software release processes using Kubernetes-native CI/CD with Tekton.

## Structure

- `tasks/managed/` - Production release tasks (signing, publishing, advisory management)
- `tasks/collectors/` - Data collection tasks; `tasks/internal/` - Internal workflow tasks
- `pipelines/managed/` - Release pipelines; `pipelines/run-collectors/` - Collection pipelines
- `stepactions/` - Reusable step actions; `hub/` - Tekton Hub resources
- `integration-tests/` - Test configs with encrypted Ansible Vault files

## Conventions

- **Main branch**: `development` (not main)
- **Commits**: Conventional commits enforced by gitlint, scope is a Jira ticket ID: `feat(JIRA-1234): message`, `fix(JIRA-1234): message`
- **YAML style**: 120-char max, consistent indentation, `---` document start, max 1 empty line
- **Tekton tasks**: Trusted Artifacts tasks with non-`release-service-utils` images MUST set `stepTemplate.securityContext.runAsUser: 1001`; all tasks SHOULD specify compute resource requirements
- **New tasks**: implement logic as a standalone script (usually Python) in the [release-service-utils repo](https://github.com/konflux-ci/release-service-utils), referenced via `command`, rather than inline `script` shell code — see [RELEASE-2455](https://redhat.atlassian.net/browse/RELEASE-2455)
- **Vault files** (`.*vault.*\.(yaml|yml)$`): MUST be encrypted with `ansible-vault` before commit
- **READMEs** under `tasks/` and `pipelines/`: auto-generated, do not edit by hand

## Validation & Linting

```bash
yamllint .                                                # YAML style (120ch, --- start)
gitlint --commits origin/development..HEAD                # Conventional commit format
pre-commit run --all-files                                # All hooks including vault encryption check
```

## Security

```bash
ansible-vault encrypt integration-tests/*/vault/secrets.yaml  # Encrypt before commit (MANDATORY)
scripts/check-vault-encrypted.sh path/to/vault/file.yaml      # Verify encryption
```

Never commit unencrypted vault files. Pre-commit hooks enforce this automatically.

## Testing

```bash
./scripts/run-local-tests.sh                              # Auto-detect changes
./scripts/run-local-tests.sh --pr-mode                    # CI-identical change detection
./scripts/run-local-tests.sh --parallel 2 tasks/managed/  # Parallel execution
./scripts/run-local-tests.sh tasks/managed/<task-name>    # Specific task
.github/scripts/tkn_check_compute_resources.sh            # Resource validation
.github/scripts/tkn_check_task_runasuser.sh               # Security compliance
```

Test locally first. Use `--pr-mode` for pre-merge validation. Check `test-results/summary.txt` after runs.

## Scripting & Tooling

- **Shell options**: `set -eo pipefail` minimum in Tekton task scripts; `set -euo pipefail` for standalone scripts. Integration test `test.sh` files are sourced (not standalone) and inherit the caller's shell options
- **Variables**: always quote — `"${VAR}"`, `"$(command)"`; use `${VAR}` not `$VAR`
- **JSON**: build with `jq --arg`/`--argjson` or `jq -n`, never string concatenation or `echo`
- **jq flags**: `-r` for raw output, `-c` for compact, `-e` to exit non-zero on false/null
- **Tekton results**: `echo -n "value" > "$(results.name.path)"` — always `-n` to avoid trailing newlines
- **curl**: use `--retry 3`, `-s` for silent, `--fail-with-body` for error handling; pipe to `jq -r` for parsing
- **Error handling**: internal tasks MUST always `exit 0` and write success/failure to `$(results.result.path)`.
  Use a `trap EXIT` handler or write the result explicitly at each exit point. A non-zero exit prevents Tekton
  from setting results that the calling managed task needs. Managed and collector tasks can use non-zero exit codes as appropriate to signal errors
- **Secrets**: `set +x` before using sensitive values, re-enable after; read from mounted files, not env vars
- **Cleanup**: `mktemp` + `trap 'rm -f "${TEMP_FILE}"' EXIT`; use `pushd`/`popd` for directory changes

## Task and pipeline README generation

README.md under `tasks/` and `pipelines/` are generated from the Tekton YAML. Do not edit them by hand.
Update `spec.description` and `spec.params` in the YAML, then run `./.github/scripts/readme_generator.sh <directory>`

## When Task Complete

Run the full validation sequence:

```bash
yamllint .
gitlint --commits origin/development..HEAD
pre-commit run --all-files
```
