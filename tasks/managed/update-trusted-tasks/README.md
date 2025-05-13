# update-trusted-tasks
Tekton task to update trusted-tasks list OCI artifact.
Once a task is released as a bundle, the list of trusted-tasks should be 
updated with the new task.
The OCI artifact containing the trusted-tasks list is named `acceptable-data-bundles` and should reside in the same org in the registry.
If it is already in place, it will be used as an input to which the results will be appended, else a new artifact will be created.

## Parameters

| Name       | Description                                                             | Optional | Default value |
|------------|-------------------------------------------------------------------------|----------|---------------|
| snapshotPath   | Path to the JSON string of the Snapshot spec in the data workspace | No       | -             |

## Changes in 0.2.0
* Task's image (quay.io/konflux-ci/appstudio-utils) has been updated to the latest
