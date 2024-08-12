# FBC Release Pipeline

Tekton release pipeline to interact with FBC Pipeline

## Parameters

| Name                            | Description                                                                                              | Optional  | Default value                                                   |
|---------------------------------|----------------------------------------------------------------------------------------------------------|-----------|-----------------------------------------------------------------|
| release                         | The namespaced name (namespace/name) of the Release custom resource initiating this pipeline execution   | No        | -                                                               |
| releasePlan                     | The namespaced name (namespace/name) of the releasePlan                                                  | No        | -                                                               |
| releasePlanAdmission            | The namespaced name (namespace/name) of the releasePlanAdmission                                         | No        | -                                                               |
| releaseServiceConfig            | The namespaced name (namespace/name) of the releaseServiceConfig                                         | No        | -                                                               |
| snapshot                        | The namespaced name (namespace/name) of the snapshot                                                     | No        | -                                                               |
| enterpriseContractPolicy        | JSON representation of the EnterpriseContractPolicy                                                      | No        | -                                                               |
| enterpriseContractExtraRuleData | Extra rule data to be merged into the policy specified in params.enterpriseContractPolicy. Use syntax "key1=value1,key2=value2..."                                              | Yes       | pipeline_intention=release                            |
| enterpriseContractTimeout       | Timeout setting for `ec validate`                                                                        | Yes       | 40m0s                                                           |
| verify_ec_task_bundle           | The location of the bundle containing the verify-enterprise-contract task                                | No        | -                                                               |
| postCleanUp                     | Cleans up workspace after finishing executing the pipeline                                               | Yes       | true                                                            |
| taskGitUrl                      | The url to the git repo where the release-service-catalog tasks to be used are stored                    | Yes       | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision                 | The revision in the taskGitUrl repo to be used                                                           | No        | -                                                               |

## Changes in 4.0.0
* Drop the `enterpriseContractPublicKey` param. The verify task will take the value from the policy.

## Changes in 3.7.0
* Add `requireInternalServices` parameter to the 'verify-access-to-resources' task.

## Changes in 3.6.2
* Increase `enterpriseContractTimeout` parameter default value.

## Changes in 3.6.1
* Add `enterpriseContractTimeout` parameter.

## Changes in 3.6.0
* Removed `verify-access-to-resources` script and replaced it with a task.

## Changes in 3.5.0
* add the task `update-cr-status` at the end of the pipeline to save all pipeline results

## Changes in 3.4.0
* The `add-fbc-contribution-to-index-image` and `extract-index-image` tasks now gets the `resultsDir` parameter from `collect-data` results

## Changes in 3.3.0
* `enterpriseContractExtraRuleData` added as a pipeline parameter, which is
  then passed to EC. Allows for easier runtime changes to rule data.

## Changes in 3.2.0
* update the taskGitUrl default value due to migration
  to konflux-ci GitHub org

## Changes in 3.1.0
* add a new `check-fbc-packages` task to support operator package name uniqueness constraints

## Changes in 3.0.0
* releaseServiceConfig added as a pipeline parameter that is passed to the collect-data task

## Changes in 2.0.0
* Parameters supplied by the Release Service operator now use camelCase format

## Changes in 1.10.0
* the task `sign-index-image` now requires the `manifestListDigests` parameter set with the `indexImageDigests`
  result from the task `add-fbc-contribution-to-index-image`.
* the `manifestDigestImage` parameter was removed from `sign-index-image` task

## Changes in 1.9.0
* modified the pipeline to dynamically source the `data.json` and `snapshot_spec.json`
  files from the results of the `collect-data` task.

## Changes in 1.8.0
* the task `add-fbc-contribution` now requires the `targetIndex` parameter set with the `updated-targetIndex`
  result from the task `update-ocp-tag`

## Changes in 1.7.1
* tasks that interact with InternalRequests now have a pipelineRunUid parameter added to them to help with cleanup

## Changes in 1.7.0
* taskGitRevision no longer has a default. It will be provided by the operator and will always have the same value as
  the git revision in the PipelineRef definition of the PipelineRun if using a git resolver. See RHTAPREL-790 for details

## Changes in 1.6.0
* add new parameter `buildTimestamp` when calling the `publish-index-image` task
  * this new parameter is used for adding a timestamped tag to the index image

## Changes in 1.5.0
* modify the task `publish-index-image` to use a dedicated task instead of using the `create-internal-request` task

## Changes in 1.4.0
* rename task results accordingly to the changes contained in the task
  `add-fbc-contribution`

## Changes in 1.3.0
* taskGitUrl parameter is added. It is used to provide the git repo for the release-service-catalog tasks
* taskGitRevision parameter is added. It is used to provide the revision to be used in the taskGitUrl repo

## Changes in 1.1.0
* update task definition `sign-index-image`

## Changes in 1.0.0
* Switch back to using bundle resolvers for the verify-enterprise-contract task

## Changes in 0.26.0
* change pipeline and tasks definitions to support usage of data JSON file
* remove parameters `fromIndex`, `targetIndex`, `binaryImage`, `buildTags`, `addArches`
  `signingConfigMapName`, `iibServiceConfigSecret`, `iibOverwriteFromIndexCredential`,
  `fbcPublishingCredentials`, `requestUpdateTimeout` and `buildTimeoutSeconds`

## Changes in 0.25.0
* change default value of signingConfigMapName

## Changelog in 0.24.0
* Remove releasestrategy parameter

## Changes in 0.23.0
* adds new tasks `validate-single-component` to validate that the
  snapshot only contains a single component. The pipeline should fail otherwise.

## Changes in 0.22.0
* Introduce new initial task - verify-access-to-resources
  * protection to verify that service accounts have required permissions to access
    resources before we start a pipeline.
  * If verification does not pass, the pipeline fails

## Changes in 0.21
* update Tekton API to v1
    * includes bumping all tasks to versions that use Tekton API v1

## Changes in 0.20
* iibIndexImage and iibIndexImageResolved pipelineResults were added. These come from the
  task results in extract-index-image

## Changes in 0.19
* adds new tasks `get-ocp-version` and `update-ocp-tag` to update version tag
  for `targetIndex`, `fromIndex` and `binaryImage` with valid OCP Version
* add new enterpriseContractPublicKey parameter

## Changes in 0.18
 explicitly set IGNORE_REKOR value to "true" in the verify-enterprise-contract task
* use git resolvers for the verify-enterprise-contract task
    * the verify_ec_task_bundle parameter was placed with verify_ec_task_git_url,
      verify_ec_task_git_revision, and verify_ec_task_git_pathInRepo

## Changes in 0.17
* use new version of collect-data task with subdirectory parameter
* use PipelineRun UID for subdirectory inside the workspace
    * this will avoid the issue of parallel PipelineRuns overriding each other's data
* use new version of create-internal-requests task with subdirectory parameter

## Changes in 0.16
* git resolvers are used in place of release bundle resolvers

## Changes in 0.15
* the collect-data task was added
    * this includes adding the required parameters releaseplan, releaseplanadmission, and
      releasestrategy as pipeline parameters
* the snapshot parameter is now a namespaced name instead of a JSON string
    * task versions were updated in accordance with this change

## Changes in 0.14
* adds parameters `iibServiceConfigSecret` and `iibOverwriteFromIndexCredential`
  to enable the build of pre-GA and prod FBC components in the same namespace

## Changes in 0.13
* adds back the parameter `fbcPublishingCredentials` as different secrets
  might be set for the same namespace

## Changes in 0.12
* the release parameter was added and the requester parameter was removed
    * the value to use for signing is now pulled from the release resource status

## Changes in 0.11
* updates tasks that use `create-internal-request` task to 0.6 as now they need to
  rely on its `genericResult` result
* the task `publish-index-image` now uses `create-internal-request` so the publishing
  is done by the cluster running the internal-services-controller
* only executes `publish-index-image` and `sign-index-image` when genericResult result of
  the tasks using `create-internal-request` has `fbc_opt_in=true` value set
* removes `fbcPublishingCredentials` parameter
* removes `overwriteFromIndex` parameter

## Changes in 0.10
* the verify_ec_task_bundle parameter was added
    * with this addition, the verify-enterprise-contract task version is no longer static

## Changes in 0.9
* changes on the following tasks due to `create-internal-request` changes:
    * `add-fbc-contribution-to-index-image` now accepts dynamic parameters
    * `sign-index-image` now accepts dynamic parameters
* changes on `publish-index-image` task to read data from its `inputDataFile` parameter
* adds cleanup task

## Changes in 0.8
* fixes in the README.md file
* adds param `fbcPublishingCredentials`
* removes param `overwriteFromIndex`
* adds new task `publish-index-image`

## Changes in 0.7
* The syntax for `taskRef.bundle` and `pipelineRef.bundle` is deprecated,
bundles resolver is used with new format.

## Changes in 0.6
* adds sign-index-image task
* refactor task and change its reference name from `create-internal-request`
  to `add-fbc-contribution-to-index-image`
* adds `requester` and `signingConfigMapName` parameters
* removes `resolvedIndexImage` result

## Changes in 0.5
* updates `create-internal-request` task version to 0.3

## Changes in 0.4
* updates `create-internal-request` task version to 0.2
* adds `resolvedIndexImage` result

## Changes in 0.3
* removes param `fbcFragment`
* adds param `buildTimeoutSeconds`

## Changes in 0.2
* renames the pipeline to `fbc-release`
* forces the pipeline to run after `verify-enterprise-contract`

## Changes in 0.1
* adds param `requestUpdateTimeout`
* adds task result values to the pipeline results
  * `requestMessage` gets `$(tasks.create-internal-request.results.requestMessage)`
  * `requestReason` gets `$(tasks.create-internal-request.results.requestReason)`
  * `requestResults` gets `$(tasks.create-internal-request.results.requestResults)`
* changes `verify-enterprise-contract` task version
