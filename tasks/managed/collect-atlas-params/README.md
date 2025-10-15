# collect-atlas-params

Tekton task that collects the Atlas server option from the data file. Based on
the value of the "atlas.server" field ("stage" or "production"), outputs results
used to push SBOMs to Atlas. Also outputs results used to push SBOMs to an S3
bucket. If no Atlas fields are present in the data file, it outputs empty
strings as results, indicating that the Atlas push should be skipped.

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value        |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|----------------------|
| dataPath                | Path to the JSON string of the merged data containing the Atlas config                                                     | No       | -                    |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                   |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                   |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                   |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                   |
| dataDir                 | The location where data will be stored                                                                                     | Yes      | /var/workdir/release |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | -                    |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | No       | -                    |
| caTrustConfigMapName    | The name of the ConfigMap to read CA bundle data from                                                                      | Yes      | trusted-ca           |
| caTrustConfigMapKey     | The name of the key in the ConfigMap that contains the CA bundle data                                                      | Yes      | ca-bundle.crt        |
