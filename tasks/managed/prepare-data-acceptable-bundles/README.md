# prepare-data-acceptable-bundles

Tekton task to prepare data-acceptable-bundles repositories by modifying the snapshot.

This task reads the snapshot file, extracts repository URLs from components that have
public: true set, transforms them to the corresponding data-acceptable-bundles repository
format, and adds them to the snapshot as components marked with public: true.
For example: quay.io/org/source-repo -> quay.io/org/data-acceptable-bundles

Only components with explicit public: true are processed, as these are the components
that will be processed by the make-repo-public task. Components without public: true
(or with public: false) are ignored.

This task does NOT call external APIs, mount secrets, or use tokens.
It only processes the snapshot data and modifies it to include data-acceptable-bundles repositories.

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value        |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|----------------------|
| snapshotPath            | Path to the JSON string of the Snapshot spec in the data workspace                                                         | No       | -                    |
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
