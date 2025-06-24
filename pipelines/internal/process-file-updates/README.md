# process-file-updates

Tekton Pipeline to update files in Git repositories. It is possible to seed a file with initial content and/or apply
replacements to a yaml file that already exists. It will attempt to create a Merge Request in Gitlab.

## Parameters

| Name                | Description                                                                                                                                                                              | Optional | Default value                                             |
|---------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| upstream_repo       | Upstream Git repository                                                                                                                                                                  | No       | -                                                         |
| repo                | Git repository                                                                                                                                                                           | No       | -                                                         |
| ref                 | Git branch                                                                                                                                                                               | No       | -                                                         |
| paths               | String containing a JSON array of file paths and its updates and/or replacements E.g. '[{"path":"file1.yaml","replacements":[{"key":".yamlkey1,","replacement":"\|regex\|replace\|"}]}]' | No       | -                                                         |
| application         | Application being released                                                                                                                                                               | No       | -                                                         |
| file_updates_secret | The credentials used to update the git repo                                                                                                                                              | Yes      | file-updates-secret                                       |
| taskGitUrl          | The url to the git repo where the release-service-catalog tasks to be used are stored                                                                                                    | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision     | The revision in the taskGitUrl repo to be used                                                                                                                                           | No       | -                                                         |
