# prepare-fbc-release

A tekton task to prepare FBC Release by collecting a valid
OCP version for each component from given
containerImage(fbcFragment) in the snapshot, and update
the fromIndex, targetIndex and binaryImage with collected
OCP version and store updated values to snapshot respective
to each component, so other task can use them.

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value           |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|-------------------------|
| snapshotPath            | Path to the JSON string of the Snapshot spec in the data workspace                                                         | No       | -                       |
| dataPath                | Path to the JSON string of the merged data to use in the data workspace                                                    | No       | -                       |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                   |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                      |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                      |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                      | 
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                      |
| dataDir                 | The location where data will be stored                                                                                     | Yes      | $(workspaces.data.path) |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | ""                      |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | No       | ""                      |

## Changes in 2.0.0
* This task now supports Trusted artifacts

## Changes in 1.5.0
* Added compute resource limits

## Changes in 1.4.1
* The task now support multiarchitecture images
* Changed to use `mktemp` to generate the temporary snapshot json file

## Changes in 1.4.0
* Removed the `binaryImage` parameter so IIB can auto resolve it

## Changes in 1.3.1
* Changed the replace_tag function to only replace the version when the {{ OCP_VERSION }}
  placeholder is given
* Added the validateOcpVersion function to check if the index version matches with the one
  found in the base image

## Changes in 1.3.0
* updated the base image used in this task

## Changes in 1.2.0
* updated the base image used in this task

## Changes in 1.1.0
* remove `dataPath` and `snapshotPath` default values
