# prepare-and-finalize-artifacts

Task to prepare the workspace by selecting the correct input artifact and create a final trusted artifact.

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value                                             |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                                                     |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                                                        |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                                                        |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                                                        |
| baseDataArtifact        | Location of trusted artifact from sign task                                                                                | Yes      | ""                                                        |
| rpmDataArtifact         | Location of trusted artifact from optional build-rpms task                                                                 | Yes      | ""                                                        |
| dataDir                 | The location where data will be stored                                                                                     | Yes      | /var/workdir/release                                      |
| taskGitUrl              | The git repository URL for task and StepAction resolution                                                                  | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision         | The git revision for task and StepAction resolution                                                                        | Yes      | main                                                      |
