# add-fbc-contribution

Task to create a internalrequest to add fbc contributions to index images

## Parameters

| Name           | Description                                                                               | Optional | Default value        |
|----------------|-------------------------------------------------------------------------------------------|----------|----------------------|
| snapshotPath   | Path to the JSON string of the mapped Snapshot spec in the data workspace                 | Yes      | snapshot_spec.json   |
| dataPath       | Path to the JSON string of the merged data to use in the data workspace                   | Yes      | data.json            |
| requestTimeout | InternalRequest timeout                                                                   | Yes      | 180                  |
| binaryImage    | binaryImage value updated by update-ocp-tag task                                          | No       |                      |
| fromIndex      | fromIndex value updated by update-ocp-tag task                                            | No       |                      |
| pipelineRunUid | The uid of the current pipelineRun. Used as a label value when creating internal requests | No       |                      |

## changes in 2.0.0
- The internalrequest CR is created with a label specifying the pipelinerun uid with the new pipelineRunUid parameter
  - This change comes with a bump in the image used for the task

## changes in 1.5.0
- add the result `buildTimestamp` to be used in the downstream tasks

## changes in 1.4.0
- add the possibility of setting a stagedIndex tag
 
## changes in 1.3.0
- add the possibility of setting a hotfix tag
- replace the `fbcOptIn` result with `mustSignIndexImage` and `mustPublishIndexImage`
  to control the pipeline flow

## changes in 1.2.0
- Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead

## changes in 1.1.0
- add `requestTargetIndex` result
