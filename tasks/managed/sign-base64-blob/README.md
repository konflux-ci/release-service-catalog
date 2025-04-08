# sign-base64-blob

Creates an InternalRequest to sign a base64 encoded blob

## Parameters

| Name                 | Description                                                                               | Optional | Default value         |
|----------------------|-------------------------------------------------------------------------------------------|----------|-----------------------|
| dataPath             | Path to the JSON string of the merged data to use in the data workspace                   | No       | -                     |
| referenceImage       | The image to be signed                                                                    | No       | -                     |
| manifestDigestImage  | Manifest Digest Image used to extract the SHA                                             | Yes      | ""                    |
| requester            | Name of the user that requested the signing, for auditing purposes                        | No       | -                     |
| requestTimeout       | InternalRequest timeout                                                                   | Yes      | 180                   |
| binariesPath         | The directory inside the workspace where the binaries are stored                          | Yes      | binaries              |
| pipelineRunUid       | The uid of the current pipelineRun. Used as a label value when creating internal requests | No       | -                     |

## Signing data parameters

 The signing configuration should be set as `data.sign` in the _releasePlanAdmission_. The data should be set in the _ReleasePlanAdmission_ as follows:

```
data:
    sign:
        pipelineImage: <image pullspec>
        configMapName: <configmap name>
```

## Changes in 2.4.2
* Use a temp file for `internal-request` result instead of a fixed file in the workspace to reduce risk
  of interference with other tasks

## Changes in 2.4.1
* Fix shellcheck/checkton linting issues in the task and tests

## Changes in 2.4.0
* No longer examine `.data.sign.request` to obtain the Signing pipeline name. Use the default - blob-signing-pipeline

## Changes in 2.3.0
* Updated the base image used in this task

## Changes in 2.2.0
* Updated the base image used in this task

## Changes in 2.1.0
* remove `dataPath` default value

## Changes in 2.0.0
* The internalrequest CR is created with a label specifying the pipelinerun uid with the new pipelineRunUid parameter
  - This change comes with a bump in the image used for the task

## Changes in 1.0.2
* Save the `.sig` file as a non-ASCII armored GPG binary instead of clear ASCII GPG signature

## Changes in 1.0.1
* Now the task decodes the payload from base64 before creating the `.sig` file
