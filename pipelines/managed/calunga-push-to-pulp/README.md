# calunga-push-to-pulp pipeline

Release Components in a Snapshot to a pulp-backed python index. Each image in a Component is expected to contain a python wheel and sdist under the /releases directory.

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
| verify_ec_task_bundle           | The location of the bundle containing the verify-enterprise-contract task                                                          | No       | -                                                         |
| verify_ec_task_git_revision     | The git revision to be used when consuming the verify-conforma task                                                                | No       | -                                                         |
| taskGitUrl                      | The url to the git repo where the release-service-catalog tasks to be used are stored                                              | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision                 | The revision in the taskGitUrl repo to be used                                                                                     | Yes      | production                                                |
| pulpBaseUrl                     | The base URL of the Pulp server                                                                                                    | Yes      | https://packages.redhat.com                               |
| pulpDomain                      | The domain to use for Pulp operations                                                                                              | Yes      | trusted-libraries                                         |
| pulpApiRoot                     | The API root path of the Pulp server                                                                                               | Yes      | /api/                                                     |
| serviceAccountSecretName        | The name of the secret containing the Pulp service account credentials                                                             | Yes      | rhtl-pulp-credentials-secret                              |
| pulpRepository                  | The Pulp repository to upload packages to                                                                                          | Yes      | main                                                      |
| signingSecretName               | The name of the AWS KMS signing secret                                                                                             | Yes      | konflux-cosign-signing-production                         |
| config                          | Name of the ConfigMap with config options, e.g. ociStorage                                                                         | Yes      | release-pipeline-config                                   |
