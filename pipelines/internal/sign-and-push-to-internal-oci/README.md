# sign-and-push-to-internal-oci pipeline

Internal pipeline wrapper for the sign-and-push-to-internal-oci task.
Dispatched via InternalRequest from the managed pipeline.

## Parameters

| Name                 | Description                                                                           | Optional | Default value                                             |
|----------------------|---------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| snapshot_json        | String containing a JSON representation of the snapshot spec                          | No       | -                                                         |
| concurrentLimit      | The maximum number of images to be pulled at once                                     | Yes      | 3                                                         |
| author               | Author taken from Release to be used for checksum signing                             | No       | -                                                         |
| signingKeyName       | Signing key name to be used for checksum signing                                      | No       | -                                                         |
| quayURL              | Quay URL of the repo where unsigned content is shared between tasks                   | Yes      | quay.io/konflux-artifacts                                 |
| destQuayURL          | Destination Quay URL where signed artifacts will be pushed                            | Yes      | ""                                                        |
| quaySecret           | Secret to interact with the source Quay repository                                    | Yes      | quay-credentials                                          |
| destQuaySecret       | Secret to interact with the destination Quay repository                               | Yes      | quay-credentials                                          |
| origin               | Origin tenant namespace that triggered the release                                    | No       | -                                                         |
| macSigningScript     | Path to the macOS signing script on the remote host                                   | Yes      | ""                                                        |
| windowsSigningScript | Path to the Windows signing script on the remote host                                 | Yes      | ""                                                        |
| taskGitUrl           | The url to the git repo where the release-service-catalog tasks to be used are stored | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision      | The revision in the taskGitUrl repo to be used                                        | No       | -                                                         |
