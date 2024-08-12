# add-fbc-contribution

Task to create a internalrequest to add fbc contributions to index images

## Parameters

| Name           | Description                                                                               | Optional | Default value        |
|----------------|-------------------------------------------------------------------------------------------|----------|----------------------|
| snapshotPath   | Path to the JSON string of the mapped Snapshot spec in the data workspace                 | No       | -                    |
| dataPath       | Path to the JSON string of the merged data to use in the data workspace                   | No       | -                    |
| binaryImage    | binaryImage value updated by update-ocp-tag task                                          | No       | -                    |
| fromIndex      | fromIndex value updated by update-ocp-tag task                                            | No       | -                    |
| pipelineRunUid | The uid of the current pipelineRun. Used as a label value when creating internal requests | No       | -                    |
| targetIndex    | targetIndex value updated by update-ocp-tag task                                          | No       | -                    |
| resultsDirPath | Path to results directory in the data workspace                                           | No       | -                    |

## Changes in 3.1.0
* Updated the base image used in this task

## Changes in 3.0.0
* the task now writes the updated targetIndex to a results json file in the workspace

## Changes in 2.5.0
* updated the base image used in this task

## Changes in 2.4.0
* remove default values of `dataPath` and `snapshotPath` parameters

## Changes in 2.3.2
* add check to fail the task if `fbc.preGA` and `fbc.hotfix` were both set in the `ReleasePlanAdmission` data and
  test for the failing scenario

## Changes in 2.3.1
* fix the error message for the empty value of `issueId`, `productName` and `productVersion`
  with the old format, the backticks caused the string inside (e.g. fbc.issueId) to be executed as a command

## Changes in 2.3.0
* add new result called `indexImageDigests`

## Changes in 2.2.0
* remove requestTimeout parameter and use values defined in RP/RPA
* default build and request timeouts are now 1500 seconds

## Changes in 2.1.0
* add the parameter `targetIndex` to receive the `updated-targetIndex` result from
  the task `update-ocp-tag` as input

## Changes in 2.0.0
* The internalrequest CR is created with a label specifying the pipelinerun uid with the new pipelineRunUid parameter
  * This change comes with a bump in the image used for the task

## Changes in 1.5.0
* add the result `buildTimestamp` to be used in the downstream tasks

## Changes in 1.4.0
* add the possibility of setting a stagedIndex tag
 
## Changes in 1.3.0
* add the possibility of setting a hotfix tag
* replace the `fbcOptIn` result with `mustSignIndexImage` and `mustPublishIndexImage`
  to control the pipeline flow

## Changes in 1.2.0
* Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead

## Changes in 1.1.0
* add `requestTargetIndex` result
