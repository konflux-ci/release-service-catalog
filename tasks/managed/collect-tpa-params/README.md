# collect-tpa-params

Tekton task that collects the TPA server option from the data file.
It can either parse the cluster configuration stored in konflux-info
namespace or parse a dataPath JSON file for values.

If the desired configmap is present in konflux-info, it will be used
as a preferred option.

Otherwise it outputs values based on the value of the "atlas.server" or
"tpa.servers" field ("stage" or "production"), the output values are used
to push SBOMs to TPA. Also outputs results used to push SBOMs to an S3
bucket.

If the configmap in konflux-info cannot be parsed and no TPA fields
are present in the data file, the task fails.

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value                 |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|-------------------------------|
| dataPath                | Path to the JSON string of the merged data containing the TPA config                                                       | Yes      | ""                            |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                         |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                            |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                            |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                            |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                            |
| dataDir                 | The location where data will be stored                                                                                     | Yes      | /var/workdir/release          |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | -                             |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | No       | -                             |
| caTrustConfigMapName    | The name of the ConfigMap to read CA bundle data from                                                                      | Yes      | trusted-ca                    |
| caTrustConfigMapKey     | The name of the key in the ConfigMap that contains the CA bundle data                                                      | Yes      | ca-bundle.crt                 |
| caCertPath              | Path to CA certificate bundle for TLS verification with self-signed certificates                                           | Yes      | /mnt/trusted-ca/ca-bundle.crt |
| configMapNamespace      | The namespace where the ConfigMap is located                                                                               | Yes      | konflux-info                  |
| configMapName           | The name of the ConfigMap to read TPA parameters from                                                                      | Yes      | cluster-config                |
