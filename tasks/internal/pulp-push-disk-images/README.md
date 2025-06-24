# pulp-push-disk-images

Tekton task to push disk images with Pulp

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
