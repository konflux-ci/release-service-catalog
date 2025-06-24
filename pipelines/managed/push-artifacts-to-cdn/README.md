# push-artifacts-to-cdn pipeline

Tekton Pipeline to push artifacts to either CDN and/or CGW with signing.
It uses InternalRequests so that it can be run on both public and private clusters.

## Parameters

| Name                            | Description                                                                                                                         | Optional | Default value                                             |
|---------------------------------|-------------------------------------------------------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| release                         | The namespaced name (namespace/name) of the Release custom resource initiating this pipeline execution                              | No       | -                                                         |
| releasePlan                     | The namespaced name (namespace/name) of the releasePlan                                                                             | No       | -                                                         |
| releasePlanAdmission            | The namespaced name (namespace/name) of the releasePlanAdmission                                                                    | No       | -                                                         |
| releaseServiceConfig            | The namespaced name (namespace/name) of the releaseServiceConfig                                                                    | No       | -                                                         |
| snapshot                        | The namespaced name (namespace/name) of the snapshot                                                                                | No       | -                                                         |
| enterpriseContractPolicy        | JSON representation of the policy to be applied when validating the enterprise contract                                             | No       | -                                                         |
| enterpriseContractExtraRuleData | Extra rule data to be merged into the policy specified in params.enterpriseContractPolicy. Use syntax "key1=value1,key2=value2..."  | Yes      | pipeline_intention=release                                |
| enterpriseContractTimeout       | Timeout setting for `ec validate`                                                                                                   | Yes      | 10m0s                                                     |
| enterpriseContractWorkerCount   | Number of parallel workers for policy evaluation                                                                                    | Yes      | 4                                                         |
| postCleanUp                     | Cleans up workspace after finishing executing the pipeline                                                                          | Yes      | true                                                      |
| verify_ec_task_bundle           | The location of the bundle containing the verify-enterprise-contract task                                                           | No       | -                                                         |
| verify_ec_task_git_revision     | The git revision to be used when consuming the verify-conforma task                                                                 | No       | -                                                         |
| taskGitUrl                      | The url to the git repo where the release-service-catalog tasks to be used are stored                                               | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision                 | The revision in the taskGitUrl repo to be used                                                                                      | No       | -                                                         |
| ociStorage                      | The OCI repository where the Trusted Artifacts are stored                                                                           | Yes      | quay.io/konflux-ci/release-service-trusted-artifacts     |
| orasOptions                     | oras options to pass to Trusted Artifacts calls                                                                                     | Yes      | ""                                                        |
| trustedArtifactsDebug           | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                              | Yes      | ""                                                        |
| dataDir                         | The location where data will be stored                                                                                              | Yes      | /var/workdir/release                                      |


## Changes in 2.0.1
* Fixed trusted artifacts references throughout the pipeline
* Corrected `sourceDataArtifact` references in task parameters
* Updated `update-cr-status` task to use `resultArtifacts` parameter instead of `sourceDataArtifact`
* Fixed task execution order to ensure `update-cr-status` runs after all required results are available

## Changes in 2.0.0
* **BREAKING**: Migrated to trusted artifacts architecture for enhanced security and traceability
* Added trusted artifacts parameters: `ociStorage`, `orasOptions`, `trustedArtifactsDebug`, `dataDir`
* Added `enterpriseContractWorkerCount` parameter for configurable parallel processing
* Replaced `verify-enterprise-contract` task with `verify-conforma` task for better performance
* All tasks now use trusted artifacts for data exchange instead of shared workspaces
* Updated file paths to use `dataDir` instead of workspace paths

### Changes in 1.0.1
* Added retries in the pipline 

### Changes in 1.0.0
* Added advisory generation tasks:
  - `populate-release-notes` - Populates release notes for the advisory
  - `embargo-check` - Checks for embargoed content
  - `create-advisory` - Creates the actual advisory
  - `close-advisory-issues` - Closes any related advisory issues

## Changes in 0.2.1
* Required parameter `releasePath` is now passed to the `push-artifacts-to-cdn` task

## Changes in 0.2.0
* Update all tasks that now support trusted artifacts to specify the taskGit* parameters for the step action resolvers
* Align workspace name with changes in the apply-mapping task

## Changes in 0.1.0
* Add new parameter `verify_ec_task_git_revision` needed for consuming the verify-conforma task
  via git resolver
