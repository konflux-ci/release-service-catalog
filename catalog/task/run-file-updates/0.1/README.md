# run-file-udpates

Tekton task to create InternalRequests for each repository that needs to be updated. This information is extracted from
the field `spec.extraData.fileUpdates` in the ReleasePlanAdmission resource.

## Parameters

| Name            | Description                                                   | Optional | Default value                 |
|-----------------|---------------------------------------------------------------|----------|-------------------------------|
| jsonKey         | JSON key where the information is defined                     | Yes      | .spec.extraData.fileUpdates[] |
| fileUpdatesPath | Path to the JSON file containing the key                      | No       |                               |
| request         | Type of request to be created                                 | Yes      | file-updates                  |
| synchronously   | Whether the task should wait for InternalRequests to complete | Yes      | true                          |

