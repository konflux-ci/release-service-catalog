# push-oot-kmods pipeline

Tekton pipeline to sign out-of-tree kernel modules and upload them to an internal Gitlab repository.

## Parameters

| Name                            | Description                                                                                                                        | Optional | Default value                                             |
|---------------------------------|------------------------------------------------------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| release                         | The namespaced name of the Release custom resource initiating this pipeline execution                                              | No       | -                                                         |
| releasePlan                     | The namespaced name (namespace/name) of the releasePlan                                                                            | No       | -                                                         |
| releasePlanAdmission            | The namespaced name (namespace/name) of the releasePlanAdmission                                                                   | No       | -                                                         |
| releaseServiceConfig            | The namespaced name (namespace/name) of the releaseServiceConfig                                                                   | No       | -                                                         |
| snapshot                        | The namespaced name (namespace/name) of the snapshot                                                                               | No       | -                                                         |
| enterpriseContractPolicy        | JSON representation of the EnterpriseContractPolicy                                                                                | No       | -                                                         |
| enterpriseContractExtraRuleData | Extra rule data to be merged into the policy specified in params.enterpriseContractPolicy. Use syntax "key1=value1,key2=value2..." | Yes      | pipeline_intention=release                                |
| verify_ec_task_git_revision     | The git revision to be used when consuming the verify-conforma task                                                                | No       | -                                                         |
| ociStorage                      | The OCI repository where the Trusted Artifacts are stored                                                                          | Yes      | quay.io/konflux-ci/release-service-trusted-artifacts      |
| orasOptions                     | oras options to pass to Trusted Artifacts calls                                                                                    | Yes      | ""                                                        |
| trustedArtifactsDebug           | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                             | Yes      | ""                                                        |
| dataDir                         | The location where data will be stored                                                                                             | Yes      | /var/workdir/release                                      |
| taskGitRevision                 | The revision in the taskGitUrl repo to be used                                                                                     | Yes      | main                                                      |
| taskGitUrl                      | The url to the git repo where the release-service-catalog tasks to be used are stored                                              | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
