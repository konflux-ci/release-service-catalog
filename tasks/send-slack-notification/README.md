# send-slack-notification task

Sends message to Slack using postMessage API

## Parameters
| Name            | Description                                                | Optional | Default Value             |
|-----------------|------------------------------------------------------------|----------|---------------------------|
| message         | Message to be sent                                         | No       |                           |
| tasksStatus     | status of tasks execution                                  | No       |                           |
| secretName      | Name of secret which contains authentication token for app | Yes      | slack-notification-secret |
| secretKeyName   | Name of key within secret which contains webhook URL       | No       |                           |
