# request-and-upload-signature

Task to request and upload signatures using RADAS and pyxis

## Parameters

| Name                 | Description                                                                                           | Optional | Default value                                         |
|----------------------|-------------------------------------------------------------------------------------------------------|----------|-------------------------------------------------------|
| pipeline_image       | An image with CLI tools needed for the signing.                                                       | Yes      | quay.io/redhat-isv/operator-pipelines-images:released |
| manifest_digest      | Manifest digest for the signed content, usually in the format sha256:xxx                              | No       | -                                                     |
| reference            | Docker reference for the signed content, e.g. registry.redhat.io/redhat/community-operator-index:v4.9 | No       | -                                                     |
| requester            | Name of the user that requested the signing, for auditing purposes                                    | No       | -                                                     |
| sig_key_id           | The signing key id that the content is signed with                                                    | Yes      | 4096R/55A34A82 SHA-256                                |
| sig_key_name         | The signing key name that the content is signed with                                                  | Yes      | containerisvsign                                      |
| ssl_cert_secret_name | Kubernetes secret name that contains the umb SSL files                                                | No       | -                                                     |
| ssl_cert_file_name   | The key within the Kubernetes secret that contains the umb SSL cert.                                  | No       | -                                                     |
| ssl_key_file_name    | The key within the Kubernetes secret that contains the umb SSL key.                                   | No       | -                                                     |
| umb_client_name      | Client name to connect to umb, usually a service account name                                         | Yes      | operatorpipelines                                     |
| umb_listen_topic     | umb topic to listen to for responses with signed content                                              | Yes      | VirtualTopic.eng.robosignatory.isv.sign               |
| umb_publish_topic    | umb topic to publish to for requesting signing                                                        | Yes      | VirtualTopic.eng.operatorpipelines.isv.sign           |
| umb_url              | umb host to connect to for messaging                                                                  | Yes      | umb.api.redhat.com                                    |
| pyxis_url            | Pyxis instance to upload the signature to.                                                            | Yes      | https://pyxis.engineering.redhat.com                  |
| signature_data_file  | The file where the signing response should be placed                                                  | Yes      | signing_response.json                                 |
