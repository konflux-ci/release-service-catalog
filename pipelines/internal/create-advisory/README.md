# create-advisory pipeline

Tekton pipeline to execute the create-advisory task. The task clones the advisory repo, gets an ID for the advisory,
generates an advisory, then pushes it if the generated advisory is valid. The pipeline returns a result with the
advisory URL as well as a result to show the error message if one occurred.

## Parameters

| Name                 | Description                                                                                            | Optional | Default value                                             |
|----------------------|--------------------------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| advisory_json        | String containing a JSON representation of the advisory data (e.g. '{"product_id":123,"type":"RHSA"}') | No       | -                                                         |
| application          | Application being released                                                                             | No       | -                                                         |
| origin               | The origin workspace where the release CR comes from. This is used to determine the advisory path      | No       | -                                                         |
| config_map_name      | The name of the configMap that contains the signing key                                                | No       | -                                                         |
| contentType          | The contentType of the release artifact. One of [image|binary|generic]                                 | Yes      | image                                                     |
| advisory_secret_name | The name of the secret that contains the advisory creation metadata                                    | No       | -                                                         |
| errata_secret_name   | The name of the secret that contains the errata service account metadata                               | No       | -                                                         |
| taskGitUrl           | The url to the git repo where the release-service-catalog tasks to be used are stored                  | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision      | The revision in the taskGitUrl repo to be used                                                         | No       | -                                                         |
