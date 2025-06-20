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

## Changes in 3.0.0
* This task now supports Trusted artifacts

## Changes in 2.3.0
* Added compute resource limits

## Changes in 2.2.1
* Fix check for existing release
  * The grep was inadequate, because it would also match for substrings. Now we'll
    use github api and check the string directly

## Changes in 2.2.0
* Make task idempotent

## Changes in 2.1.1
* Fixed shellcheck linting issues

## Changes in 2.1.0
* Updated the base image used in this task

## Changes in 2.0.0
* The task now writes created artifacts to a results json file in the workspace

## Changes in 1.1.0
* Updated the base image used in this task

## Changes in 1.0.2
* Added title to the GitHub release creation

## Changes in 1.0.0
* Added the `.sig` files to the release
* Updated test with a `.sig` file

## Changes in 0.2.0
* Removed the installation of the `gh` CLI, since it is now part of the release image
* Changed way to send the results, piping from the `gh` command to make it cleaner

## Changes in 0.1.0
* Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead
