# close-advisory-issues

Tekton task to close all issues referenced in the releaseNotes. It is meant to run after the advisory is published.
A comment will be added to each closed issue with a link to the advisory it was fixed in.

Note: This task currently only supports issues in issues.redhat.com due to it requiring authentication.
Issues in other servers will be skipped without the task failing.

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value           |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|-------------------------|
| dataPath                | Path to data JSON in the data workspace                                                                                    | No       | -                       |
| advisoryUrl             | The url of the advisory the issues were fixed in. This is added in a comment on the issue                                  | No       | -                       |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                   |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                      |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                      |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                      |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                      |
| dataDir                 | The location where data will be stored                                                                                     | Yes      | $(workspaces.data.path) |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | ""                      |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | No       | ""                      |

## Changes in 1.1.0
* Added compute resource limits

## Changes in 1.0.1
* Bump the utils image to allow 201 and other 2xx codes in `curl-with-retry` script

## Changes in 1.0.0
* This task now supports Trusted artifacts

## Changes in 0.1.1
* Deal with Jira API rate limiting using a new `curl-with-retry` script from utils image
  * Bump the utils image to a version containing the new script
