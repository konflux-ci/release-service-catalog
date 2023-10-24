# create-advisory-internal-request

Tekton task to create an advisory via an InternalRequest. The advisory data is pulled from the data JSON. The origin workspace from
the ReleasePlanAdmission and Application from the Snapshot are also used. The advisory is created in a GitLab repository.

## Parameters

| Name                     | Description                                                             | Optional | Default value               |
|--------------------------|-------------------------------------------------------------------------|----------|-----------------------------|
| jsonKey                  | The json key containing the advisory data                               | Yes      | .advisory                   |
| releasePlanAdmissionPath | Path to the JSON file of the ReleasePlanAdmission in the data workspace | Yes      | release_plan_admission.json |
| snapshotPath             | Path to the JSON file of the Snapshot spec in the data workspace        | Yes      | snapshot_spec.json          |
| dataPath                 | Path to data JSON in the data workspace                                 | Yes      | data.json                   |
| request                  | Type of request to be created                                           | Yes      | create-advisory             |
| synchronously            | Whether the task should wait for InternalRequests to complete           | Yes      | true                        |
