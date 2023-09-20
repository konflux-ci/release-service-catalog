# FBC Release Pipeline

Tekton release pipeline to interact with FBC Pipeline

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| release | The namespaced name (namespace/name) of the Release custom resource initiating this pipeline execution | No | - |
| releaseplan | The namespaced name (namespace/name) of the releasePlan | No | - |
| releaseplanadmission | The namespaced name (namespace/name) of the releasePlanAdmission | No | - |
| releasestrategy | The namespaced name (namespace/name) of the releaseStrategy | No | - |
| snapshot | The namespaced name (namespace/name) of the snapshot | No | - |
| enterpriseContractPolicy | JSON representation of the EnterpriseContractPolicy | No | - |
| enterpriseContractPublicKey | Public key to use for validation by the enterprise contract | Yes | k8s://openshift-pipelines/public-key |
| fromIndex | The source Index image (catalog of catalogs) FBC fragment | No | - |
| targetIndex | Index image (catalog of catalogs) the FBC fragment will be added to | No | - |
| binaryImage | OCP binary image to be baked into the index image | Yes | "" |
| buildTags | List of additional tags the internal index image copy should be tagged with | Yes | "[]" |
| addArches | List of arches the index image should be built for | Yes | "[]" |
| signingConfigMapName | The ConfigMap to be used by the signing Pipeline | Yes | "hacbs-signing-pipeline-config" |
| iibServiceConfigSecret | Secret that contains IIB's service configuration | Yes | "iib-services-config" |
| iibOverwriteFromIndexCredential | Secret that stores IIB's overwrite_from_index_token parameter value | Yes | "iib-overwrite-fromimage-credentials" |
| fbcPublishingCredentials | Secret used to publish the built index image | Yes | "fbc-publishing-credentials" |
| requestUpdateTimeout | Max seconds to wait until the status is updated | Yes | - |
| buildTimeoutSeconds | Max seconds to wait until the build finishes | Yes | - |
| verify_ec_task_git_url | The git repo url of the verify-enterprise-contract task | No | - |
| verify_ec_task_git_revision | The git repo revision the verify-enterprise-contract task | No | - |
| verify_ec_task_git_pathInRepo | The location of the verify-enterprise-contract task in its repo | No | - |

## Changelog

### Changes since 0.22
- adds new tasks `validate-single-component` to validates that the 
  snapshot only contains a single component. A pipeline should fail otherwise.

### Changes since 0.21
- update Tekton API to v1
    - includes bumping all tasks to versions that use Tekton API v1

### Changes since 0.20
- iibIndexImage and iibIndexImageResolved pipelineResults were added. These come from the
  task results in extract-index-image

### Changes since 0.19
- adds new tasks `get-ocp-version` and `update-ocp-tag` to update version tag
  for `targetIndex`, `fromIndex` and `binaryImage` with valid OCP Version
- add new enterpriseContractPublicKey parameter

### Changes since 0.18
- explicitly set IGNORE_REKOR value to "true" in the verify-enterprise-contract task
- use git resolvers for the verify-enterprise-contract task
    - the verify_ec_task_bundle parameter was placed with verify_ec_task_git_url,
      verify_ec_task_git_revision, and verify_ec_task_git_pathInRepo

### Changes since 0.17
- use new version of collect-data task with subdirectory parameter
- use PipelineRun UID for subdirectory inside the workspace
    - this will avoid the issue of parallel PipelineRuns overriding each other's data
- use new version of create-internal-requests task with subdirectory parameter

### Changes since 0.16
- git resolvers are used in place of release bundle resolvers

### Changes since 0.15
- the collect-data task was added
    - this includes adding the required parameters releaseplan, releaseplanadmission, and
      releasestrategy as pipeline parameters
- the snapshot parameter is now a namespaced name instead of a JSON string
    - task versions were updated in accordance with this change

### Changes since 0.14
- adds parameters `iibServiceConfigSecret` and `iibOverwriteFromIndexCredential`
  to enable the build of pre-GA and prod FBC components in the same namespace

### Changes since 0.13
- adds back the parameter `fbcPublishingCredentials` as different secrets
  might be set for the same namespace

### Changes since 0.12
- the release parameter was added and the requester parameter was removed
    - the value to use for signing is now pulled from the release resource status

### Changes since 0.11
- updates tasks that use `create-internal-request` task to 0.6 as now they need to
  rely on its `genericResult` result
- the task `publish-index-image` now uses `create-internal-request` so the publishing
  is done by the cluster running the internal-services-controller
- only executes `publish-index-image` and `sign-index-image` when genericResult result of
  the tasks using `create-internal-request` has `fbc_opt_in=true` value set
- removes `fbcPublishingCredentials` parameter
- removes `overwriteFromIndex` parameter

### Changes since 0.10
- the verify_ec_task_bundle parameter was added
    - with this addition, the verify-enterprise-contract task version is no longer static

### Changes since 0.9
- changes on the following tasks due to `create-internal-request` changes:
    - `add-fbc-contribution-to-index-image` now accepts dynamic parameters
    - `sign-index-image` now accepts dynamic parameters
- changes on `publish-index-image` task to read data from its `inputDataFile` parameter
- adds cleanup task

### Changes since 0.8
- fixes in the README.md file
- adds param `fbcPublishingCredentials`
- removes param `overwriteFromIndex`
- adds new task `publish-index-image`

### Changes since 0.7
The syntax for `taskRef.bundle` and `pipelineRef.bundle` is deprecated,
bundles resolver is used with new format.

### Changes since 0.6
- adds sign-index-image task
- refactor task and change its reference name from `create-internal-request`
  to `add-fbc-contribution-to-index-image`
- adds `requester` and `signingConfigMapName` parameters
- removes `resolvedIndexImage` result

### Changes since 0.5
- updates `create-internal-request` task version to 0.3

### Changes since 0.4
- updates `create-internal-request` task version to 0.2
- adds `resolvedIndexImage` result

### Changes since 0.3
- removes param `fbcFragment`
- adds param `buildTimeoutSeconds`

### Changes since 0.2
- renames the pipeline to `fbc-release`
- forces the pipeline to run after `verify-enterprise-contract`

### Changes since 0.1
- adds param `requestUpdateTimeout`
- adds task result values to the pipeline results
  - `requestMessage` gets `$(tasks.create-internal-request.results.requestMessage)`
  - `requestReason` gets `$(tasks.create-internal-request.results.requestReason)`
  - `requestResults` gets `$(tasks.create-internal-request.results.requestResults)`
- changes `verify-enterprise-contract` task version
