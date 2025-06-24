# push-rpm-to-koji

Tekton task to push konflux build rpms to koji instance.

## Parameters

| Name                 | Description                                                                    | Optional | Default value |
|----------------------|--------------------------------------------------------------------------------|----------|---------------|
| snapshotPath         | Path to the JSON file of the mapped Snapshot spec in the data workspace        | No       | -             |
| dataPath             | Path to the JSON file of the merged data to use in the data workspace          | No       | -             |
| pushSecret           | The secret that for the login of koji instance                                 | No       | -             |
| subdirectory         | Path to results directory in the data workspace                                | No       | -             |
| pipelineImage        | The image url with koji (1.34 or higher), jq and kinit installed for running the push-rpm-to-koji task | No       | -             |
