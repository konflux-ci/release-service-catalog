# extract-kmods-from-image

Tekton task to extract kernel modules from an image in a specific directory.

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value                                             |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| kmodsPath               | Path for the unsigned .ko files to be extracted from the image                                                             | No       | -                                                         |
| signedKmodsPath         | Path to store the extracted file in the workspace                                                                          | No       | -                                                         |
| snapshot                | The namespaced name (namespace/name) of the snapshot                                                                       | No       | -                                                         |
| snapshotPath            | Path to the JSON string of the mapped Snapshot spec in the data workspace                                                  | No       | -                                                         |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                                                     |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                                                        |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                                                        |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                                                        |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                                                        |
| dataDir                 | The location where data will be stored                                                                                     | Yes      | /var/workdir/release                                      |
| taskGitUrl              | The git repository URL for task and StepAction resolution                                                                  | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision         | The git revision for task and StepAction resolution                                                                        | Yes      | main                                                      |
| caTrustConfigMapName    | The name of the ConfigMap to read CA bundle data from                                                                      | Yes      | trusted-ca                                                |
| caTrustConfigMapKey     | The name of the key in the ConfigMap that contains the CA bundle data                                                      | Yes      | ca-bundle.crt                                             |
