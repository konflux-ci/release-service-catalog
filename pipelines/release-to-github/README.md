# Release to GitHub Pipeline

Tekton release pipeline to release binaries extracted from the image built with RHTAP, sign a checksum file, and release the binaries and signed file to GitHub.

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

## Changes in 3.0.0
- releaseServiceConfig added as a pipeline parameter that is passed to the collect-data task

## Changes in 2.0.0
- Parameters supplied by the Release Service operator now use camelCase format

## Changes in 1.2.0
- Modified the pipeline to dynamically source the `snapshot_spec.json`
  file from the results of the `collect-data` task.

## Changes in 1.1.1
- Tasks that interact with InternalRequests now have a pipelineRunUid parameter added to them to help with cleanup

## Changes in 1.1.0
- taskGitRevision no longer has a default. It will be provided by the operator and will always have the same value as
  the git revision in the PipelineRef definition of the PipelineRun if using a git resolver. See RHTAPREL-790 for details

## Changes in 1.0.1
- Fixed bug where pipeline execution didn't wait for verify-enterprise-contract task to succeed
