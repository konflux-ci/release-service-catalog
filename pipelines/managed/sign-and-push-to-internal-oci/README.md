# sign-and-push-to-internal-oci pipeline

Tekton Pipeline to sign artifacts and push to internal oci registry.
Used to specifically sign artifacts that will be consumed in a second
build pipeline (creation of macOS and windows installers).
Per-component signingOptions in the ReleasePlanAdmission mapping select
the signing script and optional DMG creation and notarization.

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
| verify_ec_task_git_revision     | Previously used for the Conforma task git resolver, now deprecated and ignored                                                     | Yes      | ignored                                                   |
| taskGitUrl                      | The url to the git repo where the release-service-catalog tasks to be used are stored                                              | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision                 | The revision in the taskGitUrl repo to be used                                                                                     | No       | -                                                         |
| ociStorage                      | The OCI repository where the Trusted Artifacts are stored                                                                          | Yes      | quay.io/konflux-ci/release-service-trusted-artifacts      |
| orasOptions                     | oras options to pass to Trusted Artifacts calls                                                                                    | Yes      | ""                                                        |
| trustedArtifactsDebug           | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                             | Yes      | ""                                                        |
| quayURL                         | Quay URL of the repo where unsigned content is shared between tasks                                                                | Yes      | quay.io/konflux-artifacts                                 |
| macSigningScriptBase            | Directory containing macOS signing scripts on the remote host                                                                      | Yes      | /Users/konflux-release-signing-sa/mac-signing             |
| windowsSigningScriptBase        | Directory containing Windows signing scripts on the remote host                                                                    | Yes      | C:/Users/binary_signer/windows-signing                    |
| dataDir                         | The location where data will be stored                                                                                             | Yes      | /var/workdir/release                                      |
