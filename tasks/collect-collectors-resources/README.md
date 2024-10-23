# collect-collectors-resources

Tekton task to collect collectors related resources.

The purpose of this task is to collect all the resources related with the collectors feature and supply
them to other tasks in the pipeline by creating json files for each resource. This task is similar
to collect-data but it only collects a subset of the resources. Specifically those related to collectors.

A task result is returned for each resource with the relative path to the stored JSON for it in the workspace.

## Parameters

| Name                   | Description                                                      | Optional | Default value |
|------------------------|------------------------------------------------------------------|----------|---------------|
| previousRelease        | Namespaced name of the previous Release                          | No       | -             |
| release                | Namespaced name of the Release                                   | No       | -             |
| collectorsResourceType | The type of resource that contains the collectors                | No       | -             |
| collectorsResource     | The namespaced name of the resource that contains the collectors | No       | -             |
| subdirectory           | Subdirectory inside the workspace to be used                     | Yes      | ""            |

## Changes in 0.2.0
* Stop passing releasePlan and releasePlanAdmission and pass instead a reference to a resource