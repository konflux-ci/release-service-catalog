# create-github-release

Tekton task that creates a release in GitHub.com via the API.

It assumes that a workspace is provided that includes `*.zip`, `*.json` and `*SHA256SUMS` files in
a `release` dir.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| githubSecret | The kubernetes secret to use to authenticate to GitHub | No | - |
| repository | The github repository to release to | No | - |
| release_version | The version string to use creating the release | No | - |
| content_directory | The directory inside the workspace to find files for release | No | - |
