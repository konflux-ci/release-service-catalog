# git-clone

Tekton task to clone remote repositories into a Tekton workspace named `output`.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| url | The URL to clone from | No | - |
| revision | Revision to checkout (branch, tag, sha, ref, etc...) | Yes | - |
| subdirectory | Subdirectory inside the `output` Workspace to clone the repo into | Yes | - |
| deleteExisting | Whether to clean out the contents of the destination directory if it already exists before cloning | Yes | "true" |
| verbose | Whether this task script should show verbose output | Yes | "false" |

## Example usage

This is an example usage of the `git-clone` task:

```
---
tasks:
  - name: git-clone
    taskRef:
      name: git-clone
    params:
      - name: url
        value: git@github.com:foo/bar.git
    workspaces:
      - name: output
        workspace: output
```

## Private repositories

To clone private repositories, a service account has to be defined in the PipelineRun/TaskRun with a linked secret allowing to connect to the repository using SSH. More information on this can be found in the [official documentation](https://tekton.dev/docs/pipelines/auth/#configuring-ssh-auth-authentication-for-git).
