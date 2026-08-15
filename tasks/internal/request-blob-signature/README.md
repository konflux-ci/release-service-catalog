# request-blob-signature

Tekton task to request a simple signature.
- This task is meant to be used in an internal pipeline that can be triggered frequently
  and is expected to complete as quickly as possible.

## Parameters

| Name                     | Description                                                           | Optional | Default value                                                                     |
|--------------------------|-----------------------------------------------------------------------|----------|-----------------------------------------------------------------------------------|
| pipeline_image           | A docker image of operator-pipeline-images for the steps to run in    | Yes      | quay.io/konflux-ci/release-service-utils:13e379cb498293f8f7b8b9c84c57d9e8ab141be2 |
| requester                | Name of the user that requested the signing, for auditing purposes    | No       | -                                                                                 |
| blob                     | Blob content to be signed, base64 encoded                             | No       | -                                                                                 |
| sig_key_names            | NL separated signing key names that the content is signed with        | Yes      | containerisvsign                                                                  |
| umb_client_name          | Client name to connect to umb, usually a service account name         | Yes      | operatorpipelines                                                                 |
| umb_listen_topic         | umb topic to listen to for responses with signed content              | Yes      | VirtualTopic.eng.robosignatory.isv.sign                                           |
| umb_batch_listen_topic   | batch signer umb topic to listen to for responses with signed content | Yes      | VirtualTopic.eng.robosignatory.konflux.sign                                       |
| umb_publish_topic        | umb topic to publish to for requesting signing                        | Yes      | VirtualTopic.eng.operatorpipelines.isv.sign                                       |
| umb_batch_publish_topic  | batch signer umb topic to publish to for requesting signing           | Yes      | VirtualTopic.eng.hacbs-signing-pipeline.konflux.sign                              |
| umb_url                  | umb host to connect to for messaging                                  | Yes      | umb.api.redhat.com                                                                |
| umb_ssl_cert_secret_name | Kubernetes secret name that contains the umb SSL files                | No       | -                                                                                 |
| signature_data_file      | The file where the signing response should be placed                  | Yes      | signing_response.json                                                             |
| caTrustConfigMapName     | The name of the ConfigMap to read CA bundle data from                 | Yes      | trusted-ca                                                                        |
| caTrustConfigMapKey      | The name of the key in the ConfigMap that contains the CA bundle data | Yes      | ca-bundle.crt                                                                     |
