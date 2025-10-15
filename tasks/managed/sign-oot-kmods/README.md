# sign-oot-kmods

Task to sign out-of-tree kernel modules using the internal signing server

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value                                             |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| dataPath                | Path to the data JSON in the data workspace                                                                                | No       | -                                                         |
| signedKmodsPath         | Path where the kernel modules are stored in the workspace                                                                  | No       | -                                                         |
| kerberosRealm           | Name of the key used to sign the kernel modules                                                                            | No       | -                                                         |
| signingAuthor           | Human name responsible for the signing process                                                                             | No       | -                                                         |
| checksumFingerprint     | Secret containing the host key database for SSH the server running signing                                                 | No       | -                                                         |
| checksumKeytab          | Secret containing keytab file for the Kerberos user / server                                                               | No       | -                                                         |
| signing-secret          | Secret containing the fields signHost, SignKey and SignUser                                                                | No       | -                                                         |
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
