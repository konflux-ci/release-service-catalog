# sign-checksum-blob

Submits a direct signing request for the release SHA256SUMS checksum file
via the signing service's `generic-signing` pipeline.

The checksum file is isolated into its own Trusted Artifact (the
`generic-signing` pipeline signs every file in the input artifact) and an
InternalRequest is submitted with `signMethod=detachsign`. The TA with the
result is then downloaded and finalized into the output format

## Idempotent Behavior

This task is **idempotent**. If a valid signature file (`.sig`) already exists in the binaries directory:
- The task will validate the existing signature in the prepare step
- If valid, it will skip the signing steps and keep the signature as-is
- If invalid or corrupted, it will remove the file and submit a fresh request

This allows the task to be safely retried without creating duplicate signing requests or wasting resources.

## Signing data parameters

 The signing configuration should be set as `data.sign` in the _releasePlanAdmission_. The data should be set in the
 _ReleasePlanAdmission_ as follows:

```
data:
    sign:
        configMapName: <configmap name>
```

The named ConfigMap (default `signing-config-map`) must expose `SIG_KEY_NAME`, used as the signing key name.

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value                                     |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|---------------------------------------------------|
| dataPath                | Path to the JSON string of the merged data to use in the data workspace                                                    | No       | -                                                 |
| requester               | Name of the user that requested the signing, for auditing purposes                                                         | No       | -                                                 |
| requestTimeout          | InternalRequest timeout                                                                                                    | Yes      | 1800                                              |
| binariesPath            | The directory inside the workspace where the binaries are stored                                                           | Yes      | binaries                                          |
| pipelineRunUid          | The uid of the current pipelineRun. Used as a label value when creating internal requests                                  | No       | -                                                 |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                                             |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                                                |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                                                |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                                                |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                                                |
| dataDir                 | The location where data will be stored                                                                                     | Yes      | /var/workdir/release                              |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | -                                                 |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | No       | -                                                 |
| signingRepo             | Git repository URL containing the generic-signing pipeline                                                                 | Yes      | https://gitlab.cee.redhat.com/signing/signing.git |
| signingRevision         | Git revision (branch, tag, or commit) in the signing repository                                                            | Yes      | 9b0756bc38bc547dbf575a5db1b8c001cda62c67          |
| caTrustConfigMapName    | The name of the ConfigMap to read CA bundle data from                                                                      | Yes      | trusted-ca                                        |
| caTrustConfigMapKey     | The name of the key in the ConfigMap that contains the CA bundle data                                                      | Yes      | ca-bundle.crt                                     |
