# E2E test Pipeline

Minimal Tekton Pipeline to be used by the E2E tests. The Pipeline is designed to include only tasks that could be
affected by RHTAP services or which results could affect the RHTAP workflow.

## Parameters

| Name                            | Description                                                                                            | Optional | Default value |
|---------------------------------|--------------------------------------------------------------------------------------------------------|----------|---------------|
| release                         | The namespaced name (namespace/name) of the Release custom resource initiating this pipeline execution | No       | -             |
| releasePlan                     | The namespaced name (namespace/name) of the releasePlan                                                | No       | -             |
| releasePlanAdmission            | The namespaced name (namespace/name) of the releasePlanAdmission                                       | No       | -             |
| releaseServiceConfig            | The namespaced name (namespace/name) of the releaseServiceConfig                                       | No       | -             |
| snapshot                        | The namespaced name (namespace/name) of the snapshot                                                   | No       | -             |
| enterpriseContractPolicy        | JSON representation of the policy to be applied when validating the enterprise contract                | No       | -             |
| enterpriseContractExtraRuleData | Extra rule data to be merged into the policy specified in params.enterpriseContractPolicy. Use syntax "key1=value1,key2=value2..." | Yes | pipeline_intention=release |
| enterpriseContractTimeout       | Timeout setting for `ec validate`                                                                      | Yes      | 40m0s         |
| postCleanUp                     | Cleans up workspace after finishing executing the pipeline                                             | Yes      | true          |
| verify_ec_task_bundle           | The location of the bundle containing the verify-enterprise-contract task                              | No       | -             |
| taskGitUrl                      | The url to the git repo where the release-service-catalog tasks to be used are stored                  | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision                 | The revision in the taskGitUrl repo to be used                                                         | No       | -             |

## Changes in 3.0.0
* Drop the `enterpriseContractPublicKey` param. The verify task will take the value from the policy.

## Changes in 2.2.2
* Increase `enterpriseContractTimeout` parameter default value.

## Changes in 2.2.1
* Add `enterpriseContractTimeout` parameter.

## Changes in 2.2.0
* `enterpriseContractExtraRuleData` added as a pipeline parameter, which is
  then passed to EC. Allows for easier runtime changes to rule data.

## Changes in 2.1.0
* update the taskGitUrl default value due to migration
  to konflux-ci GitHub org

## Changes in 2.0.0
* releaseServiceConfig added as a pipeline parameter that is passed to the collect-data task

## Changes in 1.0.0
* Parameters supplied by the Release Service operator now use camelCase format

## Changes in 0.5.0
* Modified the pipeline to dynamically source the `snapshot_spec.json`
  file from the results of the `collect-data` task.

## Changes in 0.4.1
* The cleanup-workspace task now receives a pipelineRunUid parameter to cleanup InternalRequests

## Changes in 0.4.0
* taskGitRevision no longer has a default. It will be provided by the operator and will always have the same value as
  the git revision in the PipelineRef definition of the PipelineRun if using a git resolver. See RHTAPREL-790 for details

## Changes in 0.3.0
* taskGitUrl parameter is added. It is used to provide the git repo for the release-service-catalog tasks
* taskGitRevision parameter is added. It is used to provide the revision to be used in the taskGitUrl repo

## Changes in 0.1.0
* Switch to using bundle resolvers for the verify-enterprise-contract task
