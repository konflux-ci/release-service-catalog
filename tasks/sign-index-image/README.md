# sign-index-image

Creates an InternalRequest to sign an index image

## Parameters

| Name                 | Description                                                                               | Optional | Default value          |
|----------------------|-------------------------------------------------------------------------------------------|----------|------------------------|
| dataPath             | Path to the JSON string of the merged data to use in the data workspace                   | No       | -                      |
| request              | Signing pipeline name to handle this request                                              | Yes      | hacbs-signing-pipeline |
| referenceImage       | The image to be signed                                                                    | No       | -                      |
| manifestListDigests  | The manifest digests for each arch in manifest list                                       | No       | -                      |
| requester            | Name of the user that requested the signing, for auditing purposes                        | No       | -                      |
| requestTimeout       | InternalRequest timeout                                                                   | Yes      | 180                    |
| pipelineRunUid       | The uid of the current pipelineRun. Used as a label value when creating internal requests | No       | -                      |

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

## Changes in 3.3.0
* Updated the base image used in this task

## Changes in 3.2.0
* Updated the base image used in this task

## Changes in 3.1.0
* Remove `dataPath` default value

## Changes in 3.0.1
* Update task image and make changes to accomodate for new `translate-delivery-repo` funtionality

## Changes in 3.0.0
* This task now requires a list of digests to use in the signing request via the parameter `manifestListDigests`
* The `manifestDigestImage` parameter has been removed.

## Changes in 2.1.0
* Use the translate-delivery-repo util for translating the reference_image variable
  * This change comes with a bump in the image used for the task

## Changes in 2.0.0
* The internalrequest CR is created with a label specifying the pipelinerun uid with the new pipelineRunUid parameter
  * This change comes with a bump in the image used for the task

## Changes in 1.2.1
* add image pullspec rewriting

## Changes in 1.2.0
* Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead

## Changes in 1.1.0
* change the task to use the `internal-request` script

## Changes in 0.1
* update Tekton API to v1
