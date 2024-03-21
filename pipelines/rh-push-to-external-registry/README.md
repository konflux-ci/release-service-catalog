# Red Hat Push to External Registry Pipeline

Tekton pipeline to release Red Hat Snapshots to an external registry. This pipeline includes pyxis interactions.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| release | The namespaced name (namespace/name) of the Release custom resource initiating this pipeline execution | No | - |
| releasePlan | The namespaced name (namespace/name) of the releasePlan | No | - |
| releasePlanAdmission | The namespaced name (namespace/name) of the releasePlanAdmission | No | - |
| releaseServiceConfig | The namespaced name (namespace/name) of the releaseServiceConfig | No | - |
| snapshot | The namespaced name (namespace/name) of the snapshot | No | - |
| enterpriseContractPolicy | JSON representation of the policy to be applied when validating the enterprise contract | No | - |
| enterpriseContractPublicKey | Public key to use for validation by the enterprise contract | Yes | k8s://openshift-pipelines/public-key |
| postCleanUp | Cleans up workspace after finishing executing the pipeline | Yes | true |
| verify_ec_task_bundle | The location of the bundle containing the verify-enterprise-contract task | No | - |
| taskGitUrl | The url to the git repo where the release-service-catalog tasks to be used are stored | Yes | https://github.com/redhat-appstudio/release-service-catalog.git |
| taskGitRevision | The revision in the taskGitUrl repo to be used | No | - |

## Changes in 4.1.0
- Remove push-sbom-to-pyxis. It has been replaced by manifest-box.

## Changes in 4.0.0
- releaseServiceConfig added as a pipeline parameter that is passed to the collect-data task

## Changes in 3.0.0
- Parameters supplied by the Release Service operator now use camelCase format

## Changes in 2.2.0
- Modified the pipeline to dynamically source the `data.json`, `snapshot_spec.json` and
  `release_plan_admission.json` files from the results of the `collect-data` task.

## Changes in 2.1.1
- Tasks that interact with InternalRequests now have a pipelineRunUid parameter added to them to help with cleanup

## Changes in 2.1.0
- taskGitRevision no longer has a default. It will be provided by the operator and will always have the same value as
  the git revision in the PipelineRef definition of the PipelineRun if using a git resolver. See RHTAPREL-790 for details

## Changes in 2.0.0
- Renamed pipeline from `push-to-external-registry` to `rh-push-to-external-registry`

## Changes in 1.2.0
- taskGitUrl parameter is added. It is used to provide the git repo for the release-service-catalog tasks
- taskGitRevision parameter is added. It is used to provide the revision to be used in the taskGitUrl repo

## Changes since 1.1.0
- Pass path to ReleasePlanAdmission to the apply-mapping task

## Changes since 1.0.1
- Switch back to using bundle resolvers for the verify-enterprise-contract task

## Changes since 1.0.0
- Updated fileUpdatesPath parameter in run-file-updates task to use data.json
  instead of extra_data.json

## Changes since 0.23.0
- Removed tag, addGitShaTag, addSourceShaTag, addTimestampTag parameters
    - These are now provided in the data json that is collected in the collect-data task

## Changes since 0.22.0
- Remove extraConfig parameters as the information is now passed in the RPA data field
- Remove the git clone task
- Fix apply-mapping parameters

## Changes since 0.21.0
- pyxisSecret and pyxisServerType parameters were removed
    - They are now pulled from the data.json created by merging the Release CR data fields
    - This includes adding a new task `collect-pyxis-params` to emit the values as results

## Changes since 0.20.0
- Remove releasestrategy parameter

## Changes since 0.19.0
- Introduce new initial task - verify-access-to-resources
    - protection to verify that service accounts have required permissions to access
      resources before we start a pipeline.
    - If verification does not pass, the pipeline fails

## Changes since 0.18
- update Tekton API to v1
    - includes bumping all tasks to versions that use Tekton API v1

## Changes since 0.17
- run-file-updates now included
- add new enterpriseContractPublicKey parameter

## Changes since 0.16
- explicitly set IGNORE_REKOR value to "true" in the verify-enterprise-contract task
- use git resolvers for the verify-enterprise-contract task
    - the verify_ec_task_bundle parameter was placed with verify_ec_task_git_url,
      verify_ec_task_git_revision, and verify_ec_task_git_pathInRepo

## Changes since 0.15
- use new version of collect-data task with subdirectory parameter
- use PipelineRun UID for subdirectory inside the workspace
    - this will avoid the issue of parallel PipelineRuns overriding each other's data
- also use new version of apply-mapping which overrides the original snapshot_spec file
    - and specify snapshotPath for this task to point to the subdir

## Changes since 0.14
* update push-snapshot task to be v0.10

## Changes since 0.13
* git resolvers are used in place of release bundle resolvers

## Changes since 0.12
* the push-snapshot task was updated to version 0.9 to use `cosign copy` instead of `skopeo copy`

## Changes since 0.11
* the collect-data task was added
    * this includes adding the required parameters release, releaseplan, releaseplanadmission,
      and releasestrategy as pipeline parameters
* the snapshot parameter is now a namespaced name instead of a JSON string
    * task versions were updated in accordance with this change

## Changes since 0.10
* the verify_ec_task_bundle parameter was added
    * with this addition, the verify-enterprise-contract task version is no longer static

## Changes since 0.9
* addGitShaTag now defaults to true instead of false

## Changes since 0.8
* Use version 0.4 of apply-mapping task and set the new failOnEmptyResult parameter to true
    * This will ensure that if the result of mapping is an empty component list, the task will fail

## Changes since 0.7
* Upgrade push-snapshot task to version 0.7
    * Only the first 7 characters are used for the git sha tag in Quay.

## Changes since 0.6
Add `push-sbom-to-pyxis` task to the pipeline. This will ensure that sbom components
for the image are pushed to Pyxis as part of this pipeline.

## Changes since 0.5
The syntax for `taskRef.bundle` and `pipelineRef.bundle` is deprecated,
bundles resolver is used with new format.

## Changes since 0.4
* Upgrade push-snapshot task to version 0.6
    * addShaTag parameter is now named addSourceShaTag
    * addGitShaTag parameter is now supported and passed as a pipeline parameter to the task

## Changes since 0.3

* Upgrade push-snapshot task to version 0.5
    * addShaTag parameter is now supported and passed as a pipeline parameter to the task
    * addTimestampTag parameter is now supported and passed as a pipeline parameter to the task

## Changes since 0.2

* push-snapshot now supports tag parameter

## Changes since 0.1

* Upgrade create-pyxis-image task to version 0.2
  * correct incorrect snapshot param
