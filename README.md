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

# Versioning

All the resources in this repository are versioned through the use of the `app.kubernetes.io/version` label. Any change
in one of these resources will modify the version of the resource. Semantic Versioning is used to bump the versions on each
of those resources.
