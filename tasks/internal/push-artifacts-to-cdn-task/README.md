# push-artifacts-to-cdn-task

Tekton task to push artifacts to CDN and optionally Dev Portal with optional signing

## Parameters

| Name            | Description                                                       | Optional | Default value                                            |
|-----------------|-------------------------------------------------------------------|----------|----------------------------------------------------------|
| snapshot_json   | String containing a JSON representation of the snapshot spec      | No       | -                                                        |
| concurrentLimit | The maximum number of images to be pulled at once                 | Yes      | 3                                                        |
| exodusGwSecret  | Env specific secret containing the Exodus Gateway configs         | No       | -                                                        |
| exodusGwEnv     | Environment to use in the Exodus Gateway. Options are [live, pre] | No       | -                                                        |
| pulpSecret      | Env specific secret containing the rhsm-pulp credentials          | No       | -                                                        |
| udcacheSecret   | Env specific secret containing the udcache credentials            | No       | -                                                        |
| cgwHostname     | The hostname of the content-gateway to publish the metadata to    | Yes      | https://developers.redhat.com/content-gateway/rest/admin |
| cgwSecret       | Env specific secret containing the content gateway credentials    | No       | -                                                        |

## Changes in 1.0.0
* Add steps for signing: `push-unsigned-using-oras`, `sign-mac-binaries`, `sign-windows-binaries`, `generate-checksums`
  * The code was copied and adapted from the `sign-binaries` managed task
  * New parameters were added to support signing, many of which have a default which is normally used

## Changes in 0.1.0
* Split out the extracting of the artifacts (via oras pull) to a separate step
