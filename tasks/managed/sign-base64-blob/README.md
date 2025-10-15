# sign-base64-blob

Creates an InternalRequest to sign a base64 encoded blob

## Idempotent Behavior

This task is **idempotent**. If a valid signature file (`.sig`) already exists in the binaries directory:
- The task will validate the existing signature
- If valid, it will skip the signing operation and exit successfully
- If invalid or corrupted, it will remove the file and re-sign

This allows the task to be safely retried without creating duplicate signing requests or wasting resources.

## Signing data parameters

 The signing configuration should be set as `data.sign` in the _releasePlanAdmission_. The data should be set in the
 _ReleasePlanAdmission_ as follows:

```
data:
    sign:
        pipelineImage: <image pullspec>
        configMapName: <configmap name>
```

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value        |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|----------------------|
| dataPath                | Path to the JSON string of the merged data to use in the data workspace                                                    | No       | -                    |
| blob                    | The base64 encoded blob to be signed                                                                                       | No       | -                    |
| requester               | Name of the user that requested the signing, for auditing purposes                                                         | No       | -                    |
| requestTimeout          | InternalRequest timeout                                                                                                    | Yes      | 1800                 |
| binariesPath            | The directory inside the workspace where the binaries are stored                                                           | Yes      | binaries             |
| pipelineRunUid          | The uid of the current pipelineRun. Used as a label value when creating internal requests                                  | No       | -                    |
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
