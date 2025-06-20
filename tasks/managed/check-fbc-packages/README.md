# check-fbc-packages

Task to check that the packages being shipped in an fbc contribution are in the allow list provided in the dataPath.

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value           |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|-------------------------|
| snapshotPath            | Path to the JSON string of the mapped Snapshot spec in the data workspace                                                  | No       | -                       |
| dataPath                | Path to the JSON string of the merged data to use in the data workspace                                                    | No       | -                       |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                   |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                      |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                      |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                      | 
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                      |
| dataDir                 | The location where data will be stored                                                                                     | Yes      | $(workspaces.data.path) |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | ""                      |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | No       | ""                      |

## Changes in 1.0.0
* This task now supports Trusted artifacts

## Changes in 0.5.1
* Up memory resource limit from 512Mi to 1Gi
  * Saw task OOMKilled in E2E with 512Mi

## Changes in 0.5.0
* Added compute resource limits

## Changes in 0.4.1
* fix linting issues in check-fbc-package task

## Changes in 0.4.0
* updated the base image used in this task

## Changes in 0.3.0
* updated the base image used in this task

## Changes in 0.2.0
* remove default values of `snapshotPath` and `dataPath` parameters
