# sign-index-image

Creates an InternalRequest to sign an index image

## Parameters

| Name                 | Description                                                             | Optional | Default value          |
|----------------------|-------------------------------------------------------------------------|----------|------------------------|
| dataPath             | Path to the JSON string of the merged data to use in the data workspace | Yes      | data.json              |
| request              | Signing pipeline name to handle this request                            | Yes      | hacbs-signing-pipeline |
| referenceImage       | The image to be signed                                                  | No       |                        |
| manifestDigestImage  | Manifest Digest Image used to extract the SHA                           | Yes      | ""                     |
| requester            | Name of the user that requested the signing, for auditing purposes      | No       |                        |
| requestTimeout       | InternalRequest timeout                                                 | Yes      | 180                    |

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

## Changes in 1.2.1
- add image pullspec rewriting

## Changes in 1.2.0
- Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead

## Changes in 1.1.0
- change the task to use the `internal-request` script

## Changes since 0.1
- update Tekton API to v1
