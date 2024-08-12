# slack-webhook-notification task

This task sends a message to Slack using incoming webhook

## Parameters
| Name         | Description                                                                                                                     | Optional | Default Value                     |
|--------------|---------------------------------------------------------------------------------------------------------------------------------|----------|-----------------------------------|
| message      | Message to be sent                                                                                                              | false    | -                                 |
| secretName   | Name of secret which contains key/value pairs of `<team>/<webhook url>`. e.g. team1=https://hooks.slack.com/services/XXX/XXXXXX | true     | slack-webhook-notification-secret |
| dataJsonPath | Path to data json file. It should contain a key called 'slack-webhook-notification-secret-keyname'                              | false    | -                                 |

## Changes in 0.7.0
* Updated the base image used in this task

## Changes in 0.6.0
* Updated the base image used in this task

## Changes in 0.5.0
* remove `dataJsonPath` default value

## Changes in 0.3.0
* Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead

## Changes in 0.2
* extraDataJsonPath is renamed to dataJsonPath to more closely match the API spec

## Changes in 0.1
* update Tekton API to v1
