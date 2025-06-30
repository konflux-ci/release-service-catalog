# get-advisory-severity pipeline

Tekton pipeline to execute the get-advisory-severity task. The goal of the task is to fetch the proper severity
for an advisory.

## Parameters

| Name               | Description                                                                           | Optional | Default value                                             |
|--------------------|---------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| releaseNotesImages | Json array of image specific details for the advisory                                 | No       | -                                                         |
| taskGitUrl         | The url to the git repo where the release-service-catalog tasks to be used are stored | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision    | The revision in the taskGitUrl repo to be used                                        | No       | -                                                         |
