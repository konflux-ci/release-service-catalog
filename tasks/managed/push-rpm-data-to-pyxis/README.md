# push-rpm-data-to-pyxis

Tekton task that extracts all rpms from the sboms and pushes them to Pyxis as an RPM Manifest.
In addition, it will also update ContainerImage.content_sets field in Pyxis to include
all repository_id strings found in rpm purl strings in the sboms.

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value           |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|-------------------------|
| pyxisJsonPath           | Path to the JSON string of the saved Pyxis data in the data workspace                                                      | No       | -                       |
| pyxisSecret             | The kubernetes secret to use to authenticate to Pyxis. It needs to contain two keys: key and cert                          | No       | -                       |
| server                  | The server type to use. Options are 'production','production-internal,'stage-internal' and 'stage'                         | Yes      | production              |
| concurrentLimit         | The maximum number of images to be processed at once                                                                       | Yes      | 20                      |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                   |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                      |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                      |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                      |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                      |
| subdirectory            | Subdirectory inside the workspace to be used                                                                               | Yes      | ""                      |
| dataDir                 | The location where data will be stored                                                                                     | Yes      | $(workspaces.data.path) |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | -                       |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | No       | -                       |
