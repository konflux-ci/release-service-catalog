# gpg-sign-and-push-to-cdn-task

Tekton task to pull signed binary artifacts and publish them to Exodus CDN
and Content Gateway. Receives signed artifact references from the managed
gpg-sign-and-push-to-cdn task via InternalRequest.

## Parameters

| Name                               | Description                                                                            | Optional | Default value                                       |
|------------------------------------|----------------------------------------------------------------------------------------|----------|-----------------------------------------------------|
| snapshot_json                      | String containing a JSON representation of the snapshot spec                           | No       | -                                                   |
| signed_artifacts_json              | JSON mapping of component name to list of signed Trusted Artifact URIs                 | No       | -                                                   |
| exodusGwSecret                     | Env specific secret containing the Exodus Gateway configs                              | No       | -                                                   |
| exodusGwEnv                        | Environment to use in the Exodus Gateway. Options are [live, pre]                      | No       | -                                                   |
| cgwHostname                        | Env specific hostname for content gateway                                              | No       | -                                                   |
| cgwSecret                          | Env specific secret containing the content gateway credentials                         | No       | -                                                   |
| caTrustConfigMapName               | The name of the ConfigMap to read CA bundle data from                                  | Yes      | trusted-ca                                          |
| caTrustConfigMapKey                | The name of the key in the ConfigMap that contains the CA bundle data                  | Yes      | ca-bundle.crt                                       |
| trustedArtifactsDockerConfigSecret | The name of the secret that contains dockerconfig json for trusted artifact operations | Yes      | quay-token-konflux-release-trusted-artifacts-secret |
