# sign-base64-blob

Creates an InternalRequest to sign a base64 encoded blob

## Parameters

| Name                 | Description                                                             | Optional | Default value          |
|----------------------|-------------------------------------------------------------------------|----------|------------------------|
| dataPath             | Path to the JSON string of the merged data to use in the data workspace | Yes      | data.json              |
| request              | Signing pipeline name to handle this request                            | Yes      | hacbs-signing-pipeline |
| referenceImage       | The image to be signed                                                  | No       |                        |
| manifestDigestImage  | Manifest Digest Image used to extract the SHA                           | Yes      | ""                     |
| requester            | Name of the user that requested the signing, for auditing purposes      | No       |                        |
| requestTimeout       | InternalRequest timeout                                                 | Yes      | 180                    |
| binariesPath         | The directory inside the workspace where the binaries are stored        | Yes      | binaries               |

## Signing data parameters

 The signing configuration should be set as `data.sign` in the _releasePlanAdmission_. The data should be set in the _ReleasePlanAdmission_ as follows:

```
data:
    sign:
        request: <signing pipeline name>
        pipelineImage: <image pullspec>
        configMapName: <configmap name>
```

## Changes in 1.0.1
- Now the task decodes the payload from base64 before creating the `.sig` file
