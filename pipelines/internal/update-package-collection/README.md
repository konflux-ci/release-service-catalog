# update-package-collection-pipeline

Runs the update-package-collection-task to update one or more package collections for a given product and environment.
Supports both adding and deleting builds (NVRs) per package.

This pipeline ensures the update-package-collection-task result is always captured and propagated, even if the underlying step encounters errors.

## Parameters

| Name                           | Description                                                                                        | Optional | Default value                                                                   |
| ------------------------------ | -------------------------------------------------------------------------------------------------- | -------- | ------------------------------------------------------------------------------- |
| repo                           | Git repository URL for `package-collection-utils`.                                                 | Yes      | `https://gitlab.cee.redhat.com/package-collection/package-collection-utils.git` |
| branch                         | Git branch to checkout for `package-collection-utils`.                                             | Yes      | `main`                                                                          |
| action                         | The action to perform on the package collection. One of `add-builds` or `delete-builds`.           | Yes      | `add-builds`                                                                    |
| env                            | Target environment where the package collection will be updated. One of `dev`, `stage`, or `prod`. | Yes      | `dev`                                                                           |
| product                        | The product whose package collection will be updated.                                              | Yes      | `example-product`                                                               |
| collection-name                | The name of the package collection to update.                                                      | Yes      | `example-collection`                                                            |
| package_name                   | The name of the package to add or remove.                                                          | No       | –                                                                               |
| nvr                            | The NVR (Name-Version-Release) of the package.                                                     | No       | –                                                                               |
| download_url                   | The URL where the package can be downloaded.                                                       | No       | –                                                                               |
| internalRequestPipelineRunName | Name of the PipelineRun that invoked this pipeline, used for traceability.                         | Yes      | `update-pkg-col-run-001`                                                        |
| taskGitUrl                     | Git repository URL where the Tekton task YAML is located (used by resolver).                       | Yes      | –                                                                               |
| taskGitRevision                | Git revision of the repository containing the Tekton task.                                         | Yes      | –                                                                               |
