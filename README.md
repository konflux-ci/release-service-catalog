# HACBS Release bundles

HACBS Release bundles is a curated Tekton bundles catalog that contains bundles that are used by the
[HACBS Release operator](https://github.com/redhat-appstudio/release-service) to process releases in the context of
AppStudio.

## Using the bundles

All the bundles in this repository are pushed to our [Quay organization](https://quay.io/organization/hacbs-release).
This push happens automatically whenever a new bundle is added to the repository or an existent one is updated. Two new
tags will be created or updated during this automatic process:

* **main**: This tag will point always to the existing code in the repository main branch.
* **commit-sha**: A tag with the commit-sha of the change will be created, so we can have multiple bundles per each
change in the git repository.

## Adding new bundles

To add new bundles to this repository, create a directory in the [definitions directory](definitions) and place inside
yaml files containing the definition of the resources that should go inside the bundle. The directory name will be used
as the name of the new bundle.

> **NOTE:** Although not required, it is recommended to define a single resource per file.

## Linting of yaml files

Whenever a change is pushed to the repository and a pull request is created, a yaml lint task will run to ensure that the
bundle definition doesn't contain invalid yaml data. Refer to the [.yamllint file](.yamllint) to see the exact applied
rules. For more information on yamllint, check the [official documentation](https://yamllint.readthedocs.io/en/stable).
