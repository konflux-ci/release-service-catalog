# rh-sign-rpm

Tekton task to create internalrequests to sign RPMs

## Parameters

| Name                       | Description                                                                                                                | Optional | Default value                                     |
|----------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|---------------------------------------------------|
| dataPath                   | Path to the JSON file of the merged data to use in the data workspace                                                      | No       | -                                                 |
| artifactsJsonPath          | Path to the artifacts.json file in the data workspace (pulp-tool format with RPM metadata)                                 | Yes      | artifacts.json                                    |
| requester                  | Name of the user that requested the signing, for auditing purposes                                                         | No       | -                                                 |
| requestTimeout             | InternalRequest timeout                                                                                                    | Yes      | 1800                                              |
| pipelineRunUid             | The uid of the current pipelineRun. Used as a label value when creating internal requests                                  | No       | -                                                 |
| ociStorage                 | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                                             |
| sourceDataArtifact         | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                                                |
| ociArtifactExpiresAfter    | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                                                |
| trustedArtifactsDebug      | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                                                |
| orasOptions                | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                                                |
| dataDir                    | The location where data will be stored                                                                                     | Yes      | /var/workdir/release                              |
| taskGitUrl                 | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | -                                                 |
| taskGitRevision            | The revision in the taskGitUrl repo to be used                                                                             | No       | -                                                 |
| signedRpmsDomain           | The domain to use for pushing signed RPMs                                                                                  | Yes      | rok-storage                                       |
| pipelineImage              | Container image to use for the signing pipeline                                                                            | Yes      | quay.io/konflux-ci/signing:latest                 |
| signingRepo                | Git repository URL containing the signing tasks                                                                            | Yes      | https://gitlab.cee.redhat.com/signing/signing.git |
| signingRevision            | Git revision (branch, tag, or commit) in the signing repository                                                            | Yes      | main                                              |
| signPipeline               | Name of the internal pipeline to use for RPM signing                                                                       | Yes      | direct-rpm-signing                                |
| signPipelineServiceAccount | Service account to use for the signing pipeline                                                                            | Yes      | signing-pipeline-sa                               |
| force                      | When uploading signed RPMs to Pulp, overwrite existing artifacts                                                           | Yes      | false                                             |
