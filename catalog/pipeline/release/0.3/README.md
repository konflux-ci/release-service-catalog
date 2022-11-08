# Milestone-9 Release Pipeline

Tekton pipeline to release HACBS Application Snapshot to Quay.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| applicationSnapshot | The ApplicationSnapshot in JSON format | No | - |
| enterpriseContractPolicy | JSON representation of the policy to be applied when validating the enterprise contract | No | - |
| extraConfigGitUrl |URL to the remote Git repository containing the extra config | No | - |
| extraConfigGitRevision | Revision to fetch from the remote Git repository containing the extra config | No | - |
| extraConfigPath | Path to the extra config file within the repository | No | - |
| postCleanUp | Cleans up workspace after finishing executing the pipeline | Yes | true |


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
    * Task Parameter `applicationSnapshot` was removed
    * Task parameter `IMAGES` was added
    * Task Parameter `STRICT` was added
    * Task Parameter `IMAGE_REF` was removed
    * Task Parameter `REKOR_HOST` was removed
