# simple-signing pipeline

Tekton pipeline for simple signing. It is meant to be used by the rh-sign-image task, not as a standalone managed
pipeline.
Signing config (Pyxis URL, UMB settings, secrets, signer type, UMB topics) is read from the signing ConfigMap by
the managed task and passed as pipeline parameters.

## Parameters

| Name                       | Description                                                                                                           | Optional | Default value                                             |
|----------------------------|-----------------------------------------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| manifest_digests           | Space separated manifest digest for the signed content, usually in the format sha256:xxx                              | No       | -                                                         |
| references                 | Space separated docker reference for the signed content, e.g. registry.redhat.io/redhat/community-operator-index:v4.9 | No       | -                                                         |
| requester                  | Name of the user that requested the signing, for auditing purposes                                                    | No       | -                                                         |
| taskGitUrl                 | The url to the git repo where the release-service-catalog tasks to be used are stored                                 | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision            | The revision in the taskGitUrl repo to be used                                                                        | No       | -                                                         |
| signing_key_names          | Space separated list of signing key names to use                                                                      | No       | -                                                         |
| umb_listen_topic           | UMB topic to listen to for signing responses (chosen by caller based on SIGNER_TYPE)                                  | No       | -                                                         |
| umb_publish_topic          | UMB topic to publish to for signing requests (chosen by caller based on SIGNER_TYPE)                                  | No       | -                                                         |
| umb_url                    | UMB host from signing configMap                                                                                       | No       | -                                                         |
| umb_client_name            | UMB client name from signing configMap                                                                                | No       | -                                                         |
| umb_ssl_cert_secret_name   | Kubernetes secret name for UMB SSL (keys cert and key)                                                                | No       | -                                                         |
| pyxis_url                  | Pyxis instance URL from signing configMap                                                                             | No       | -                                                         |
| pyxis_ssl_cert_secret_name | Kubernetes secret name for Pyxis SSL (keys cert and key)                                                              | No       | -                                                         |
| signer_type                | single or batch from signing configMap SIGNER_TYPE                                                                    | No       | -                                                         |
