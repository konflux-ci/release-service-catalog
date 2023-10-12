# slack-webhook-notification task

This task sends a message to Slack using incoming webhook

## Parameters
| Name         | Description                                                                                                                     | Optional | Default Value                     |
|--------------|---------------------------------------------------------------------------------------------------------------------------------|----------|-----------------------------------|
| message      | Message to be sent                                                                                                              | false    |                                   |
| secretName   | Name of secret which contains key/value pairs of `<team>/<webhook url>`. e.g. team1=https://hooks.slack.com/services/XXX/XXXXXX | true     | slack-webhook-notification-secret |
| dataJsonPath | Path to data json file. It should contain a key called 'slack-webhook-notification-secret-keyname'                              | true     | $(workspaces.data.path)/data.json |

## Changes since 0.2
- extraDataJsonPath is renamed to dataJsonPath to more closely match the API spec

## Changes since 0.1
- update Tekton API to v1
