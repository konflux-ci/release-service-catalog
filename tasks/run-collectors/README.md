# run-collectors

Tekton task to run the collectors defined in the ReleasePlan and ReleasePlanAdmission. The results are saved in the resultsDir,
one file per collector.

## Parameters

| Name                   | Description                                                                             | Optional | Default value |
|------------------------|-----------------------------------------------------------------------------------------|----------|---------------|
| collectorsPath         | Path to the JSON string of the resource containing the collectors in the data workspace | No       | -             |
| collectorsResourceType | The type of resource that contains the collectors                                       | No       | -             |
| resultsDir             | The relative path in the workspace to save the collector results to                     | No       | -             |

## Changes in 0.2.0
* Pass reference to the collectors path and to the resource type