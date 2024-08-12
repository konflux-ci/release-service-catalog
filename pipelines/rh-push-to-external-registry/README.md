# Red Hat Push to External Registry Pipeline

Tekton pipeline to release Red Hat Snapshots to an external registry. This pipeline includes pyxis interactions.

## Parameters

| Name                    | Description                                                                          | Optional | Default value |
|-------------------------|--------------------------------------------------------------------------------------|----------|---------------|
| release                 | The namespaced name (namespace/name) of the Release custom resource initiating this pipeline execution | No | - |
| releasePlan             | The namespaced name (namespace/name) of the releasePlan                              | No       | -             |
| releasePlanAdmission    | The namespaced name (namespace/name) of the releasePlanAdmission                     | No       | -             |
| releaseServiceConfig    | The namespaced name (namespace/name) of the releaseServiceConfig                     | No       | -             |
| snapshot                | The namespaced name (namespace/name) of the snapshot                                 | No       | -             |
| enterpriseContractPolicy        | JSON representation of the policy to be applied when validating the enterprise contract | No | -        |
| enterpriseContractExtraRuleData | Extra rule data to be merged into the policy specified in params.enterpriseContractPolicy. Use syntax "key1=value1,key2=value2..." | Yes | pipeline_intention=release |
| enterpriseContractTimeout       | Timeout setting for `ec validate`                                            | Yes       | 40m0s        |
| postCleanUp             | Cleans up workspace after finishing executing the pipeline                           | Yes       | true         |
| verify_ec_task_bundle   | The location of the bundle containing the verify-enterprise-contract task            | No        | -            |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks to be used are stored | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                       | No        | -            |

## Changes in 5.0.0
* Drop the `enterpriseContractPublicKey` param. The verify task will take the value from the policy.

## Changes in 4.10.0
* Add `requireInternalServices` parameter to the 'verify-access-to-resources' task.

## Changes in 4.9.2
* Increase `enterpriseContractTimeout` parameter default value.

## Changes in 4.9.1
* Add `enterpriseContractTimeout` parameter.

## Changes in 4.9.0
* Removed `verify-access-to-resources` script and replaced it with a task

## Changes in 4.8.0
* The `create-pyxis-image` task no longer receives the `dataPath` parameter

## Changes in 4.7.0
* The `push-snapshot` task now gets the `resultsDirPath` parameter from `collect-data` results

## Changes in 4.6.0
* Add the task `update-cr-status` at the end of the pipeline to save all pipeline results

## Changes in 4.5.0
* The apply-mapping task now gets the dataPath parameter instead of releasePlanAdmissionPath

## Changes in 4.4.0
* `enterpriseContractExtraRuleData` added as a pipeline parameter, which is
  then passed to EC. Allows for easier runtime changes to rule data.

## Changes in 4.3.0
* Add new task `push-rpm-manifests-to-pyxis` to run after `create-pyxis-image`

## Changes in 4.2.0
* update the taskGitUrl default value due to migration
  to konflux-ci GitHub org

## Changes in 4.1.1
* Added `when` clause to
  `push-snapshot`,
  `collect-pyxis-params`,
  `create-pyxis-image` and
  `run-file-updates`  task in the pipeline to ensure it only executes when
  the `apply-mapping` task indicates that mapping was successful.

## Changes in 4.1.0
* Remove push-sbom-to-pyxis. It has been replaced by manifest-box.

## Changes in 4.0.0
* releaseServiceConfig added as a pipeline parameter that is passed to the collect-data task

## Changes in 3.0.0
* Parameters supplied by the Release Service operator now use camelCase format

## Changes in 2.2.0
* Modified the pipeline to dynamically source the `data.json`, `snapshot_spec.json` and
  `release_plan_admission.json` files from the results of the `collect-data` task.

## Changes in 2.1.1
* Tasks that interact with InternalRequests now have a pipelineRunUid parameter added to them to help with cleanup

## Changes in 2.1.0
* taskGitRevision no longer has a default. It will be provided by the operator and will always have the same value as
  the git revision in the PipelineRef definition of the PipelineRun if using a git resolver. See RHTAPREL-790 for details

## Changes in 2.0.0
* Renamed pipeline from `push-to-external-registry` to `rh-push-to-external-registry`

## Changes in 1.2.0
* taskGitUrl parameter is added. It is used to provide the git repo for the release-service-catalog tasks
* taskGitRevision parameter is added. It is used to provide the revision to be used in the taskGitUrl repo

## Changes in 1.1.0
* Pass path to ReleasePlanAdmission to the apply-mapping task

## Changes in 1.0.1
* Switch back to using bundle resolvers for the verify-enterprise-contract task

## Changes in 1.0.0
* Updated fileUpdatesPath parameter in run-file-updates task to use data.json
  instead of extra_data.json

## Changes in 0.23.0
* Removed tag, addGitShaTag, addSourceShaTag, addTimestampTag parameters
    * These are now provided in the data json that is collected in the collect-data task

## Changes in 0.22.0
* Remove extraConfig parameters as the information is now passed in the RPA data field
* Remove the git clone task
* Fix apply-mapping parameters

## Changes in 0.21.0
* pyxisSecret and pyxisServerType parameters were removed
    * They are now pulled from the data.json created by merging the Release CR data fields
    * This includes adding a new task `collect-pyxis-params` to emit the values as results

## Changes in 0.20.0
* Remove releasestrategy parameter

## Changes in 0.19.0
* Introduce new initial task - verify-access-to-resources
    * protection to verify that service accounts have required permissions to access
      resources before we start a pipeline.
    * If verification does not pass, the pipeline fails

## Changes in 0.18
* update Tekton API to v1
    * includes bumping all tasks to versions that use Tekton API v1

## Changes in 0.17
* run-file-updates now included
* add new enterpriseContractPublicKey parameter

## Changes in 0.16
* explicitly set IGNORE_REKOR value to "true" in the verify-enterprise-contract task
* use git resolvers for the verify-enterprise-contract task
    * the verify_ec_task_bundle parameter was placed with verify_ec_task_git_url,
      verify_ec_task_git_revision, and verify_ec_task_git_pathInRepo

## Changes in 0.15
* use new version of collect-data task with subdirectory parameter
* use PipelineRun UID for subdirectory inside the workspace
    * this will avoid the issue of parallel PipelineRuns overriding each other's data
* also use new version of apply-mapping which overrides the original snapshot_spec file
    * and specify snapshotPath for this task to point to the subdir

## Changes in 0.14
* update push-snapshot task to be v0.10

## Changes in 0.13
* git resolvers are used in place of release bundle resolvers

## Changes in 0.12
* the push-snapshot task was updated to version 0.9 to use `cosign copy` instead of `skopeo copy`

## Changes in 0.11
* the collect-data task was added
    * this includes adding the required parameters release, releaseplan, releaseplanadmission,
      and releasestrategy as pipeline parameters
* the snapshot parameter is now a namespaced name instead of a JSON string
    * task versions were updated in accordance with this change

## Changes in 0.10
* the verify_ec_task_bundle parameter was added
    * with this addition, the verify-enterprise-contract task version is no longer static

## Changes in 0.9
* addGitShaTag now defaults to true instead of false

## Changes in 0.8
* Use version 0.4 of apply-mapping task and set the new failOnEmptyResult parameter to true
    * This will ensure that if the result of mapping is an empty component list, the task will fail

## Changes in 0.7
* Upgrade push-snapshot task to version 0.7
    * Only the first 7 characters are used for the git sha tag in Quay.

## Changes in 0.6
Add `push-sbom-to-pyxis` task to the pipeline. This will ensure that sbom components
for the image are pushed to Pyxis as part of this pipeline.

## Changes in 0.5
The syntax for `taskRef.bundle` and `pipelineRef.bundle` is deprecated,
bundles resolver is used with new format.

## Changes in 0.4
* Upgrade push-snapshot task to version 0.6
    * addShaTag parameter is now named addSourceShaTag
    * addGitShaTag parameter is now supported and passed as a pipeline parameter to the task

## Changes in 0.3

* Upgrade push-snapshot task to version 0.5
    * addShaTag parameter is now supported and passed as a pipeline parameter to the task
    * addTimestampTag parameter is now supported and passed as a pipeline parameter to the task

## Changes in 0.2

* push-snapshot now supports tag parameter

## Changes in 0.1

* Upgrade create-pyxis-image task to version 0.2
  * correct incorrect snapshot param
