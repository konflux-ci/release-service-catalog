# collect-data

Tekton task to collect the information added to the data field of the release resources.

The purpose of this task is to collect all the data and supply it to the other task in the pipeline by creating
a json file called `data.json` in the workspace.

This task also stores the passed resources as json files in a workspace.

The parameters to this task are lowercase instead of camelCase because they are passed from the operator, and the
operator passes them as lowercase.

A task result is returned for each resource with the relative path to the stored JSON for it in the workspace. There is
also a task result for the fbcFragment extracted from the snapshot's first component.

## Parameters

| Name                 | Description                                        | Optional | Default value |
|----------------------|----------------------------------------------------|----------|---------------|
| release              | Namespaced name of the Release                     | No       | -             |
| releaseplan          | Namespaced name of the ReleasePlan                 | No       | -             |
| releaseplanadmission | Namespaced name of the ReleasePlanAdmission        | No       | -             |
| snapshot             | Namespaced name of the Snapshot                    | No       | -             |
| subdirectory         | Subdirectory inside the workspace to be used.      | Yes      | -             |

## Changes since 1.0.1
  * Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead

## Changes since 1.0.0
  * Replace all references to extraData with data due to change in the Release CRDs
  * Bump the image used in the task to get a bug fix in the merge-json script

## Changes since 0.4
  * Remove releasestrategy param and result from the task
  * Collect data field instead of extraData as the Release Service API has changed

## Changes since 0.3
  * Update Tekton API to v1

## Changes since 0.2
  * Added task results for the path to each of the stored resources

## Changes since 0.1
  * Added new `subdirectory` parameter to specify a subdirectory inside the workspace dir to be used
