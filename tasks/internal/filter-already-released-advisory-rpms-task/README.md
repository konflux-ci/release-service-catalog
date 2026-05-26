# filter-already-released-advisory-rpms-task

Filters out RPMs from a snapshot if they are already published in an advisory
stored in the GitLab advisory repo. Returns lists of unreleased RPMs and
RPMs found in advisories (for digest validation by the calling task).

## Parameters

| Name                                            | Description                                                                                | Optional | Default value                                       |
|-------------------------------------------------|--------------------------------------------------------------------------------------------|----------|-----------------------------------------------------|
| transformedSnapshot                             | Base64 string of gzipped JSON array of RPM entries with purls                              | No       | -                                                   |
| origin                                          | The origin workspace for the release CR                                                    | No       | -                                                   |
| advisory_secret_name                            | Name of the secret containing advisory GitLab metadata                                     | No       | -                                                   |
| internalRequestPipelineRunName                  | Name of the PipelineRun that requested this task                                           | No       | -                                                   |
| ociStorage                                      | The OCI repository to store results artifact                                               | No       | -                                                   |
| trusted_artifacts_dockerconfig_json_secret_name | The name of the secret that contains the dockerconfig json for trusted artifact operations | Yes      | quay-token-konflux-release-trusted-artifacts-secret |
| orasOptions                                     | oras options to pass to oras calls                                                         | Yes      | ""                                                  |
| caTrustConfigMapName                            | The name of the ConfigMap to read CA bundle data from                                      | Yes      | trusted-ca                                          |
| caTrustConfigMapKey                             | The name of the key in the ConfigMap that contains the CA bundle data                      | Yes      | ca-bundle.crt                                       |
