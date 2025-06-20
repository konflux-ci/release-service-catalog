# reduce-snapshot

Tekton task to reduce a snapshot to a single component based on the component that the snapshot was built for.

## Parameters

| Name                                | Description                                                                                                                | Optional   | Default value                                             |
|-------------------------------------|----------------------------------------------------------------------------------------------------------------------------|------------|-----------------------------------------------------------|
| SNAPSHOT                            | String representation of Snapshot spec                                                                                     | No         | -                                                         |
| SINGLE_COMPONENT                    | Single mode component enabled                                                                                              | No         | -                                                         |
| SINGLE_COMPONENT_CUSTOM_RESOURCE    | Custom Resource to query for built component in Snapshot                                                                   | No         | -                                                         |
| SINGLE_COMPONENT_CUSTOM_RESOURCE_NS | Namespace where Custom Resource is found                                                                                   | No         | -                                                         |
| SNAPSHOT_PATH                       | The location to place the reduced Snapshot                                                                                 | No         | -                                                         |
| ociStorage                          | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes        | empty                                                     |
| ociArtifactExpiresAfter             | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes        | 1d                                                        |
| trustedArtifactsDebug               | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes        | ""                                                        |
| orasOptions                         | oras options to pass to Trusted Artifacts calls                                                                            | Yes        | ""                                                        | 
| sourceDataArtifact                  | Location of trusted artifacts to be used to populate data directory                                                        | Yes        | ""                                                        |
| dataDir                             | The location where data will be stored                                                                                     | Yes        | $(workspaces.data.path)                                   |
| taskGitUrl                          | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | Yes        | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision                     | The revision in the taskGitUrl repo to be used                                                                             | Yes        | production                                                |

## Chnages in 1.1.1
* Updates compute resource limits due to OOM kill

## Changes in 1.1.0
* Added compute resource limits

## Changes in 1.0.0
* This task now supports Trusted artifacts
