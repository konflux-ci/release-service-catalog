# push-artifacts-to-cdn-task

Tekton task to push artifacts to CDN and optionally Dev Portal with optional signing

## Parameters

| Name                  | Description                                                           | Optional | Default value                                            |
|-----------------------|-----------------------------------------------------------------------|----------|----------------------------------------------------------|
| snapshot_json         | String containing a JSON representation of the snapshot spec          | No       | -                                                        |
| concurrentLimit       | The maximum number of images to be pulled at once                     | Yes      | 3                                                        |
| author                | Author taken from Release to be used for checksum signing             | No       | -                                                        |
| signingKeyName        | Signing key name to be used for checksum signing                      | No       | -                                                        |
| quayUrl               | quay URL of the repo where content will be shared                     | Yes      | quay.io/konflux-artifacts                                |
| quaySecret            | Secret to interact with Quay                                          | Yes      | quay-credentials                                         |
| windowsCredentials    | Secret to interact with the Windows signing host                      | Yes      | windows-credentials                                      |
| windowsSSHKey         | Secret containing SSH private key for the Windows signing host        | Yes      | windows-ssh-key                                          |
| macHostCredentials    | Secret to interact with the Mac signing host                          | Yes      | mac-host-credentials                                     |
| macSigningCredentials | Secret to interact with the Mac signing utils                         | Yes      | mac-signing-credentials                                  |
| macSSHKey             | Secret containing SSH private key for the Mac signing host            | Yes      | mac-ssh-key                                              |
| checksumUser          | User to interact with the checksum host                               | Yes      | konflux-release-signing-sa                               |
| checksumHost          | Hostname of the checksum host                                         | Yes      | etera-worker.hosted.upshift.rdu2.redhat.com              |
| checksumFingerprint   | Secret containing the fingerprint for the checksum host               | Yes      | checksum-fingerprint                                     |
| checksumKeytab        | Secret containing the keytab for the checksum host                    | Yes      | checksum-keytab                                          |
| kerberosRealm         | Kerberos realm for the checksum host                                  | Yes      | IPA.REDHAT.COM                                           |
| exodusGwSecret        | Env specific secret containing the Exodus Gateway configs             | No       | -                                                        |
| exodusGwEnv           | Environment to use in the Exodus Gateway. Options are [live, pre]     | No       | -                                                        |
| pulpSecret            | Env specific secret containing the rhsm-pulp credentials              | No       | -                                                        |
| udcacheSecret         | Env specific secret containing the udcache credentials                | No       | -                                                        |
| cgwHostname           | The hostname of the content-gateway to publish the metadata to        | Yes      | https://developers.redhat.com/content-gateway/rest/admin |
| cgwSecret             | Env specific secret containing the content gateway credentials        | No       | -                                                        |

## Changes in 2.2.0
* Update Pulp push logic to be controlled by `staged.destination`.
* When `staged.destination` is present in any component, the task will push to Pulp.
* When `staged.destination` is not present, the task will skip the Pulp push step.

## Changes in 2.1.0
* Added compute resource limits

## Changes in 2.0.0
* Add new required parameter `signingKeyName`. This is used for checksum signing

## Changes in 1.0.1
* Base64 decode keytab used for interacting with the checksum signing host (ETERA)

## Changes in 1.0.0
* Add steps for signing: `push-unsigned-using-oras`, `sign-mac-binaries`, `sign-windows-binaries`, `generate-checksums`
  * The code was copied and adapted from the `sign-binaries` managed task
  * New parameters were added to support signing, many of which have a default which is normally used

## Changes in 0.1.0
* Split out the extracting of the artifacts (via oras pull) to a separate step
