# extract-index-image

Extract the index image fields from the inputDataFile

The inputDataFile is a result from another task which includes the workspace name in it. Thus,
the workspace name for this task *must* be input.

## Parameters

| Name                        | Description                                                                                                                | Optional | Default value           |
|-----------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|-------------------------|
| inputDataFile               | File to read json data from                                                                                                | No       | -                       |
| resultsDirPath              | Path to results directory in the data workspace                                                                            | No       | -                       |
| internalRequestResultsFile  | Path to the results file of the InternalRequest build result | No       | -             |
| ociStorage                  | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                   |
| ociArtifactExpiresAfter     | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                      |
| trustedArtifactsDebug       | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                      |
| orasOptions                 | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                      | 
| sourceDataArtifact          | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                      |
| dataDir                     | The location where data will be stored                                                                                     | Yes      | $(workspaces.data.path) |
| taskGitUrl                  | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | ""                      |
| taskGitRevision             | The revision in the taskGitUrl repo to be used                                                                             | No       | ""                      |

## Changes in 2.2.0
* Changed to allow processing of multiple components in the snapshot. New parameter `internalRequestResultsFile`
  is added.

## Changes in 2.1.0
* Added compute resource limits

## Changes in 2.0.0
* This task now supports Trusted artifacts

## Changes in 1.1.1
* Fix shellcheck/checkton linting issues in the task and tests

## Changes in 1.1.0
* Updated the base image used in this task

## Changes in 1.0.0
* The task now writes the index_image and index_image_resolved values to a results json file in the workspace

## Changes in 0.4.0
* Updated the base image used in this task

## Changes in 0.2.0
* Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead

## Changes in 0.1
* update Tekton API to v1
