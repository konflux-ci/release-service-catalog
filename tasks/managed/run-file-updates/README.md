# run-file-udpates

Tekton task to create InternalRequests for each repository that needs to be updated. This information is extracted from
the field `spec.data.fileUpdates` in the ReleasePlanAdmission resource.

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value            |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|--------------------------|
| jsonKey                 | JSON key where the information is defined                                                                                  | Yes      | .spec.data.fileUpdates[] |
| fileUpdatesPath         | Path to the JSON file containing the key                                                                                   | No       | -                        |
| snapshotPath            | Path to the JSON string of the Snapshot spec in the data workspace                                                         | No       | -                        |
| request                 | Type of request to be created                                                                                              | Yes      | file-updates             |
| synchronously           | Whether the task should wait for InternalRequests to complete                                                              | Yes      | true                     |
| pipelineRunUid          | The uid of the current pipelineRun. Used as a label value when creating internal requests                                  | No       | -                        |
| resultsDirPath          | Path to results directory in the data workspace                                                                            | No       | -                        |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                    |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                       |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                       |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                       | 
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                       |
| dataDir                 | The location where data will be stored                                                                                     | Yes      | $(workspaces.data.path)  |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | ""                       |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | No       | ""                       |

## Changes in 4.1.0
* Added compute resource limits

## Changes in 4.0.0
* This task now supports Trusted artifacts

## Changes in 3.0.0
* Added taskGiturl and taskGitRevision parameters to be passed to the internalRequest
* The pipeline is called via git resolver now instead of cluster resolver
  * This was done by changing from `-r` to `--pipeline` in the `internal-request` call
  * The base image was updated to include this new functionality

## Changes in 2.0.2
* fix linting issues

## Changes in 2.0.1
* fix typo in default value for `jq`

## Changes in 2.0.0
* new mandatory parameter resultsDirPath added
* the task now supplies created merge requests to update Release CR status task.
* the task can use a secret name supplied in the data section which will be passed
  to the internal request.
* The internal request default name was updated
* Fix linting issues and added additional test
* internalRequestPipelineRunName and internalRequestTaskRunName is now logged to help
  with debugging

## Changes in 1.3.0
* Updated the base image used in this task

## Changes in 1.2.0
* Updated the base image used in this task

## Changes in 1.1.0
* remove `snapshotPath` default value

## Changes in 1.0.0
* The internalrequest CRs are created with a label specifying the pipelinerun uid with the new pipelineRunUid parameter
  * This change comes with a bump in the image used for the task

## Changes in 0.5.0
* Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead

## Changes in 0.4.1
* jsonKey default changed to .spec.data.fileUpdates{} due to API changes

## Changes in 0.3
* update Tekton API to v1

## Changes in 0.2
* application name from snapshot is now provided to update-paths

## Changes in 0.1
* adds parameter `snapshotPath`.
* calls `update-paths` script to run the `{{ }}` enclosed yq updates set in the `paths` key
  of the defined `fileUpdatesPath` file.
