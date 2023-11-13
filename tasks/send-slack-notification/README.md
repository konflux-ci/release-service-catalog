# send-slack-notification task

Sends message to Slack using postMessage API

## Parameters
| Name         | Description                                                 | Optional | Default Value              |
|--------------|-------------------------------------------------------------|----------|----------------------------|
| message      | Message to be sent                                          | false    |                            |
| tasksStatus  | status of tasks execution                                   | false    |                            |
| secretName   | Name of secret which contains authentication token for app  | true     | slack-notification-secret  |
