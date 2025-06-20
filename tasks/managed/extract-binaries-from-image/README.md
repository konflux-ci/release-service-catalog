# extract-binaries-from-image

Tekton task that extracts binaries to be released on github.com from an image.

The path to the directory inside the provided workspace where the binaries were
saved is provided as a result.

The binaries must be stored at the same `image_binaries_path` for each component
passed.

## Parameters

| Name                       | Description                                                                                                                | Optional  | Default value           |
|----------------------------|----------------------------------------------------------------------------------------------------------------------------|-----------|-------------------------|
| image_binaries_path        | Path inside the image where the binaries to extract are stored                                                             | Yes       | /releases               |
| snapshotPath               | Path to the JSON string of the mapped Snapshot spec in the data workspace                                                  | No        | -                       |
| subdirectory               | Subdirectory inside the workspace to be used for storing the binaries                                                      | Yes       | ""                      |
| dataPath                   | Path to the JSON string of the merged data to use in the data workspace                                                    | No        | -                       |
| ociStorage                 | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes       | empty                   |
| ociArtifactExpiresAfter    | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes       | 1d                      |
| trustedArtifactsDebug      | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes       | ""                      |
| orasOptions                | oras options to pass to Trusted Artifacts calls                                                                            | Yes       | ""                      |
| sourceDataArtifact         | Location of trusted artifacts to be used to populate data directory                                                        | Yes       | ""                      |
| dataDir                    | The location where data will be stored                                                                                     | Yes       | $(workspaces.data.path) |
| taskGitUrl                 | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No        | ""                      |
| taskGitRevision            | The revision in the taskGitUrl repo to be used                                                                             | No        | ""                      |

## Changes in 3.0.1
* Add retry for skopeo copy

## Changes in 3.0.0
* This task now supports Trusted artifacts

## Changes in 2.2.0
* Added compute resource limits

## Changes in 2.1.3
* Add comprobation to only extract from the layer with the releases directory

## Changes in 2.1.2
* Fix typo in fetching DESIRED_COMPONENTS_LIST `content-gateway` -> `contentGateway`

## Changes in 2.1.1
* Fix shellcheck/checkton linting issues in the task and tests

## Changes in 2.1.0
* updated the base image used in this task

## Changes in 2.0.0
* support multiple components in snapshot

## Changes in 1.2.0
* updated the base image used in this task

## Changes in 1.1.0
* remove `snapshotPath` default value
