# create-advisory-oci-artifact pipeline

Pipeline to generate an oci artifact containing an advisory json using an advisory url.

## Parameters

| Name            | Description                                                                           | Optional | Default value                                             |
|-----------------|---------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| advisory_url    | advisory url                                                                          | No       | -                                                         |
| taskGitUrl      | The url to the git repo where the release-service-catalog tasks to be used are stored | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision | The revision in the taskGitUrl repo to be used                                        | No       | -                                                         |
