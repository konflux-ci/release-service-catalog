# request-advisory-oci-artifact pipeline

Pipeline to request an oci artifact containing an advisory json using an advisory url.

## Parameters

| Name                | Description                                                                             | Optional | Default value                                               |
|---------------------|-----------------------------------------------------------------------------------------|----------|-------------------------------------------------------------|
| advisory_url        | URL pointing to the advisory                                                            | No       | -                                                           |
| taskGitUrl          | The url to the git repo where the release-service-catalog tasks to be used are stored   | Yes      | https://github.com/konflux-ci/release-service-catalog.git   |
| taskGitRevision     | The revision in the taskGitUrl repo to be used                                          | No       | -                                                           |
