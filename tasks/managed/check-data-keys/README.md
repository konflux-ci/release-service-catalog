# check-data-keys

Tekton task that validates data keys against a schema to ensure that all required keys for a system(s) are present
and correctly formatted. The system(s) passed into the `systems` parameter become required.
The schema validation also applies to all data passed into the `dataPath` parameter,
meaning all the data keys must be allowed and formatted correctly.

For example, if `releaseNotes` is passed as a system and the data file does not have all the required
releaseNotes keys, the schema will give validation errors, and the task will fail.

The validation schema is defined in `schema/dataKeys.json` in this repository.

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value                                                                                                    |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|------------------------------------------------------------------------------------------------------------------|
| dataPath                | Path to the JSON string of the merged data to use                                                                          | No       | -                                                                                                                |
| schema                  | URL to the JSON schema file to validate the data against                                                                   | Yes      | https://raw.githubusercontent.com/konflux-ci/release-service-catalog/refs/heads/development/schema/dataKeys.json |
| systems                 | The systems to check that all data keys are present for                                                                    | Yes      | ""                                                                                                               |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                                                                                                            |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                                                                                                               |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                                                                                                               |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                                                                                                               |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                                                                                                               |
| dataDir                 | The location where data will be stored                                                                                     | Yes      | /var/workdir/release                                                                                             |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | -                                                                                                                |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | No       | -                                                                                                                |
| caTrustConfigMapName    | The name of the ConfigMap to read CA bundle data from                                                                      | Yes      | trusted-ca                                                                                                       |
| caTrustConfigMapKey     | The name of the key in the ConfigMap that contains the CA bundle data                                                      | Yes      | ca-bundle.crt                                                                                                    |
