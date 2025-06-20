# get-ocp-version

Tekton task to collect OCP version tag from FBC fragment using `skopeo inspect`.

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value           |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|-------------------------|
| snapshotPath            | Path to the JSON string of the mapped Snapshot spec in the data workspace                                                  | No       | -                       | 
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                   |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                      |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                      |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                      | 
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                      |
| dataDir                 | The location where data will be stored                                                                                     | Yes      | $(workspaces.data.path) |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | ""                      |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | No       | ""                      |

## Changes in 2.1.0
* Added compute resource limits

## Changes in 2.0.0
* This task now supports Trusted artifacts

## Changes in 1.0.0
* Using new parameter, snapshotPath, obtain the fbcFragment directly.

## Changes in 0.5.2
* Bump the utils image used in this task
  * The `get-image-architectures` script now uses `set -e` so that it fails
    if a `skopeo` or `oras` call fails

## Changes in 0.5.1
* Task updated to handle multi-arch fbc fragments

## Changes in 0.5.0
* Updated the base image used in this task

## Changes in 0.4.0
* Updated the base image used in this task

## Changes in 0.2.0
* Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead

## Changes in 0.1
* update Tekton API to v1
