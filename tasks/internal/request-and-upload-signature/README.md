# request-and-upload-signature

Tekton task to request and upload a simple signature.
- This task is meant to be used in an internal pipeline that can be triggered frequently
  and is expected to complete as quickly as possible.

## Parameters

| Name                       | Description                                                                                                                   | Optional | Default value                        |
|----------------------------|-------------------------------------------------------------------------------------------------------------------------------|----------|--------------------------------------|
| manifest_digests           | List of space separated manifest digests for the signed content, usually in the format sha256:xxx                             | No       | -                                    |
| requester                  | Name of the user that requested the signing, for auditing purposes                                                            | No       | -                                    |
| references                 | List of space separated docker references for the signed content, e.g. registry.com/ns/image:v4.9 registry.com/ns/image:v4.10 | No       | -                                    |
| sig_key_names              | Space separated signing key names that the content is signed with                                                             | No       | -                                    |
| pyxis_ssl_cert_secret_name | Kubernetes secret name that contains the Pyxis SSL files (keys cert and key)                                                  | No       | -                                    |
| pyxis_threads              | Number of threads used to upload signatures to pyxis                                                                          | Yes      | 5                                    |
| umb_client_name            | Client name to connect to umb, usually a service account name                                                                 | No       | -                                    |
| umb_listen_topic           | UMB listen topic (caller passes batch or single based on SIGNER_TYPE)                                                         | No       | -                                    |
| umb_publish_topic          | UMB publish topic (caller passes batch or single based on SIGNER_TYPE)                                                        | No       | -                                    |
| umb_url                    | umb host to connect to for messaging                                                                                          | Yes      | umb.api.redhat.com                   |
| umb_ssl_cert_secret_name   | Kubernetes secret name that contains the UMB SSL files (keys cert and key)                                                    | No       | -                                    |
| pyxis_url                  | Pyxis instance to upload the signature to                                                                                     | Yes      | https://pyxis.engineering.redhat.com |
| signature_data_file        | The file where the signing response should be placed                                                                          | Yes      | signing_response.json                |
| signer_type                | Determines if a single or batch signing should be used                                                                        | Yes      | single                               |
| caTrustConfigMapName       | The name of the ConfigMap to read CA bundle data from                                                                         | Yes      | trusted-ca                           |
| caTrustConfigMapKey        | The name of the key in the ConfigMap that contains the CA bundle data                                                         | Yes      | ca-bundle.crt                        |
