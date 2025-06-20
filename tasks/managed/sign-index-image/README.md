# sign-index-image

Creates an InternalRequest to sign an index image

## Parameters

| Name                     | Description                                                                                                                | Optional | Default value           |
|--------------------------|----------------------------------------------------------------------------------------------------------------------------| -------- |-------------------------|
| dataPath                 | Path to the JSON string of the merged data to use in the data workspace                                                    | No       | -                       |
| releasePlanAdmissionPath | Path to the JSON string of the releasePlanAdmission in the data workspace                                                  | No       | -                       |
| referenceImage           | The image to be signed                                                                                                     | No       | -                       |
| manifestListDigests      | The manifest digests for each arch in manifest list                                                                        | No       | -                       |
| requester                | Name of the user that requested the signing, for auditing purposes                                                         | No       | -                       |
| requestTimeout           | InternalRequest timeout                                                                                                    | Yes      | 1800                    |
| pipelineRunUid           | The uid of the current pipelineRun. Used as a label value when creating internal requests                                  | No       | -                       |
| fbcResultsPath           | Path to the JSON file in the data workspace containing fbc results                                                         | No       | -                       |
| concurrentLimit          | The maximum number of concurrent signing requests                                                                          | Yes      | 16                      |
| ociStorage               | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                   |
| ociArtifactExpiresAfter  | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                      |
| trustedArtifactsDebug    | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                      |
| orasOptions              | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                      | 
| sourceDataArtifact       | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                      |
| dataDir                  | The location where data will be stored                                                                                     | Yes      | $(workspaces.data.path) |
| taskGitUrl               | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | ""                      |
| taskGitRevision          | The revision in the taskGitUrl repo to be used                                                                             | No       | ""                      |

## Changes in 5.0.0
* This task now supports Trusted artifacts

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

## Changes in 4.4.0
* Added compute resource limits

## Changes in 4.3.0
* Add support for multicomponent releases
  * The new mandatory task parameter `fbcResultsPath` points to a file with images and manifest digests to sign
  * Signing is processed in parallel - up to `concurrentLimit` of signing requests at a time

## Changes in 4.2.1
* The default serviceAccount is changed from `appstudio-pipeline` to `release-service-account`

## Changes in 4.2.0
* The pipeline is called via git resolver now instead of cluster resolver
  * This was done by changing from `-r` to `--pipeline` in the `internal-request`/`internal-pipelinerun` call
  * The base image was updated to include this new functionality

## Changes in 4.1.1
* Increase `requestTimeout` value to 30 minutes
  * The internal-request/internal-pipeline is set to a timeout of 30 minutes, but the internal-request/internal-pipeline script
    was set to timeout after 3 minutes, which didn't make much sense.

## Changes in 4.1.0
* Updated task to support the `internal-pipelinerun` requestType
* New mandatory parameter `releasePlanAdmissionPath`
  * It is needed in order to obtain the serviceAccount so it can be used in the PipelineRun definition for the
  internal-pipelinerun

## Changes in 4.0.0
* Added new task parameters `taskGitRevision` and `taskGitUrl`
  * These are passed to the InternalRequest as they are required parameters of the `simple-signing-pipeline`
* The default for `sign.request` is now `simple-signing-pipeline` instead of being `hacbs-signing-pipeline`

## Changes in 3.4.0
* Removed the `request` parameter and references of `fbc.request` from the task and set the default
  internal request pipeline to `hacbs-signing-pipeline`

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
