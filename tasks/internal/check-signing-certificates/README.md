# check-signing-certificates

Tekton task to verify the expiration of signing certificates (UMB and Pyxis)

## Parameters

| Name                       | Description                                                           | Optional | Default value |
|----------------------------|-----------------------------------------------------------------------|----------|---------------|
| umb_ssl_cert_secret_name   | Kubernetes secret name for UMB                                        | No       | -             |
| umb_ssl_cert_file_name     | The name of the file with the UMB certificate in the secret           | No       | -             |
| pyxis_ssl_cert_secret_name | Kubernetes secret name for Pyxis                                      | No       | -             |
| pyxis_ssl_cert_file_name   | The name of the file with the Pyxis certificate in the secret         | No       | -             |
| certExpirationWarnDays     | Number of days before expiration to warn about certificate expiration | Yes      | 7             |
| sendSlackNotification      | Whether to send Slack notifications for certificate expiration alerts | Yes      | true          |
| slackWebhookUrl            | Override default Slack webhook URL for notifications (optional)       | Yes      | ""            |
