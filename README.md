# Release Service Catalog

This repository contains a collection of Tekton resources to be used with the
[Release Service](https://github.com/konflux-ci/release-service). The main purpose of these
resources is to facilitate and streamline the release process.

# Resources
Here's a brief overview of what you can find in the different directories of this catalog:

* `pipelines`: This directory contains Release Pipelines which use a collection of both Release Tasks and Hub Tasks.
* `tasks`: The tasks directory holds Tekton Tasks that are used in our Release Pipelines.
* `hub`: This directory contains Tekton resources that have been sourced from the Tekton Hub.

## Linting of yaml files

Whenever a change is pushed to this repository and a pull request is created, a yaml lint task will run to ensure that the
resource definition doesn't contain invalid yaml data. Refer to the [.yamllint file](.yamllint) to see the exact applied
rules. For more information on yamllint, check the [official documentation](https://yamllint.readthedocs.io/en/stable).

## Pre-commit Hooks

This repository uses pre-commit hooks to ensure that sensitive vault files are always encrypted before being committed. The hook prevents accidental commits of unencrypted Ansible Vault files.

### Setup for Team Members

To set up the pre-commit hooks on your local machine:

1. **Install pre-commit** (if not already installed):
   ```bash
   pip install pre-commit
   ```

2. **Install the hooks** in your local repository:
   ```bash
   pre-commit install
   ```

### What it does

The pre-commit hook automatically checks all vault files (files matching `.*vault.*\.(yaml|yml)$`) to ensure they are encrypted with Ansible Vault before allowing the commit. If any vault files are found to be unencrypted, the commit will be rejected with helpful instructions on how to encrypt them.

This prevents accidentally committing sensitive secrets in plain text to the repository.
