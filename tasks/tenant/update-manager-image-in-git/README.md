# update-manager-image-in-git

Updates the image line in the manager yaml files in the internal-services/manager directory.
If mode is `pr`, a pull request is created for the update. If mode is `push`, the change is pushed
directly.

## Parameters

| Name         | Description                                                                                   | Optional | Default value                                          |
|--------------|-----------------------------------------------------------------------------------------------|----------|--------------------------------------------------------|
| mode         | Whether the task should create a pull request or directly push. Options are [pr, push]        | No       | -                                                      |
| repoBranch   | The branch in the repo to target                                                              | Yes      | main                                                   |
| repoUrl      | The repo to update, starting with github.com, without https:// (e.g. github.com/org/repo.git) | Yes      | github.com/hacbs/release/app-interface-deployments.git |
| githubSecret | The secret containing a `token` key with value set to the GitHub access token                 | No       | -                                                      |
| image        | The manager image to update to                                                                | No       | -                                                      |
