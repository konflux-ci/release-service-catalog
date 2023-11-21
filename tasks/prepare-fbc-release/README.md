# prepare-fbc-release

A tekton task to prepare FBC Release by collecting a valid
OCP version for each component from given
containerImage(fbcFragment) in the snapshot, and update
the fromIndex, targetIndex and binaryImage with collected
OCP version and store updated values to snapshot respective
to each component, so other task can use them.

## Parameters

| Name         | Description                                                             | Optional | Default value      |
|--------------|-------------------------------------------------------------------------|----------|--------------------|
| snapshotPath | Path to the JSON string of the Snapshot spec in the data workspace      | Yes      | snapshot_spec.json |
| dataPath     | Path to the JSON string of the merged data to use in the data workspace | Yes      | data.json          |