# sign-image-cosign-keyless

Tekton task to sign container images in snapshot by cosign in keyless mode

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value                    |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|----------------------------------|
| snapshotPath            | Path to the JSON string of the mapped Snapshot spec in the data workspace                                                  | No       | -                                |
| retries                 | Retry cosign N times                                                                                                       | Yes      | 3                                |
| concurrentLimit         | The maximum number of concurrent cosign signing jobs                                                                       | Yes      | 90                               |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                            |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                               |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                               |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                               |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                               |
| dataDir                 | The location where data will be stored                                                                                     | Yes      | /var/workdir/release             |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | -                                |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | No       | -                                |
| caTrustConfigMapName    | The name of the ConfigMap to read CA bundle data from                                                                      | Yes      | trusted-ca                       |
| caTrustConfigMapKey     | The name of the key in the ConfigMap that contains the CA bundle data                                                      | Yes      | ca-bundle.crt                    |
| caCertPath              | Path to CA certificate bundle for TLS verification with self-signed certificates                                           | Yes      | /etc/pki/tls/certs/ca-bundle.crt |
| keylessOIDCIssuer       | OIDC issuer for keyless signing                                                                                            | No       | -                                |
| keylessFulcioURL        | Fulcio URL for keyless signing                                                                                             | No       | -                                |
| keylessRekorURL         | rekor URL for keyless signing                                                                                              | No       | -                                |
| keylessTufURL           | TUF URL for keyless signing                                                                                                | No       | -                                |
