# RHTAP Service Push to External Registry Pipeline

* Tekton pipeline based on "push-to-external-registry".
* In addition, it creates a GH pull request in infra-deployments.
  * The parameter in data.infra-deployment-update-script within the ReleasePlanAdmission CR is used to optionally specify a script that can alter files before a PR is created.

## Parameters

| Name                     | Description                                                                             | Optional | Default value |
|--------------------------|-----------------------------------------------------------------------------------------|----------|---------------|
| release                  | The namespaced name (namespace/name) of the Release custom resource initiating this pipeline execution | No | -    |
| releasePlan              | The namespaced name (namespace/name) of the releasePlan                                 | No       | -             |
| releasePlanAdmission     | The namespaced name (namespace/name) of the releasePlanAdmission                        | No       | -             |
| releaseServiceConfig     | The namespaced name (namespace/name) of the releaseServiceConfig                        | No       | -             |
| snapshot                 | The namespaced name (namespace/name) of the snapshot                                    | No       | -             |
| enterpriseContractPolicy | JSON representation of the policy to be applied when validating the enterprise contract | No       | -             |
| enterpriseContractExtraRuleData | Extra rule data to be merged into the policy specified in params.enterpriseContractPolicy. Use syntax "key1=value1,key2=value2..." | Yes | pipeline_intention=release |
| enterpriseContractTimeout       | Timeout setting for `ec validate`                                                | Yes      | 40m0s         |
| postCleanUp              | Cleans up workspace after finishing executing the pipeline                              | Yes      | true          |
| verify_ec_task_bundle    | The location of the bundle containing the verify-enterprise-contract task               | No       | -             |
| taskGitUrl               | The url to the git repo where the release-service-catalog tasks to be used are stored   | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision          | The revision in the taskGitUrl repo to be used                                          | No       | -             |

## Changes in 4.0.0
* Drop the `enterpriseContractPublicKey` param. The verify task will take the value from the policy.

## Changes in 3.12.0
* Add `requireInternalServices` parameter to the 'verify-access-to-resources' task.

## Changes in 3.11.2
* Increase `enterpriseContractTimeout` parameter default value.

## Changes in 3.11.1
* Add `enterpriseContractTimeout` parameter.

## Changes in 3.11.0
* Updated the image passed to the `infra-deployments-pr` task

## Changes in 3.10.0 
* Removed `verify-access-to-resources` script and replaced it with a task.
  
## Changes in 3.9.0
* The `create-pyxis-image` task no longer receives the `dataPath` parameter

## Changes in 3.8.0
* The `push-snapshot` task now gets the `resultsDirPath` parameter from `collect-data` results

## Changes in 3.7.0
* Add the task `update-cr-status` at the end of the pipeline to save all pipeline results

## Changes in 3.6.0
* Updated the image passed to the infra-deployments-pr task to reflect release-service-utils migrating to
  the konflux-ci quay organization

## Changes in 3.5.0
* The apply-mapping task now gets the dataPath parameter instead of releasePlanAdmissionPath

## Changes in 3.4.0
* `enterpriseContractExtraRuleData` added as a pipeline parameter, which is
  then passed to EC. Allows for easier runtime changes to rule data.

## Changes in 3.3.0
* Add new task `push-rpm-manifests-to-pyxis` to run after `create-pyxis-image`

## Changes in 3.2.0
* update the taskGitUrl default value due to migration
  to konflux-ci GitHub org

## Changes in 3.1.1
* Added `when` clause to
  `push-snapshot`,
  `collect-pyxis-params` and
  `create-pyxis-image`
  to ensure they only execute when the `apply-mapping`
  task indicates that mapping was successful.

## Changes in 3.1.0
* Remove push-sbom-to-pyxis. It has been replaced by manifest-box.

## Changes in 3.0.1
* releaseServiceConfig was not passed to the collect-data task - now it is

## Changes in 3.0.0
* releaseServiceConfig added as a pipeline parameter that is passed to the collect-data task

## Changes in 2.0.0
* Parameters supplied by the Release Service operator now use camelCase format

## Changes in 1.5.0
* Modified the pipeline to dynamically source the `data.json`, `snapshot_spec.json` and
  `release_plan_admission.json` files from the results of the `collect-data` task.

## Changes in 1.4.1
* The cleanup-workspace task now receives a pipelineRunUid parameter to cleanup InternalRequests

## Changes in 1.4.0
* taskGitRevision no longer has a default. It will be provided by the operator and will always have the same value as
  the git revision in the PipelineRef definition of the PipelineRun if using a git resolver. See RHTAPREL-790 for details

## Changes in 1.3.1
* `send-slack-notification` task is only called if slack notification secret is set in data file
  * the taskrun would fail to start with an empty `secretName` parameter

## Changes in 1.3.0
* taskGitUrl parameter is added. It is used to provide the git repo for the release-service-catalog tasks
* taskGitRevision parameter is added. It is used to provide the revision to be used in the taskGitUrl repo

## Changes in 1.1.0
* Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead

## Changes in 1.0.1
* Switch back to using bundle resolvers for the verify-enterprise-contract task

## Changes in 1.0.0
* Added parameter for releasePlanAdmissionPath to apply-mapping as the file is in a subdirectory

## Changes 0.9.0
* Removed tag, addGitShaTag, addSourceShaTag, addTimestampTag parameters
  * These are now provided in the data json that is collected in the collect-data task
* slack-webhook-notification and update-infra-deployments task now accept dataJsonPath instead of
  extraDataJsonPath. This is due to a change in the ReleasePlanAdmission API

## Changes in 0.8.0
* Remove extraConfig parameters as the information is now passed in the RPA data field
* Remove the git clone task
* Fix apply-mapping parameters

## Changes in 0.7.0
* pyxisSecret and pyxisServerType parameters were removed
  * They are now pulled from the data.json created by merging the Release CR data fields
  * This includes adding a new task `collect-pyxis-params` to emit the values as results

## Changes in 0.6.0
* Remove releasestrategy parameter

## Changes in 0.5.0
* Introduce new initial task - verify-access-to-resources
  - protection to verify that service accounts have required permissions to access
    resources before we start a pipeline.
  - If verification does not pass, the pipeline fails

## Changes in 0.4
- update Tekton API to v1
    - includes bumping all tasks to versions that use Tekton API v1

## Changes in 0.3
- correct params for snapshot and extraData json file paths of update-infra-deployments task

## Changes in 0.2
- explicitly set IGNORE_REKOR value to "true" in the verify-enterprise-contract task
- use git resolvers for the verify-enterprise-contract task
    - the verify_ec_task_bundle parameter was placed with verify_ec_task_git_url,
      verify_ec_task_git_revision, and verify_ec_task_git_pathInRepo
- add new enterpriseContractPublicKey parameter

## Changes in 0.1
- use new version of collect-data task with subdirectory parameter
- use PipelineRun UID for subdirectory inside the workspace
    - this will avoid the issue of parallel PipelineRuns overriding each other's data
- also use new version of apply-mapping which overrides the original snapshot_spec file
    - and specify snapshotPath for this task to point to the subdir
