# publish-index-image-task

Tekton task to publish a built FBC index image using skopeo

## Parameters

| Name                  | Description                                                           | Optional | Default value              |
|-----------------------|-----------------------------------------------------------------------|----------|----------------------------|
| sourceIndex           | sourceIndex signing image                                             | No       | -                          |
| targetIndex           | targetIndex signing image                                             | No       | -                          |
| retries               | Number of skopeo retries                                              | Yes      | 0                          |
| publishingCredentials | The credentials used to access the registries                         | Yes      | fbc-publishing-credentials |
| requestUpdateTimeout  | Max seconds waiting for the status update                             | Yes      | 360                        |
| caTrustConfigMapName  | The name of the ConfigMap to read CA bundle data from                 | Yes      | trusted-ca                 |
| caTrustConfigMapKey   | The name of the key in the ConfigMap that contains the CA bundle data | Yes      | ca-bundle.crt              |
