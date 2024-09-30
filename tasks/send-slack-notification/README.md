# send-slack-notification task

Sends message to Slack using postMessage API

## Parameters
| Name            | Description                                                | Optional | Default Value             |
|-----------------|------------------------------------------------------------|----------|---------------------------|
| message         | Message to be sent                                         | No       | -                         |
| tasksStatus     | status of tasks execution                                  | No       | -                         |
| secretName      | Name of secret which contains authentication token for app | No       | -                         |
| secretKeyName   | Name of key within secret which contains webhook URL       | No       | -                         |

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
