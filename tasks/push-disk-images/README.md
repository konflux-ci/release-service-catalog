# push-disk-images

Tekton task to push disk images via an InternalRequest. The environment to use is pulled from the `cdn.env` key in the data file.

## Parameters

| Name                     | Description                                                                               | Optional | Default value |
|--------------------------|-------------------------------------------------------------------------------------------|----------|---------------|
| snapshotPath             | Path to the JSON file of the Snapshot spec in the data workspace                          | No       | -             |
| dataPath                 | Path to data JSON in the data workspace                                                   | No       | -             |
| pipelineRunUid           | The uid of the current pipelineRun. Used as a label value when creating internal requests | No       | -             |
