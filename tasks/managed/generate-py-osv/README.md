# generate-py-osv

Generate OSV security metadata for remediated Python artifacts. Reads the
build-index.json OCI referrer from each component image and runs
`slan-cuan generate-security-metadata` (fath-cuan process_osv) with OSIDB
enrichment. OSV output is threaded onward on the trusted artifact.

## Parameters

| Name                       | Description                                                                                           | Optional | Default value                                 |
|----------------------------|-------------------------------------------------------------------------------------------------------|----------|-----------------------------------------------|
| SNAPSHOT_PATH              | Path to the reduced snapshot spec (relative to dataDir).                                              | No       | -                                             |
| OSIDB_API_URL              | The base URL of the OSIDB API                                                                         | Yes      | ""                                            |
| OSIDB_KERBEROS_PRINCIPAL   | Kerberos principal used to authenticate to OSIDB                                                      | Yes      | ""                                            |
| OSIDB_KERBEROS_KEYTAB_PATH | Path (inside the container) to the mounted OSIDB Kerberos keytab                                      | Yes      | /var/run/secrets/osidb-keytab/keytab          |
| OSIDB_KEYTAB_SECRET_NAME   | Secret holding the OSIDB Kerberos keytab.                                                             | Yes      | osidb-keytab-secret                           |
| BUILD_INDEX_MEDIA_TYPE     | OCI artifact type used to discover the build-index referrer                                           | Yes      | application/vnd.lightwell.build-index.v1+json |
| sourceDataArtifact         | Trusted Artifact containing the reduced snapshot spec and files                                       | No       | -                                             |
| dataDir                    | The location where data will be stored                                                                | Yes      | /var/workdir                                  |
| ociArtifactExpiresAfter    | Expiration date for the trusted artifacts created                                                     | Yes      | 1d                                            |
| orasOptions                | oras options to pass to Trusted Artifacts calls                                                       | Yes      | ""                                            |
| trustedArtifactsDebug      | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                | Yes      | ""                                            |
| taskGitUrl                 | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored | No       | -                                             |
| taskGitRevision            | The revision in the taskGitUrl repo to be used                                                        | No       | -                                             |
| ociStorage                 | The OCI repository where the Trusted Artifacts are stored                                             | No       | -                                             |
