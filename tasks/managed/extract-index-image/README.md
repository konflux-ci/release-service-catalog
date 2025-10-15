# extract-index-image

Extract the index image fields from the inputDataFile

The inputDataFile is a result from another task which includes the workspace name in it. Thus,
the workspace name for this task *must* be input.

## Parameters

| Name                       | Description                                                                                                                | Optional | Default value        |
|----------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|----------------------|
| inputDataFile              | Result from another task which includes the workspace name in it                                                           | No       | -                    |
| resultsDirPath             | Path to the results directory in the data workspace                                                                        | No       | -                    |
| internalRequestResultsFile | Path to the results file of the InternalRequest build result                                                               | No       | -                    |
| ociStorage                 | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                |
| ociArtifactExpiresAfter    | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                   |
| trustedArtifactsDebug      | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                   |
| orasOptions                | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                   |
| sourceDataArtifact         | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                   |
| dataDir                    | The location where data will be stored                                                                                     | Yes      | /var/workdir/release |
| taskGitUrl                 | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | -                    |
| taskGitRevision            | The revision in the taskGitUrl repo to be used                                                                             | No       | -                    |
| caTrustConfigMapName       | The name of the ConfigMap to read CA bundle data from                                                                      | Yes      | trusted-ca           |
| caTrustConfigMapKey        | The name of the key in the ConfigMap that contains the CA bundle data                                                      | Yes      | ca-bundle.crt        |
