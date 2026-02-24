# rh-push-to-registry-redhat-io pipeline

Tekton pipeline to release content to registry.redhat.io registry.

This pipeline is idempotent: components that have already been fully released are
automatically filtered out by verifying:
- Pyxis metadata: image record must have at least one repository with non-empty tags
  and non-empty content_sets (RPM data). A digest-only or partial record does not
  count as released, so reruns will still run push-rpm-data-to-pyxis if needed.
- fileUpdates completion (merged GitLab merge requests), checked via InternalRequest

When all components are filtered, downstream release tasks are skipped (skip_release=true).
This prevents redundant processing and allows safe re-runs of the same snapshot.

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
| taskGitUrl                      | The url to the git repo where the release-service-catalog tasks to be used are stored                                              | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision                 | The revision in the taskGitUrl repo to be used                                                                                     | No       | -                                                         |
| ociStorage                      | The OCI repository where the Trusted Artifacts are stored                                                                          | Yes      | quay.io/konflux-ci/release-service-trusted-artifacts      |
| orasOptions                     | oras options to pass to Trusted Artifacts calls                                                                                    | Yes      | ""                                                        |
| trustedArtifactsDebug           | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                             | Yes      | ""                                                        |
| dataDir                         | The location where data will be stored                                                                                             | Yes      | /var/workdir/release                                      |
