# run-collectors

Tekton task to run the collectors defined in a resource passed as parameter. The results are saved in the resultsDir,
one file per collector.

## Parameters

| Name                         | Description                                                                             | Optional | Default value |
|------------------------------|-----------------------------------------------------------------------------------------|----------|---------------|
| collectorsPath               | Path to the JSON string of the resource containing the collectors in the data workspace | No       | -             |
| collectorsResourceType       | The type of resource that contains the collectors                                       | No       | -             |
| resultsDir                   | The relative path in the workspace to save the collector results to                     | No       | -             |
| collectorsRepository         | Git repository where the collectors will be defined                                     | No       | -             |
| collectorsRepositoryRevision | Git repository revision                                                                 | Yes      | main          |

## Changes in 0.3.0
* Add new parameters to define the collectors repository and revision
* Force a cd into /tmp to avoid errors while cloning
* Address the change in the collectors spec which allows to specify a serviceAccountName while grouping
  every collector under a `items` field.

## Changes in 0.2.0
* Pass reference to the collectors path and to the resource type
