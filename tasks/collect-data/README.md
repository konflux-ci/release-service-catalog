# collect-data

Tekton task to collect the information added to the data field of the release resources.

The purpose of this task is to collect all the data and supply it to the other task in the pipeline by creating
a json file called `data.json` in the workspace.

This task also stores the passed resources as json files in a workspace.

The parameters to this task are lowercase instead of camelCase because they are passed from the operator, and the
operator passes them as lowercase.

A task result is returned for each resource with the relative path to the stored JSON for it in the workspace. There is
also a task result for the fbcFragment extracted from the snapshot's first component.

Finally, the task checks that the keys from the correct resource (a key that should come from the ReleasePlanAdmission
should not be present in the Release data section).

## Parameters

| Name                 | Description                                        | Optional | Default value |
|----------------------|----------------------------------------------------|----------|---------------|
| release              | Namespaced name of the Release                     | No       | -             |
| releasePlan          | Namespaced name of the ReleasePlan                 | No       | -             |
| releasePlanAdmission | Namespaced name of the ReleasePlanAdmission        | No       | -             |
| releaseServiceConfig | Namespaced name of the ReleaseServiceConfig        | No       | -             |
| snapshot             | Namespaced name of the Snapshot                    | No       | -             |
| subdirectory         | Subdirectory inside the workspace to be used.      | Yes      | -             |

## Changes in 4.5.3
* Introduce new step to collect, print and record information about the git resolver metadata for the
  running release pipeline.

## Changes in 4.5.2
* Introduce new step to collect information needed for reduce-snapshot task

## Changes in 4.5.1
  * Fix linting issues in this task

## Changes in 4.5.0
  * Updated the base image used in this task

## Changes in 4.4.0
  * Updated the base image used in this task

## Changes in 4.3.0
  * Task creates a results dir in the workspace (inside the subdirectory if set). The path to this
    inside the workspace is emitted as a task result

## Changes in 4.2.0
  * Replace redirects with `tee` so that more is output in the task log to make debugging easier

## Changes in 4.1.0
  * releaseNotes.type is allowed in both Release and ReleasePlan CRs

## Changes in 4.0.0
  * releaseServiceConfig parameter added and the task now stores that CR in the data workspace as well

## Changes in 3.1.0
  * product_stream was added as a disallowed key in Release and ReleasePlan CRs

## Changes in 3.0.0
  * Parameters supplied by the Release Service operator now use camelCase format. For consistency, the `collect-data`
    task also switched to use the same format.

## Changes in 2.1.0
  * product_name and product_version were added as disallowed keys in Release and ReleasePlan CRs

## Changes in 2.0.0
  * A second step was added to the task
    * The step lists keys that are disallowed for each of the three release resources
    * If any of the disallowed keys are found in the corresponding resource, the check will fail the task

## Changes in 1.0.1
  * Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead

## Changes in 1.0.0
  * Replace all references to extraData with data due to change in the Release CRDs
  * Bump the image used in the task to get a bug fix in the merge-json script

## Changes in 0.4
  * Remove releasestrategy param and result from the task
  * Collect data field instead of extraData as the Release Service API has changed

## Changes in 0.3
  * Update Tekton API to v1

## Changes in 0.2
  * Added task results for the path to each of the stored resources

## Changes in 0.1
  * Added new `subdirectory` parameter to specify a subdirectory inside the workspace dir to be used
