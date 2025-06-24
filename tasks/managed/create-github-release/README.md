# create-github-release

Tekton task that creates a release in GitHub.com via the API.

It assumes that a workspace is provided that includes `*.zip`, `*.json` and `*SHA256SUMS` files in
a `release` dir.

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value           |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|-------------------------|
| githubSecret            | The kubernetes secret to use to authenticate to GitHub                                                                     | No       | -                       |
| repository              | The github repository to release to                                                                                        | No       | -                       |
| release_version         | The version string to use creating the release                                                                             | No       | -                       |
| content_directory       | The directory inside the workspace to find files for release                                                               | No       | -                       |
| resultsDirPath          | Path to results directory in the data workspace                                                                            | No       | -                       |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                   |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                      |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                      |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                      |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                      |
| dataDir                 | The location where data will be stored                                                                                     | Yes      | $(workspaces.data.path) |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | ""                      |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | No       | ""                      |
