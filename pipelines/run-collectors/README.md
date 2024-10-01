# run-collectors pipeline

Tekton pipeline to execute the collectors defined in the releasePlan and releasePlanAdmission. The pipeline will
save the required resources to the workspace, execute the collectors, then update the Release.Status with the results.

## Parameters

| Name                 | Description                                                                                                       | Optional | Default value                                             |
|----------------------|-------------------------------------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| release              | The namespaced name (namespace/name) of the Release custom resource initiating this pipeline execution            | No       | -                                                         |
| previousRelease      | The namespaced name (namespace/name) of the previous successful Release prior to the one passed as params.release | No       | -                                                         |
| releasePlan          | The namespaced name (namespace/name) of the releasePlan                                                           | No       | -                                                         |
| releasePlanAdmission | The namespaced name (namespace/name) of the releasePlanAdmission                                                  | No       | -                                                         |
| taskGitUrl           | The url to the git repo where the release-service-catalog tasks to be used are stored                             | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision      | The revision in the taskGitUrl repo to be used                                                                    | No       | -                                                         |
