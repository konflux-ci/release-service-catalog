# rh-push-to-registry-redhat-io pipeline

Tekton pipeline to push images to a registry.redhat.io registry.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| release | The namespaced name (namespace/name) of the Release custom resource initiating this pipeline execution | No | - |
| releaseplan | The namespaced name (namespace/name) of the releasePlan | No | - |
| releaseplanadmission | The namespaced name (namespace/name) of the releasePlanAdmission | No | - |
| releasestrategy | The namespaced name (namespace/name) of the releaseStrategy | No | - |
| snapshot | The namespaced name (namespace/name) of the snapshot | No | - |
| enterpriseContractPolicy | JSON representation of the policy to be applied when validating the enterprise contract | No | - |
| enterpriseContractPublicKey | Public key to use for validation by the enterprise contract | Yes | k8s://openshift-pipelines/public-key |
| extraConfigGitUrl |URL to the remote Git repository containing the extra config | No | - |
| extraConfigGitRevision | Revision to fetch from the remote Git repository containing the extra config | No | - |
| extraConfigPath | Path to the extra config file within the repository | No | - |
| tag | The default tag to use when mapping file does not contain a tag | No | - |
| addGitShaTag | When pushing the snapshot components, also push a tag with the image git sha | Yes | true |
| addSourceShaTag | When pushing the snapshot components, also push a tag with the image source sha | Yes | true |
| addTimestampTag | When pushing the snapshot components, also push a tag with the current timestamp | Yes | false |
| pyxisServerType | The Pyxis server type to use. Options are 'production' and 'stage' | No | - |
| pyxisSecret | The kubernetes secret to use to authenticate to Pyxis. It needs to contain two keys: key and cert | No | - |
| postCleanUp | Cleans up workspace after finishing executing the pipeline | Yes | true |
| verify_ec_task_git_url | The git repo url of the verify-enterprise-contract task | No | - |
| verify_ec_task_git_revision | The git repo revision the verify-enterprise-contract task | No | - |
| verify_ec_task_git_pathInRepo | The location of the verify-enterprise-contract task in its repo | No | - |
