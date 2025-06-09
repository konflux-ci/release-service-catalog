# push-rpm-to-koji pipeline

Tekton pipeline to push rpms into the koji instance.

## Parameters

| Name                            | Description                                                                                                                        | Optional | Default value                                             |
|---------------------------------|------------------------------------------------------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| release                         | The namespaced name (namespace/name) of the Release custom resource initiating this pipeline execution                             | No       | -                                                         |
| releasePlan                     | The namespaced name (namespace/name) of the releasePlan                                                                            | No       | -                                                         |
| releasePlanAdmission            | The namespaced name (namespace/name) of the releasePlanAdmission                                                                   | No       | -                                                         |
| releaseServiceConfig            | The namespaced name (namespace/name) of the releaseServiceConfig                                                                   | No       | -                                                         |
| snapshot                        | The namespaced name (namespace/name) of the snapshot                                                                               | No       | -                                                         |
| postCleanUp                     | Cleans up workspace after finishing executing the pipeline                                                                         | Yes      | true                                                      |
| taskGitUrl                      | The url to the git repo where the release-service-catalog tasks to be used are stored                                              | No       | -                                                         |
| taskGitRevision                 | The revision in the taskGitUrl repo to be used                                                                                     | No       | -                                                         |
| enterpriseContractPolicy        | JSON representation of the EnterpriseContractPolicy                                                                                | No       | -                                                         |
| enterpriseContractPublicKey     | Public key to use for validation by the enterprise contract                                                                        | Yes      | k8s://openshift-pipelines/public-key                      |
| verify_ec_task_bundle           | The location of the bundle containing the verify-enterprise-contract task                                                          | No       | -                                                         |
| enterpriseContractExtraRuleData | Extra rule data to be merged into the policy specified in params.enterpriseContractPolicy. Use syntax "key1=value1,key2=value2..." | Yes      | pipeline_intention=release                                |
| enterpriseContractTimeout       | Timeout setting for `ec validate`                                                                                                  | Yes      | 8h0m0s                                                    |
| enterpriseContractWorkerCount   | Number of parallel workers for policy evaluation                                                                                   | Yes      | 4                                                         |

## Changes in 0.2.0
* Avoid importing to Koji if enterprise contract verification fails
