# Release Pipeline

Tekton pipeline to verify Snapshot prior to Deployment

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| snapshot | The Snapshot in JSON format | No | - |
| enterpriseContractPolicy | JSON representation of the policy to be applied when validating the enterprise contract | No | - |
| verify_ec_task_bundle | The location of the bundle containing the verify-enterprise-contract task | No | - |

### Changes since 0.2
- the verify_ec_task_bundle parameter was added
    - with this addition, the verify-enterprise-contract task version is no longer static

## Changes since 0.1

The syntax for `taskRef.bundle` and `pipelineRef.bundle` is deprecated,
bundles resolver is used with new format.
