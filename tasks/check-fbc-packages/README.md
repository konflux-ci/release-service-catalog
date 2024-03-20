# check-fbc-packages

Task to check that the packages being shipped in an fbc contribution are in the allow list provided in the dataPath.

## Parameters

| Name           | Description                                                               | Optional | Default value        |
|----------------|---------------------------------------------------------------------------|----------|----------------------|
| snapshotPath   | Path to the JSON string of the mapped Snapshot spec in the data workspace | Yes      | snapshot_spec.json   |
| dataPath       | Path to the JSON string of the merged data to use in the data workspace   | Yes      | data.json            |
