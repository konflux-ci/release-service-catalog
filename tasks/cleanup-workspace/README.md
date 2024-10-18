# cleanup-workspace

Tekton task to delete a given directory in a passed workspace and cleanup InternalRequests related to the current PipelineRun.

## Parameters

| Name           | Description                                                                                                      | Optional | Default value |
|----------------|------------------------------------------------------------------------------------------------------------------|----------|---------------|
| subdirectory   | The directory to remove within the workspace                                                                     | No       | -             |
| delay          | Time in seconds to delay execution. Needed to allow other finally tasks to access workspace before being deleted | Yes      | 60            |
| pipelineRunUid | The uid of the current pipelineRun. It is only available at the pipeline level                                   | Yes      | ""            |

## Changes in 0.8.2
* Fix error if internalrequests are not installed on cluster

## Changes in 0.8.1
* Fix linting issues in this task

## Changes in 0.8.0
* Updated the base image used in this task

## Changes in 0.7.0
* Updated the base image used in this task

## Changes in 0.6.0
* The task now removes all internalrequest CRs for the current pipelinerun via the pipelineRunUid parameter

## Changes in 0.4.0
* Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead

## Changes in 0.3.0
* Add delay parameter with a default of 60 (in seconds)

## Changes in 0.2
* Update Tekton API to v1

## Changes in 0.1
* Base image was changed from `release-utils` to `release-base-image`
* The syntax for `taskRef.bundle` and `pipelineRef.bundle` is deprecated,
  bundles resolver is used with new format.
