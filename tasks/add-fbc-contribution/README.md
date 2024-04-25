# add-fbc-contribution

Task to create a internalrequest to add fbc contributions to index images

## Parameters

| Name           | Description                                                                               | Optional | Default value        |
|----------------|-------------------------------------------------------------------------------------------|----------|----------------------|
| snapshotPath   | Path to the JSON string of the mapped Snapshot spec in the data workspace                 | Yes      | snapshot_spec.json   |
| dataPath       | Path to the JSON string of the merged data to use in the data workspace                   | Yes      | data.json            |
| binaryImage    | binaryImage value updated by update-ocp-tag task                                          | No       |                      |
| fromIndex      | fromIndex value updated by update-ocp-tag task                                            | No       |                      |
| pipelineRunUid | The uid of the current pipelineRun. Used as a label value when creating internal requests | No       |                      |
| targetIndex    | targetIndex value updated by update-ocp-tag task                                          | No       |                      |

## changes in 2.3.2
- add check to fail the task if `fbc.preGA` and `fbc.hotfix` were both set in the `ReleasePlanAdmission` data and
  test for the failing scenario

## changes in 2.3.1
- fix the error message for the empty value of `issueId`, `productName` and `productVersion`
  with the old format, the backticks caused the string inside (e.g. fbc.issueId) to be executed as a command

## changes in 2.3.0
- add new result called `indexImageDigests`

## changes in 2.2.0
- remove requestTimeout parameter and use values defined in RP/RPA
- default build and request timeouts are now 1500 seconds

## changes in 2.1.0
- add the parameter `targetIndex` to receive the `updated-targetIndex` result from
  the task `update-ocp-tag` as input

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
