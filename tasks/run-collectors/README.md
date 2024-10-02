# run-collectors

Tekton task to run the collectors defined in the ReleasePlan and ReleasePlanAdmission. The results are saved in the resultsDir,
one file per collector.

## Parameters

| Name                     | Description                                                               | Optional | Default value |
|--------------------------|---------------------------------------------------------------------------|----------|---------------|
| releasePlanAdmissionPath | Path to the JSON string of the ReleasePlanAdmission in the data workspace | No       | -             |
| releasePlanPath          | Path to the JSON string of the ReleasePlan in the data workspace          | No       | -             |
| resultsDir               | The relative path in the workspace to save the collector results to       | No       | -             |
