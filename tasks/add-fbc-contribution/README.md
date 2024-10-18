# add-fbc-contribution

Task to create a internalrequest to add fbc contributions to index images

## Parameters

| Name           | Description                                                                               | Optional | Default value        |
|----------------|-------------------------------------------------------------------------------------------|----------|----------------------|
| snapshotPath   | Path to the JSON string of the mapped Snapshot spec in the data workspace                 | No       | -                    |
| dataPath       | Path to the JSON string of the merged data to use in the data workspace                   | No       | -                    |
| fromIndex      | fromIndex value updated by update-ocp-tag task                                            | No       | -                    |
| pipelineRunUid | The uid of the current pipelineRun. Used as a label value when creating internal requests | No       | -                    |
| targetIndex    | targetIndex value updated by update-ocp-tag task                                          | No       | -                    |
| resultsDirPath | Path to results directory in the data workspace                                           | No       | -                    |

## Changes in 3.4.2
* Improve clarity of log statements when fbc_opt_in is not set to True.

## Changes in 3.4.1
* Removed references to data parameters `iibServiceConfigSecret` and `iibOverwriteFromIndexCredential` as
  they should not be changed by users.

## Changes in 3.4.0
* Removed the `binaryImage` parameter so IIB can auto resolve it

## Changes in 3.3.1
* Removed references of the redundant field `fbc.request` as FBC releases uses `iib` exclusively as its internal request pipeline

## Changes in 3.3.0
* Added a new result `isFbcOptIn` to expose the FBC opt-in status

## Changes in 3.2.2
* Fixing checkton/shellcheck linting issues in the task and test

## Changes in 3.2.1
* The InternalRequest will no longer fail, so success/failure check is found from a result on the internal pipelineRun
* The last 2,000 characters of the IIB log is printed

## Changes in 3.2.0
* Changed the way service account secret is determined
  * Setting `.fbc.iibServiceAccountSecret` is no longer allowed (it was never used anyway). Instead, it's based on the stagedIndex setting now.
  * If `.fbc.stagedIndex` is `true`, we'll use `iib-service-account-stage`.
    Otherwise we'll use `iib-service-account-prod`.
  * The reason is that IIB has a priority queue for requests made with our prod
    kerberos principal and we were asked to use it only for prod index requests.

## Changes in 3.1.0
* Updated the base image used in this task

## Changes in 3.0.0
* The task now writes the updated targetIndex to a results json file in the workspace

## Changes in 2.5.0
* Updated the base image used in this task

## Changes in 2.4.0
* Remove default values of `dataPath` and `snapshotPath` parameters

## Changes in 2.3.2
* Add check to fail the task if `fbc.preGA` and `fbc.hotfix` were both set in the `ReleasePlanAdmission` data and
  test for the failing scenario

## Changes in 2.3.1
* Fix the error message for the empty value of `issueId`, `productName` and `productVersion`
  with the old format, the backticks caused the string inside (e.g. fbc.issueId) to be executed as a command

## Changes in 2.3.0
* Add new result called `indexImageDigests`

## Changes in 2.2.0
* Remove requestTimeout parameter and use values defined in RP/RPA
* default build and request timeouts are now 1500 seconds

## Changes in 2.1.0
* Add the parameter `targetIndex` to receive the `updated-targetIndex` result from
  the task `update-ocp-tag` as input

## Changes in 2.0.0
* The internalrequest CR is created with a label specifying the pipelinerun uid with the new pipelineRunUid parameter
  * This change comes with a bump in the image used for the task

## Changes in 1.5.0
* Add the result `buildTimestamp` to be used in the downstream tasks

## Changes in 1.4.0
* Add the possibility of setting a stagedIndex tag

## Changes in 1.3.0
* Add the possibility of setting a hotfix tag
* replace the `fbcOptIn` result with `mustSignIndexImage` and `mustPublishIndexImage`
  to control the pipeline flow

## Changes in 1.2.0
* Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead

## Changes in 1.1.0
* Add `requestTargetIndex` result
