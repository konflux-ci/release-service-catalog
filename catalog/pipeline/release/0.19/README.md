# Release Pipeline

Tekton pipeline to release Stonesoup Snapshot to Quay.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| release | The namespaced name (namespace/name) of the Release custom resource initiating this pipeline execution | No | - |
| releaseplan | The namespaced name (namespace/name) of the releasePlan | No | - |
| releaseplanadmission | The namespaced name (namespace/name) of the releasePlanAdmission | No | - |
| releasestrategy | The namespaced name (namespace/name) of the releaseStrategy | No | - |
| snapshot | The namespaced name (namespace/name) of the snapshot | No | - |
| enterpriseContractPolicy | JSON representation of the policy to be applied when validating the enterprise contract | No | - |
| enterpriseContractPublicKey | Public key to use for validation by the enterprise contract | Yes | k8s://openshift-pipelines/public-key |
| extraConfigGitUrl |URL to the remote Git repository containing the extra config | No | - |
| extraConfigGitRevision | Revision to fetch from the remote Git repository containing the extra config | No | - |
| extraConfigPath | Path to the extra config file within the repository | No | - |
| addGitShaTag | When pushing the snapshot components, also push a tag with the image git sha | Yes | true |
| postCleanUp | Cleans up workspace after finishing executing the pipeline | Yes | true |
| verify_ec_task_git_url | The git repo url of the verify-enterprise-contract task | No | - |
| verify_ec_task_git_revision | The git repo revision the verify-enterprise-contract task | No | - |
| verify_ec_task_git_pathInRepo | The location of the verify-enterprise-contract task in its repo | No | - |

## Changes since 0.18
- explicitly set IGNORE_REKOR value to "true" in the verify-enterprise-contract task
- use git resolvers for the verify-enterprise-contract task
    - the verify_ec_task_bundle parameter was placed with verify_ec_task_git_url,
      verify_ec_task_git_revision, and verify_ec_task_git_pathInRepo
- add new enterpriseContractPublicKey parameter

## Changes since 0.17
* use new version of collect-data task with subdirectory parameter
* use PipelineRun UID for subdirectory inside the workspace
    * this will avoid the issue of parallel PipelineRuns overriding each other's data
* also use new version of apply-mapping which overrides the original snapshot_spec file
    * and specify snapshotPath for this task to point to the subdir

## Changes since 0.16
* git resolvers are used in place of release bundle resolvers

## Changes since 0.15
* the push-snapshot task was updated to version 0.9 to use `cosign copy` instead of `skopeo copy`

## Changes since 0.14
* the collect-data task was added
  * this includes adding the required parameters release, releaseplan, releaseplanadmission,
      and releasestrategy as pipeline parameters
* the snapshot parameter is now a namespaced name instead of a JSON string
  * task versions were updated in accordance with this change

## Changes since 0.13
* the verify_ec_task_bundle parameter was added
  * with this addition, the verify-enterprise-contract task version is no longer static

## Changes since 0.12
* addGitShaTag now defaults to true instead of false

## Changes since 0.11
* Use version 0.4 of apply-mapping task and set the new failOnEmptyResult parameter to true
  * This will ensure that if the result of mapping is an empty component list, the task will fail

## Changes since 0.10

Update tag of ec-task-bundle task

## Changes since 0.9

* The syntax for `taskRef.bundle` and `pipelineRef.bundle` is deprecated,
bundles resolver is used with new format.
* Upgrade push-snapshot task for v0.6 parameter
  * addGitShaTag parameter is now supported and passed as a pipeline parameter to the task with value false

## Changes since 0.8

Update tag of ec-task-bundle task

## Changes since 0.7

Pipeline name was changed:
* metadata.name = `release`

## Changes since 0.6

Pipeline definition was changed:
* Task `verify-enterprise-contract` now uses the param `STRICT: 1`

## Changes since 0.5

Pipeline definition was changed:
* Taskref renamed from `verify-enterprise-contract-v2` to `verify-enterprise-contract`
* Taskref `verify-enterprise-contract` points to new bundle location.

## Changes since 0.4

 Pipeline definition was changed:
  * Task `apply-mapping` was replaced with `task-apply-mapping`
  * Task `cleanup-workspace` was replaced with `task-cleanup-workspace`

## Changes since 0.3 (milestone-8)

 Pipeline definition was changed:
  * Parameter `applicationSnapshot` was changed to `snapshot`
  * Task `apply-mapping` was changed
    * Task parameter `applicationSnapshot` value was changed
      * old: $(params.applicationSnapshot)
      * new: $(params.snapshot)
  * Task `prepare-validation` was changed
    * Task parameter `applicationSnapshot` value was changed
      * old: $(params.applicationSnapshot)
      * new: $(params.snapshot)
  * Task `push-application-snapshot` was changed
    * Task parameter `mappedApplicationSnapshot` value was changed
      * old: $(params.mappedApplicationSnapshot)
      * new: $(params.mappedSnapshot)

## Changes since 0.2 (milestone-6)

* Pipeline definition was changed:
  * Parameter `policy` was changed to `enterpriseContractPolicy`
  * Task `verify-enterprise-contract` was changed
    * Task parameter `POLICY_CONFIGURATION` value was changed
      * old: $(params.policy)
      * new: $(params.enterpriseContractPolicy)

## Changes since 0.1 (milestone-5)

* Enterprise Contract task was changed:
  * Task `prepare-validation` was removed
  * Task `verify-enterprise-contract` was replaced
    * old: quay.io/hacbs-release/verify-enterprise-contract:main
    * new: quay.io/hacbs-release/verify-enterprise-contract-v2:main
    * Task Parameter `snapshot` was removed
    * Task parameter `IMAGES` was added
    * Task Parameter `STRICT` was added
    * Task Parameter `IMAGE_REF` was removed
    * Task Parameter `REKOR_HOST` was removed
