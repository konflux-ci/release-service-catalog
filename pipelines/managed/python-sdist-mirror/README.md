# python-sdist-mirror pipeline

Phase 1 Managed Release Pipeline: mirrors ingested Python sdists and signed provenance from a Snapshot OCI artifact into the canonical internal git repository (gitlab.cee.redhat.com/lightwell/lightwell-builds/pypi.org-<pkg>).
Unlike wheel release pipelines, this pipeline does NOT perform wheel signing or Pulp wheel uploads; it strictly evaluates Conforma / EC policy and pushes the source tree and provenance to GitLab.

## Parameters

| Name                            | Description                                                               | Optional | Default value                                                    |
|---------------------------------|---------------------------------------------------------------------------|----------|------------------------------------------------------------------|
| release                         | The namespaced name of the Release CR                                     | No       | -                                                                |
| releasePlan                     | The namespaced name of the ReleasePlan CR                                 | No       | -                                                                |
| releasePlanAdmission            | The namespaced name of the ReleasePlanAdmission CR                        | No       | -                                                                |
| releaseServiceConfig            | The namespaced name of the ReleaseServiceConfig CR                        | No       | -                                                                |
| snapshot                        | The namespaced name of the Snapshot CR                                    | No       | -                                                                |
| enterpriseContractPolicy        | JSON string containing the Enterprise Contract policy configuration       | No       | -                                                                |
| enterpriseContractExtraRuleData | Extra rule data for Enterprise Contract                                   | Yes      | ""                                                               |
| enterpriseContractTimeout       | Timeout for Enterprise Contract evaluation                                | Yes      | 1h0m0s                                                           |
| taskGitUrl                      | Git repository containing the release tasks                               | Yes      | https://github.com/konflux-lightwell/release-service-catalog.git |
| taskGitRevision                 | Git revision for release tasks                                            | Yes      | development-python                                               |
| taisceCuanGitUrl                | Git repository containing taisce-cuan tasks                            | Yes      | https://github.com/konflux-lightwell/taisce-cuan.git             |
| taisceCuanGitRevision            | Revision for taisce-cuan tasks                                         | Yes      | main                                                             |
| ociStorage                      | OCI storage repository for Trusted Artifacts                              | Yes      | quay.io/konflux-ci/release-service-trusted-artifacts             |
