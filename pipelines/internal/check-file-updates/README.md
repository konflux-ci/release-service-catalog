# check-file-updates pipeline

Internal pipeline to check whether fileUpdates changes are already complete for
a given componentGroup and GitLab repository.

This is intended to be triggered via InternalRequest from managed release tasks.

## Parameters

| Name                | Description                                                                           | Optional | Default value                                             |
|---------------------|---------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| upstream_repo       | Git repository (GitLab) where fileUpdates merge requests are created                  | No       | -                                                         |
| componentGroup      | Component group being released (used to identify Konflux fileUpdates MRs)             | No       | -                                                         |
| file_updates_secret | Secret containing GitLab host/access token used by internal services                  | Yes      | file-updates-secret                                       |
| taskGitUrl          | The url to the git repo where the release-service-catalog tasks to be used are stored | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision     | The revision in the taskGitUrl repo to be used                                        | No       | -                                                         |
