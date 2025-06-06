# publish-index-image

Publish a built FBC index image using skopeo

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value           |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|-------------------------|
| dataPath                | Path to the JSON string of the merged data to use in the data workspace                                                    | No       | -                       |
| sourceIndex             | Pullspec to pull the image from                                                                                            | No       | -                       |
| targetIndex             | Pullspec to push the image to                                                                                              | No       | -                       |
| retries                 | Number of skopeo retries                                                                                                   | Yes      | 0                       |
| requestTimeout          | Max seconds waiting for the status update                                                                                  | Yes      | 360                     |
| buildTimestamp          | Build timestamp for the publishing image                                                                                   | No       | -                       |
| pipelineRunUid          | The uid of the current pipelineRun. Used as a label value when creating internal requests                                  | No       | -                       |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                   |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                      |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                      |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                      | 
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                      |
| dataDir                 | The location where data will be stored                                                                                     | Yes      | $(workspaces.data.path) |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | ""                      |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | No       | ""                      |

## Changes in 5.1.0
* Added compute resource limits

## Changes in 5.0.0
* This task now supports Trusted artifacts

## Changes in 4.0.0
* Added taskGiturl and taskGitRevision parameters to be passed to the internalRequest
* The pipeline is called via git resolver now instead of cluster resolver
  * This was done by changing from `-r` to `--pipeline` in the `internal-request` call
  * The base image was updated to include this new functionality

## Changes in 3.3.0
* updated the base image used in this task

## Changes in 3.2.0
* updated the base image used in this task

## Changes in 3.1.0
* remove `dataPath` default value

## Changes in 3.0.0
* The internalrequest CR is created with a label specifying the pipelinerun uid with the new pipelineRunUid parameter
  * This change comes with a bump in the image used for the task

## Changes in 2.0.0
* Add the parameter `buildTimestamp` to push also a timestamp-based tag

## Changes in 1.0.0
* Refactor to use the `internal-request` script

## Changes in 0.3.0
* Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead

## Changes in 0.2
* update Tekton API to v1

## Changes in 0.1
* adds `inputDataFile` parameter to read the image source from it
