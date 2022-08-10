# Milestone-6 Release Pipeline

Tekton pipeline to release HACBS Application Snapshot to Quay.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| applicationSnapshot | The ApplicationSnapshot in JSON format | No | - |
| policy | Name of the policy to apply when validating the enterprise contract | No | - |
| extraConfigGitUrl |URL to the remote Git repository containing the extra config | No | - |
| extraConfigGitRevision | Revision to fetch from the remote Git repository containing the extra config | No | - |
| extraConfigPath | Path to the extra config file within the repository | No | - |
| postCleanUp | Cleans up workspace after finishing executing the pipeline | Yes | true |

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
