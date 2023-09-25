# Push to External Registry Pipeline

Tekton pipeline to push images to an external registry.

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
| tag | The default tag to use when mapping file does not contain a tag | No | - |
| addGitShaTag | When pushing the snapshot components, also push a tag with the image git sha | Yes | true |
| addSourceShaTag | When pushing the snapshot components, also push a tag with the image source sha | Yes | true |
| addTimestampTag | When pushing the snapshot components, also push a tag with the current timestamp | Yes | false |
| pyxisServerType | The Pyxis server type to use. Options are 'production' and 'stage' | No | - |
| pyxisSecret | The kubernetes secret to use to authenticate to Pyxis. It needs to contain two keys: key and cert | No | - |
| postCleanUp | Cleans up workspace after finishing executing the pipeline | Yes | true |
| verify_ec_task_git_url | The git repo url of the verify-enterprise-contract task | No | - |
| verify_ec_task_git_revision | The git repo revision the verify-enterprise-contract task | No | - |
| verify_ec_task_git_pathInRepo | The location of the verify-enterprise-contract task in its repo | No | - |

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

