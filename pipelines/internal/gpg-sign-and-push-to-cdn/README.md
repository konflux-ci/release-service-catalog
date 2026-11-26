# gpg-sign-and-push-to-cdn pipeline

Tekton Pipeline to publish GPG-signed artifacts to CDN and Content Gateway

## Parameters

| Name                               | Description                                                                            | Optional | Default value                                             |
|------------------------------------|----------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| snapshot_json                      | String containing a JSON representation of the snapshot spec                           | No       | -                                                         |
| signed_artifacts_json              | JSON mapping of component name to list of signed Trusted Artifact URIs                 | No       | -                                                         |
| exodusGwSecret                     | Env specific secret containing the Exodus Gateway configs                              | No       | -                                                         |
| exodusGwEnv                        | Environment to use in the Exodus Gateway. Options are [live, pre]                      | No       | -                                                         |
| cgwHostname                        | The hostname of the content-gateway to publish the metadata to                         | Yes      | https://developers.redhat.com/content-gateway/rest/admin  |
| cgwSecret                          | Env specific secret containing the content gateway credentials                         | No       | -                                                         |
| taskGitUrl                         | The url to the git repo where the release-service-catalog tasks to be used are stored  | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision                    | The revision in the taskGitUrl repo to be used                                         | No       | -                                                         |
| trustedArtifactsDockerConfigSecret | The name of the secret that contains dockerconfig json for trusted artifact operations | Yes      | quay-token-konflux-release-trusted-artifacts-secret       |
