# request-and-upload-signature

Tekton task to request and upload a simple signature.
- This task is meant to be used in an internal pipeline that can be triggered frequently
  and is expected to complete as quickly as possible.

## Parameters

| Name                       | Description                                                                                                                   | Optional | Default value                                                                     |
|----------------------------|-------------------------------------------------------------------------------------------------------------------------------|----------|-----------------------------------------------------------------------------------|
| pipeline_image             | A docker image of operator-pipeline-images for the steps to run in                                                            | Yes      | quay.io/konflux-ci/release-service-utils:82012e03002128f2a226acb23dc5c6fc1c37f5b6 |
| manifest_digests           | List of space separated manifest digests for the signed content, usually in the format sha256:xxx                             | No       | -                                                                                 |
| requester                  | Name of the user that requested the signing, for auditing purposes                                                            | No       | -                                                                                 |
| references                 | List of space separated docker references for the signed content, e.g. registry.com/ns/image:v4.9 registry.com/ns/image:v4.10 | No       | -                                                                                 |
| sig_key_names              | NL separated signing key names that the content is signed with                                                                | Yes      | containerisvsign                                                                  |
| pyxis_ssl_cert_secret_name | Kubernetes secret name that contains the Pyxis SSL files                                                                      | No       | -                                                                                 |
| pyxis_ssl_cert_file_name   | The key within the Kubernetes secret that contains the Pyxis SSL cert                                                         | No       | -                                                                                 |
| pyxis_ssl_key_file_name    | The key within the Kubernetes secret that contains the Pyxis SSL key                                                          | No       | -                                                                                 |
| pyxis_threads              | Number of threads used to upload signatures to pyxis                                                                          | Yes      | 5                                                                                 |
| umb_client_name            | Client name to connect to umb, usually a service account name                                                                 | Yes      | operatorpipelines                                                                 |
| umb_listen_topic           | umb topic to listen to for responses with signed content                                                                      | Yes      | VirtualTopic.eng.robosignatory.isv.sign                                           |
| umb_batch_listen_topic     | batch signer umb topic to listen to for responses with signed content                                                         | Yes      | VirtualTopic.eng.robosignatory.konflux.sign                                       |
| umb_publish_topic          | umb topic to publish to for requesting signing                                                                                | Yes      | VirtualTopic.eng.operatorpipelines.isv.sign                                       |
| umb_batch_publish_topic    | batch signer umb topic to publish to for requesting signing                                                                   | Yes      | VirtualTopic.eng.hacbs-signing-pipeline.konflux.sign                              |
| umb_url                    | umb host to connect to for messaging                                                                                          | Yes      | umb.api.redhat.com                                                                |
| umb_ssl_cert_secret_name   | Kubernetes secret name that contains the umb SSL files                                                                        | No       | -                                                                                 |
| umb_ssl_cert_file_name     | The key within the Kubernetes secret that contains the umb SSL cert                                                           | No       | -                                                                                 |
| umb_ssl_key_file_name      | The key within the Kubernetes secret that contains the umb SSL key                                                            | No       | -                                                                                 |
| pyxis_url                  | Pyxis instance to upload the signature to                                                                                     | Yes      | https://pyxis.engineering.redhat.com                                              |
| signature_data_file        | The file where the signing response should be placed                                                                          | Yes      | signing_response.json                                                             |
| signer_type                | Determines if a single or batch signing should be used                                                                        | Yes      | single                                                                            |
| caTrustConfigMapName       | The name of the ConfigMap to read CA bundle data from                                                                         | Yes      | trusted-ca                                                                        |
| caTrustConfigMapKey        | The name of the key in the ConfigMap that contains the CA bundle data                                                         | Yes      | ca-bundle.crt                                                                     |
