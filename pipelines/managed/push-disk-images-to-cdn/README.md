# push-disk-images-to-cdn pipeline

Tekton Pipeline to push disk images to a cdn using pulp

## Parameters

| Name                            | Description                                                                                                                         | Optional | Default value                                              |
|---------------------------------|-------------------------------------------------------------------------------------------------------------------------------------|----------|------------------------------------------------------------|
| release                         | The namespaced name (namespace/name) of the Release custom resource initiating this pipeline execution                              | No       | -                                                          |
| releasePlan                     | The namespaced name (namespace/name) of the releasePlan                                                                             | No       | -                                                          |
| releasePlanAdmission            | The namespaced name (namespace/name) of the releasePlanAdmission                                                                    | No       | -                                                          |
| releaseServiceConfig            | The namespaced name (namespace/name) of the releaseServiceConfig                                                                    | No       | -                                                          |
| snapshot                        | The namespaced name (namespace/name) of the snapshot                                                                                | No       | -                                                          |
| enterpriseContractPolicy        | JSON representation of the policy to be applied when validating the enterprise contract                                             | No       | -                                                          |
| enterpriseContractExtraRuleData | Extra rule data to be merged into the policy specified in params.enterpriseContractPolicy. Use syntax "key1=value1,key2=value2..."  | Yes      | pipeline_intention=release                                 |
| enterpriseContractTimeout       | Timeout setting for `ec validate`                                                                                                   | Yes      | 10m0s                                                      |
| postCleanUp                     | Cleans up workspace after finishing executing the pipeline                                                                          | Yes      | true                                                       |
| verify_ec_task_bundle           | The location of the bundle containing the verify-enterprise-contract task                                                           | No       | -                                                          |
| verify_ec_task_git_revision     | The git revision to be used when consuming the verify-conforma task                                                                 | No       | -                                                          |
| taskGitUrl                      | The url to the git repo where the release-service-catalog tasks to be used are stored                                               | Yes      | https://github.com/konflux-ci/release-service-catalog.git  |   
| taskGitRevision                 | The revision in the taskGitUrl repo to be used                                                                                      | No       | -                                                          |

## Changes in 1.7.1
* Add retries in the pipeline

## Changes in 1.7.0
* Update all tasks that now support trusted artifacts to specify the taskGit* parameters for the step action resolvers
* Align workspace name with changes in the apply-mapping task

## Changes in 1.6.0
* Add new parameter `verify_ec_task_git_revision` needed for consuming the verify-conforma task
  via git resolver

## Changes in 1.5.0
* Update the pipeline to add taskGiturl and taskGitRevison parameters to
  push-disk-images task.

## Changes in 1.4.0
* Update all task pathInRepo values as they are now in `tasks/managed`

## Changes in 1.3.0
* Add new parameter `schema` to the `check-data-keys` task.

## Changes in 1.2.0
* The `push-disk-images` task now gets the `resultsDir` parameter from `collect-data` results
* Add the task `update-cr-status` at the end of the pipeline to save all pipeline results

## Changes in 1.1.0
* Add new reduce-snapshot task

## Changes in 1.0.0
* Drop the `enterpriseContractPublicKey` param. The verify task will take the value from the policy.

## Changes in 0.2.0
* Add `requireInternalServices` parameter to the 'verify-access-to-resources' task.

## Changes in 0.1.1
* Override timeout of push-disk-images task. Default is now 2h.
