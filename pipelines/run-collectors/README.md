# run-collectors pipeline

Tekton pipeline to execute the collectors defined in the releasePlan and releasePlanAdmission. The pipeline will
save the required resources to the workspace, execute the collectors, then update the Release.Status with the results.

## Parameters

| Name                   | Description                                                                                                       | Optional | Default value                                             |
|------------------------|-------------------------------------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| release                | The namespaced name (namespace/name) of the Release custom resource initiating this pipeline execution            | No       | -                                                         |
| previousRelease        | The namespaced name (namespace/name) of the previous successful Release prior to the one passed as params.release | No       | -                                                         |
| collectorsResourceType | The type of resource that contains the collectors                                                                 | No       | -                                                         |
| collectorsResource     | The namespaced name of the resource that contains the collectors                                                  | No       | -                                                         |
| taskGitUrl             | The url to the git repo where the release-service-catalog tasks to be used are stored                             | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision        | The revision in the taskGitUrl repo to be used                                                                    | No       | -                                                         |

## Changes in 0.2.0
* Stop passing releasePlan and releasePlanAdmission and pass instead a reference to a resource