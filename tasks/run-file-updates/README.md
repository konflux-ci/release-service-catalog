# run-file-udpates

Tekton task to create InternalRequests for each repository that needs to be updated. This information is extracted from
the field `spec.data.fileUpdates` in the ReleasePlanAdmission resource.

## Parameters

| Name            | Description                                                                               | Optional | Default value            |
|-----------------|-------------------------------------------------------------------------------------------|----------|--------------------------|
| jsonKey         | JSON key where the information is defined                                                 | Yes      | .spec.data.fileUpdates[] |
| fileUpdatesPath | Path to the JSON file containing the key                                                  | No       |                          |
| snapshotPath    | Path to the JSON string of the Snapshot spec in the data workspace                        | No       | snapshot_spec.json       |
| request         | Type of request to be created                                                             | Yes      | file-updates             |
| synchronously   | Whether the task should wait for InternalRequests to complete                             | Yes      | true                     |
| pipelineRunUid  | The uid of the current pipelineRun. Used as a label value when creating internal requests | No       |                          |

## Changelog

## Changes in 1.0.0
- The internalrequest CRs are created with a label specifying the pipelinerun uid with the new pipelineRunUid parameter
  - This change comes with a bump in the image used for the task

## Changes since 0.5.0
- Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead

### Changes since 0.4.1
- jsonKey default changed to .spec.data.fileUpdates{} due to API changes

### changes since 0.3
- update Tekton API to v1

### changes since 0.2
- application name from snapshot is now provided to update-paths

### changes since 0.1
- adds parameter `snapshotPath`.
- calls `update-paths` script to run the `{{ }}` enclosed yq updates set in the `paths` key
  of the defined `fileUpdatesPath` file.
