# sign-index-image

Creates an InternalRequest to sign an index image

## Signing data parameters

 The signing configuration should be set as `data.sign` in the _releasePlanAdmission_. Previously it used to be
 set also in the `data.fbc`. The data should be set in the _ReleasePlanAdmission_ as follows:

```
data:
    sign:
        request: <signing pipeline name>
        pipelineImage: <image pullspec>
        configMapName: <configmap name>
```

## Parameters

| Name                     | Description                                                                                                                                                                                                           | Optional | Default value        |
|--------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------|----------------------|
| dataPath                 | Path to the JSON string of the merged data to use in the data workspace                                                                                                                                               | No       | -                    |
| releasePlanAdmissionPath | Path to the JSON string of the releasePlanAdmission in the data workspace                                                                                                                                             | No       | -                    |
| manifestListDigests      | The manifest digests for each arch in manifest list                                                                                                                                                                   | No       | -                    |
| requester                | Name of the user that requested the signing, for auditing purposes                                                                                                                                                    | No       | -                    |
| requestTimeout           | InternalRequest timeout                                                                                                                                                                                               | Yes      | 1800                 |
| pipelineRunUid           | The uid of the current pipelineRun. Used as a label value when creating internal requests                                                                                                                             | No       | -                    |
| fbcResultsPath           | Path to the JSON file in the data workspace containing fbc results                                                                                                                                                    | No       | -                    |
| concurrentLimit          | The maximum number of concurrent signing requests                                                                                                                                                                     | Yes      | 16                   |
| ociStorage               | The OCI repository where the Trusted Artifacts are stored                                                                                                                                                             | Yes      | empty                |
| ociArtifactExpiresAfter  | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire                                                                                            | Yes      | 1d                   |
| trustedArtifactsDebug    | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                                                                                                                | Yes      | ""                   |
| orasOptions              | oras options to pass to Trusted Artifacts calls                                                                                                                                                                       | Yes      | ""                   |
| sourceDataArtifact       | Location of trusted artifacts to be used to populate data directory                                                                                                                                                   | Yes      | ""                   |
| dataDir                  | The location where data will be stored                                                                                                                                                                                | Yes      | /var/workdir/release |
| taskGitUrl               | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                                                                                                                 | No       | -                    |
| taskGitRevision          | The revision in the taskGitUrl repo to be used                                                                                                                                                                        | No       | -                    |
| pyxisServer              | The server type to use. Options are 'production','production-internal,'stage-internal' and 'stage'                                                                                                                    | Yes      | production           |
| pyxisSecret              | The kubernetes secret to use to authenticate to Pyxis. It needs to contain two keys: key and cert                                                                                                                     | No       | -                    |
| batchLimit               | size of batch attributes to send to internal-request. As internal request arguments are need to be strings, size here represent maximal string length of `references` and `manifest_digests` sent to internal request | Yes      | 4096                 |
| caTrustConfigMapName     | The name of the ConfigMap to read CA bundle data from                                                                                                                                                                 | Yes      | trusted-ca           |
| caTrustConfigMapKey      | The name of the key in the ConfigMap that contains the CA bundle data                                                                                                                                                 | Yes      | ca-bundle.crt        |
