# push-artifacts-to-cdn pipeline

Tekton Pipeline to push artifacts to either CDN and/or CGW with signing.
It uses InternalRequests so that it can be run on both public and private clusters.

## Parameters

| Name                            | Description                                                                                                                         | Optional | Default value                                             |
|---------------------------------|-------------------------------------------------------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| release                         | The namespaced name (namespace/name) of the Release custom resource initiating this pipeline execution                              | No       | -                                                         |
| releasePlan                     | The namespaced name (namespace/name) of the releasePlan                                                                             | No       | -                                                         |
| releasePlanAdmission            | The namespaced name (namespace/name) of the releasePlanAdmission                                                                    | No       | -                                                         |
| releaseServiceConfig            | The namespaced name (namespace/name) of the releaseServiceConfig                                                                    | No       | -                                                         |
| snapshot                        | The namespaced name (namespace/name) of the snapshot                                                                                | No       | -                                                         |
| enterpriseContractPolicy        | JSON representation of the policy to be applied when validating the enterprise contract                                             | No       | -                                                         |
| enterpriseContractExtraRuleData | Extra rule data to be merged into the policy specified in params.enterpriseContractPolicy. Use syntax "key1=value1,key2=value2..."  | Yes      | pipeline_intention=release                                |
| enterpriseContractTimeout       | Timeout setting for `ec validate`                                                                                                   | Yes      | 10m0s                                                     |
| postCleanUp                     | Cleans up workspace after finishing executing the pipeline                                                                          | Yes      | true                                                      |
| verify_ec_task_bundle           | The location of the bundle containing the verify-enterprise-contract task                                                           | No       | -                                                         |
| verify_ec_task_git_revision     | The git revision to be used when consuming the verify-conforma task                                                                 | No       | -                                                         |
| taskGitUrl                      | The url to the git repo where the release-service-catalog tasks to be used are stored                                               | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision                 | The revision in the taskGitUrl repo to be used                                                                                      | No       | -                                                         |

## Changes in 0.2.1
* Required parameter `releasePath` is now passed to the `push-artifacts-to-cdn` task

## Changes in 0.2.0
* Update all tasks that now support trusted artifacts to specify the taskGit* parameters for the step action resolvers
* Align workspace name with changes in the apply-mapping task

## Changes in 0.1.0
* Add new parameter `verify_ec_task_git_revision` needed for consuming the verify-conforma task
  via git resolver
