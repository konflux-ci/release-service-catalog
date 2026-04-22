# rh-advisories pipeline

Tekton pipeline to release content to registry.redhat.io registry and create an advisory.
This is a copy of v3.0.0 of the rh-push-to-registry-redhat-io pipeline, but with the advisory
tasks added in. The plan is for this pipeline to eventually be deleted and take the place of
the rh-push-to-registry-redhat-io pipeline.

## Idempotent re-release behavior

When the same snapshot is released a second time, the filter-already-released-advisory-images
task detects that all images are already published in an existing advisory and sets
skip_release=true. In this case all normal release tasks (signing, pushing, advisory creation,
etc.) are skipped.

To ensure release.status.artifacts.advisory.url is still populated after an idempotent
re-release, the pipeline includes a dedicated update-cr-status-skipped task that runs only
when skip_release=true. It reads the advisory URL written to the results directory by
filter-already-released-advisory-images and patches the Release CR status in the same way
the normal update-cr-status task does on the first release.

## Parameters

| Name                            | Description                                                                                                                        | Optional | Default value                                             |
|---------------------------------|------------------------------------------------------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| release                         | The namespaced name (namespace/name) of the Release custom resource initiating this pipeline execution                             | No       | -                                                         |
| releasePlan                     | The namespaced name (namespace/name) of the releasePlan                                                                            | No       | -                                                         |
| releasePlanAdmission            | The namespaced name (namespace/name) of the releasePlanAdmission                                                                   | No       | -                                                         |
| releaseServiceConfig            | The namespaced name (namespace/name) of the releaseServiceConfig                                                                   | No       | -                                                         |
| snapshot                        | The namespaced name (namespace/name) of the snapshot                                                                               | No       | -                                                         |
| enterpriseContractPolicy        | JSON representation of the EnterpriseContractPolicy                                                                                | No       | -                                                         |
| enterpriseContractExtraRuleData | Extra rule data to be merged into the policy specified in params.enterpriseContractPolicy. Use syntax "key1=value1,key2=value2..." | Yes      | pipeline_intention=release                                |
| verify_ec_task_bundle           | The location of the bundle containing the verify-enterprise-contract task                                                          | No       | -                                                         |
| verify_ec_task_git_revision     | The git revision to be used when consuming the verify-conforma task                                                                | No       | -                                                         |
| mobster_tasks_git_revision      | The git revision to be used when consuming Mobster tasks for SBOM processing                                                       | Yes      | 53ebdf3b46a10fc4b0e60b32171e8a7b4834ede6                  |
| taskGitUrl                      | The url to the git repo where the release-service-catalog tasks to be used are stored                                              | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision                 | The revision in the taskGitUrl repo to be used                                                                                     | No       | -                                                         |
| ociStorage                      | The OCI repository where the Trusted Artifacts are stored                                                                          | Yes      | quay.io/konflux-ci/release-service-trusted-artifacts      |
| orasOptions                     | oras options to pass to Trusted Artifacts calls                                                                                    | Yes      | ""                                                        |
| trustedArtifactsDebug           | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                             | Yes      | ""                                                        |
| dataDir                         | The location where data will be stored                                                                                             | Yes      | /var/workdir/release                                      |
| conformaPubKey                  | Path to the key used by Conforma to verify attestations signed by it                                                               | Yes      | k8s://openshift-pipelines/public-key                      |
