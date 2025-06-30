# publish-index-image pipeline

Tekton pipeline to publish a built FBC index image using skopeo

## Parameters

| Name                  | Description                                                                           | Optional | Default value                                             |
|-----------------------|---------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| sourceIndex           | sourceIndex signing image                                                             | No       | -                                                         |
| targetIndex           | targetIndex signing image                                                             | No       | -                                                         |
| retries               | Number of skopeo retries                                                              | Yes      | 0                                                         |
| publishingCredentials | The credentials used to access the registries                                         | No       | -                                                         |
| requestUpdateTimeout  | Max seconds waiting for the status update                                             | Yes      | 360                                                       |
| taskGitUrl            | The url to the git repo where the release-service-catalog tasks to be used are stored | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision       | The revision in the taskGitUrl repo to be used                                        | No       | -                                                         |
