# Release Pipeline

Tekton pipeline to release Stonesoup Snapshot to Quay.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| snapshot | The Snapshot in JSON format | No | - |
| enterpriseContractPolicy | JSON representation of the policy to be applied when validating the enterprise contract | No | - |
| extraConfigGitUrl |URL to the remote Git repository containing the extra config | No | - |
| extraConfigGitRevision | Revision to fetch from the remote Git repository containing the extra config | No | - |
| extraConfigPath | Path to the extra config file within the repository | No | - |
| addGitShaTag | When pushing the snapshot components, also push a tag with the image git sha | Yes | false |
| postCleanUp | Cleans up workspace after finishing executing the pipeline | Yes | true |

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
