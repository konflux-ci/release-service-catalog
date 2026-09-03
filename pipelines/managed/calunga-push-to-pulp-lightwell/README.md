# calunga-push-to-pulp-lightwell pipeline

Release Components in a Snapshot to a pulp-backed python index. Each image in a Component is expected to contain a python wheel and sdist under the /releases directory. This is the Lightwell variant without advisory creation or SBOM uploads to Atlas, with optional sdist source mirroring to GitLab.

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
| enterpriseContractTimeout       | Timeout setting for `ec validate`                                                                                                  | Yes      | 40m0s                                                     |
| taskGitUrl                      | The url to the git repo where the release-service-catalog tasks to be used are stored                                              | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision                 | The revision in the taskGitUrl repo to be used                                                                                     | Yes      | production                                                |
| signingSecretName               | The name of the AWS KMS signing secret                                                                                             | Yes      | konflux-cosign-signing-production                         |
| ociStorage                      | URL to the OCI artifact storage                                                                                                    | Yes      | quay.io/konflux-ci/release-service-trusted-artifacts      |
| taisceCuanGitUrl                | Git repository URL where taisce-cuan tasks are stored                                                                              | Yes      | https://github.com/konflux-lightwell/taisce-cuan.git      |
| taisceCuanGitRevision           | Git revision for taisce-cuan tasks                                                                                                 | Yes      | main                                                      |
