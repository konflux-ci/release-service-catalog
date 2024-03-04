# create-advisory-internal-request

Tekton task to create an advisory via an InternalRequest. The advisory data is pulled from the data JSON. The origin workspace from
the ReleasePlanAdmission and Application from the Snapshot are also used. The advisory is created in a GitLab repository.

## Parameters

| Name                     | Description                                                                               | Optional | Default value               |
|--------------------------|-------------------------------------------------------------------------------------------|----------|-----------------------------|
| jsonKey                  | The json key containing the advisory data                                                 | Yes      | .releaseNotes               |
| releasePlanAdmissionPath | Path to the JSON file of the ReleasePlanAdmission in the data workspace                   | Yes      | release_plan_admission.json |
| releaseServiceConfigPath | Path to the JSON file of the ReleaseServiceConfig in the data workspace                   | No       |                             |
| snapshotPath             | Path to the JSON file of the Snapshot spec in the data workspace                          | Yes      | snapshot_spec.json          |
| dataPath                 | Path to data JSON in the data workspace                                                   | Yes      | data.json                   |
| request                  | Type of request to be created                                                             | Yes      | create-advisory             |
| synchronously            | Whether the task should wait for InternalRequests to complete                             | Yes      | true                        |
| pipelineRunUid           | The uid of the current pipelineRun. Used as a label value when creating internal requests | No       |                             |

## Changes in 2.1.0
- The advisory_url is reported as task result
  - If the advisory was not created, the result will instead be the empty string

## Changes in 2.0.0
- The path to the ReleaseServiceConfig in the data workspace is now passed as a parameter
  - The advisory repo will be fetched from the ReleaseServiceConfig json

## Changes in 1.2.0
- The sign.configMapName is passed to the internal request so the signing key can be added to the advisory yaml

## Changes in 1.1.0
- The default value of jsonKey changed from .advisory to .releaseNotes

## Changes in 1.0.0
- The internalrequest CR is created with a label specifying the pipelinerun uid with the new pipelineRunUid parameter
  - This change comes with a bump in the image used for the task

## Changes since 0.1.0
- Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead
