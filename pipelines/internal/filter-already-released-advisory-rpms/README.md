# filter-already-released-advisory-rpms pipeline

This pipeline filters out RPMs from a snapshot that have already been published in advisories.
It returns lists of unreleased RPMs and RPMs found in advisories for digest validation.

## Parameters

| Name                           | Description                                                                           | Optional | Default value                                             |
|--------------------------------|---------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| transformedSnapshot            | Base64 string of gzipped JSON array of RPM entries with purls                         | No       | -                                                         |
| origin                         | The origin workspace where the release CR comes from                                  | No       | -                                                         |
| advisory_secret_name           | The name of the secret that contains the advisory GitLab metadata                     | No       | -                                                         |
| internalRequestPipelineRunName | Name of the PipelineRun that requested this pipeline                                  | No       | -                                                         |
| ociStorage                     | The OCI repository to store results artifact                                          | No       | -                                                         |
| taskGitUrl                     | The url to the git repo where the release-service-catalog tasks to be used are stored | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision                | The revision in the taskGitUrl repo to be used                                        | No       | -                                                         |
| orasOptions                    | oras options to pass to oras calls                                                    | Yes      | ""                                                        |
