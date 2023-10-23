# rh-sign-image

Task to create internalrequests to sign snapshot components

## Parameters

| Name           | Description                                                               | Optional | Default value        |
|----------------|---------------------------------------------------------------------------|----------|----------------------|
| snapshotPath   | Path to the JSON string of the mapped Snapshot spec in the data workspace | Yes      | snapshot_spec.json |
| dataPath       | Path to the JSON string of the merged data to use in the data workspace   | Yes      | data.json            |
| requester      | Name of the user that requested the signing, for auditing purpose         | No       |                      |
| requestTimeout | InternalRequest timeout                                                   | Yes      | 180                  |
