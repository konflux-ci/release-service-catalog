# send-slack-notification task

Sends message to Slack using postMessage API

## Parameters
| Name                     | Description                                                | Optional | Default Value             |
|--------------------------|------------------------------------------------------------|----------|---------------------------|
| message                  | Message to be sent                                         | No       | -                         |
| tasksStatus              | status of tasks execution                                  | No       | -                         |
| secretName               | Name of secret which contains authentication token for app | No       | -                         |
| secretKeyName            | Name of key within secret which contains webhook URL       | No       | -                         |
| ociStorage               | The OCI repository where the Trusted Artifacts are stored | Yes      | empty                     |
| sourceDataArtifact       | Location of trusted artifacts to be used to populate data directory | Yes | ""               |
| ociArtifactExpiresAfter  | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes | 1d |
| trustedArtifactsDebug    | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable | Yes | ""            |
| orasOptions              | oras options to pass to Trusted Artifacts calls           | Yes      | ""                        |
| dataDir                  | The location where data will be stored                     | Yes      | $(workspaces.data.path)   |
| taskGitUrl               | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored | No | - |
| taskGitRevision          | The revision in the taskGitUrl repo to be used            | No       | -                         |

## Changes in 2.0.0
* Convert task to use trusted artifacts
* Add new parameters: `ociStorage`, `sourceDataArtifact`, `ociArtifactExpiresAfter`, `trustedArtifactsDebug`, `orasOptions`, `dataDir`, `taskGitUrl`, and `taskGitRevision`
* Add new result: `sourceDataArtifact` for trusted artifacts flow
* Add trusted artifacts step actions: `skip-trusted-artifact-operations`, `use-trusted-artifact`, `create-trusted-artifact`, and `patch-source-data-artifact-result`

## Changes in 1.4.0
* Added compute resource limits

## Changes in 1.3.1
* Fix shellcheck/checkton linting issues in the task and tests

## Changes in 1.3.0
* Updated the base image used in this task

## Changes in 1.2.0
* Updated the base image used in this task

## Changes in 1.1.1
* Correct behaviour when secret is not found

## Changes in 1.1.0
* Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead
