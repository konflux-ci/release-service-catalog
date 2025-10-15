# build-oot-kmods-rpms

Task to build RPM packages containing signed out-of-tree kernel modules

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value                                             |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| signedKmodsPath         | Path where the signed kernel modules are stored in the workspace                                                           | No       | -                                                         |
| rpmOutputPath           | Path where the built RPM packages will be stored                                                                           | Yes      | rpms                                                      |
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
