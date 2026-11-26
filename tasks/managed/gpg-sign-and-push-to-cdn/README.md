# gpg-sign-and-push-to-cdn

Task to GPG-sign arbitrary binary artifacts via the generic-signing pipeline
and publish them to the developer portal via Exodus CDN and Content Gateway.

## Parameters

| Name                       | Description                                                                                                                | Optional | Default value                                       |
|----------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|-----------------------------------------------------|
| snapshotPath               | Path to the JSON string of the mapped Snapshot spec in the data workspace                                                  | No       | -                                                   |
| dataPath                   | Path to the JSON string of the merged data to use in the data workspace                                                    | No       | -                                                   |
| requester                  | Name of the user that requested the signing, for auditing purposes (passed as onbehalfof)                                  | No       | -                                                   |
| requestTimeout             | InternalRequest timeout                                                                                                    | Yes      | 1800                                                |
| concurrentLimit            | The maximum number of signing requests to run in parallel                                                                  | Yes      | 4                                                   |
| pipelineRunUid             | The uid of the current pipelineRun. Used as a label value when creating internal requests                                  | No       | -                                                   |
| signingRepo                | Git repository URL containing the signing tasks                                                                            | Yes      | https://gitlab.cee.redhat.com/signing/signing.git   |
| signingRevision            | Git revision (branch, tag, or commit) in the signing repository                                                            | Yes      | main                                                |
| signPipeline               | Name of the internal pipeline to use for middleware signing                                                                | Yes      | generic-signing                                     |
| signPipelineServiceAccount | Service account to use for the signing pipeline                                                                            | Yes      | signing-pipeline-sa                                 |
| ociStorage                 | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                                               |
| ociArtifactExpiresAfter    | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                                                  |
| trustedArtifactsDebug      | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                                                  |
| orasOptions                | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                                                  |
| sourceDataArtifact         | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                                                  |
| dataDir                    | The location where data will be stored                                                                                     | Yes      | /var/workdir/release                                |
| taskGitUrl                 | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | -                                                   |
| taskGitRevision            | The revision in the taskGitUrl repo to be used                                                                             | No       | -                                                   |
| signMethod                 | Signing method to use for artifact signing                                                                                 | Yes      | detachsign                                          |
| taDockerConfigSecret       | Secret for Trusted Artifact registry authentication                                                                        | Yes      | quay-token-konflux-release-trusted-artifacts-secret |
| caTrustConfigMapName       | The name of the ConfigMap to read CA bundle data from                                                                      | Yes      | trusted-ca                                          |
| caTrustConfigMapKey        | The name of the key in the ConfigMap that contains the CA bundle data                                                      | Yes      | ca-bundle.crt                                       |
