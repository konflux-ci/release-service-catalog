# collect-charon-params

Tekton task that collects charon configuration options from the data file. 
Charon is a tool to publish maven or npm artifacts of RedHat products the following
services:
* MRRC(maven.repository.redhat.com), which is used to host maven artifacts
* NRRC(npm.registry.redhat.com), which is used to host npm libraries
This task looks at the data file in the workspace to extract the params like
`charon.*`, `cosignPubKeySecret` and `charonAWSSecret` keys for MRRC/NRRC.
`charon.*` will be stored in a charon.env file and are emitted as task results with
other three for downstream tasks to use.

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value        |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|----------------------|
| dataJsonPath            | path to data json file                                                                                                     | No       | -                    |
| snapshotPath            | Path to the JSON string of the Snapshot spec in the data workspace                                                         | No       | -                    |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                   |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                   |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                   |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                   |
| dataDir                 | The location where data will be stored                                                                                     | Yes      | /var/workdir/release |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | -                    |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | No       | -                    |
| releasePath             | Path to the release data JSON file                                                                                         | No       | -                    |
| caTrustConfigMapName    | The name of the ConfigMap to read CA bundle data from                                                                      | Yes      | trusted-ca           |
| caTrustConfigMapKey     | The name of the key in the ConfigMap that contains the CA bundle data                                                      | Yes      | ca-bundle.crt        |
