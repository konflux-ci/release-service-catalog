# Release Pipeline

Tekton pipeline to verify Snapshot prior to Deployment

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| release | The namespaced name (namespace/name) of the Release custom resource initiating this pipeline execution | No | - |
| releaseplan | The namespaced name (namespace/name) of the releasePlan | No | - |
| releaseplanadmission | The namespaced name (namespace/name) of the releasePlanAdmission | No | - |
| releasestrategy | The namespaced name (namespace/name) of the releaseStrategy | No | - |
| snapshot | The namespaced name (namespace/name) of the snapshot | No | - |
| enterpriseContractPolicy | JSON representation of the policy to be applied when validating the enterprise contract | No | - |
| verify_ec_task_bundle | The location of the bundle containing the verify-enterprise-contract task | No | - |

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
