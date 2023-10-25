# rh-push-to-registry-redhat-io pipeline

Tekton pipeline to release content to registry.redhat.io registry.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| release | The namespaced name (namespace/name) of the Release custom resource initiating this pipeline execution | No | - |
| releaseplan | The namespaced name (namespace/name) of the releasePlan | No | - |
| releaseplanadmission | The namespaced name (namespace/name) of the releasePlanAdmission | No | - |
| snapshot | The namespaced name (namespace/name) of the snapshot | No | - |
| enterpriseContractPolicy | JSON representation of the policy to be applied when validating the enterprise contract | No | - |
| enterpriseContractPublicKey | Public key to use for validation by the enterprise contract | Yes | k8s://openshift-pipelines/public-key |
| postCleanUp | Cleans up workspace after finishing executing the pipeline | Yes | true |
| verify_ec_task_bundle | The location of the bundle containing the verify-enterprise-contract task | No | - |
| verify_ec_task_git_url | The git repo url of the verify-enterprise-contract task | No | - |
| verify_ec_task_git_revision | The git repo revision the verify-enterprise-contract task | No | - |
| verify_ec_task_git_pathInRepo | The location of the verify-enterprise-contract task in its repo | No | - |


## Changes since 1.1.1
* Add tasks extract-requester-from-release and rh-sign-image so the pipeline can sign
  component images using the requester username

## Changes since 1.1.0
* Pass path to ReleasePlanAdmission to the apply-mapping task

## Changes since 1.0.0
* Switch back to using bundle resolvers for the verify-enterprise-contract task

## Changes since 0.1.0
* Removed tagPrefix, timestampFormat, tag, addGitShaTag, addSourceShaTag, addTimestampTag parameters
  * These are now provided in the data json that is collected in the collect-data task
