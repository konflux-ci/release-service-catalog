# Release Pipeline

Tekton pipeline to verify Snapshot prior to Deployment

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| release | The namespaced name (namespace/name) of the Release custom resource initiating this pipeline execution | No | - |
| releaseplan | The namespaced name (namespace/name) of the releasePlan | No | - |
| releaseplanadmission | The namespaced name (namespace/name) of the releasePlanAdmission | No | - |
| snapshot | The namespaced name (namespace/name) of the snapshot | No | - |
| enterpriseContractPolicy | JSON representation of the policy to be applied when validating the enterprise contract | No | - |
| enterpriseContractPublicKey | Public key to use for validation by the enterprise contract | Yes | k8s://openshift-pipelines/public-key |
| verify_ec_task_bundle | The location of the bundle containing the verify-enterprise-contract task | No | - |
| taskGitUrl | The url to the git repo where the release-service-catalog tasks to be used are stored | Yes | https://github.com/redhat-appstudio/release-service-catalog.git |
| taskGitRevision | The revision in the taskGitUrl repo to be used | Yes | staging |

## Changes in 0.12.0
- taskGitUrl parameter is added. It is used to provide the git repo for the release-service-catalog tasks
- taskGitRevision parameter is added. It is used to provide the revision to be used in the taskGitUrl repo

## Changes since 0.10.0
- Switch back to using bundle resolvers for the verify-enterprise-contract task

## Changes since 0.9.0
- Remove releasestrategy parameter

## Changes since 0.8.0
- Introduce new initial task - verify-access-to-resources
    - protection to verify that service accounts have required permissions to access
      resources before we start a pipeline.
    - If verification does not pass, the pipeline fails

## Changes since 0.7
- update Tekton API to v1
    - includes bumping all tasks to versions that use Tekton API v1

## Changes since 0.6
- explicitly set IGNORE_REKOR value to "true" in the verify-enterprise-contract task
- use git resolvers for the verify-enterprise-contract task
    - the verify_ec_task_bundle parameter was placed with verify_ec_task_git_url,
      verify_ec_task_git_revision, and verify_ec_task_git_pathInRepo
- add new enterpriseContractPublicKey parameter

## Changes since 0.5
- use new version of collect-data task with subdirectory parameter
- use PipelineRun UID for subdirectory inside the workspace
    - this will avoid the issue of parallel PipelineRuns overriding each other's data

## Changes since 0.4
- git resolvers are used in place of release bundle resolvers

## Changes since 0.3
- the collect-data task was added
    - this includes adding the required parameters release, releaseplan, releaseplanadmission,
      and releasestrategy as pipeline parameters
    - a workspace is now mounted by the pipeline as required by this task
- the snapshot parameter is now a namespaced name instead of a JSON string

## Changes since 0.2
- the verify_ec_task_bundle parameter was added
    - with this addition, the verify-enterprise-contract task version is no longer static

## Changes since 0.1

The syntax for `taskRef.bundle` and `pipelineRef.bundle` is deprecated,
bundles resolver is used with new format.
