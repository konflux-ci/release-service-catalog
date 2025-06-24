# push-artifacts-to-cdn

Tekton Pipeline to push artifacts to CDN and/or Dev Portal

## Parameters

| Name            | Description                                                                            | Optional    | Default value                                              |
|-----------------|----------------------------------------------------------------------------------------|-------------|------------------------------------------------------------|
| snapshot_json   | String containing a JSON representation of the snapshot spec                           | No          | -                                                          |
| author          | Author taken from Release to be used for checksum signing                              | No          | -                                                          |
| signingKeyName  | Signing key name to be used for checksum signing                                       | No          | -                                                          |
| exodusGwSecret  | Env specific secret containing the Exodus Gateway configs                              | No          | -                                                          |
| exodusGwEnv     | Environment to use in the Exodus Gateway. Options are [live, pre]                      | No          | -                                                          |
| pulpSecret      | Env specific secret containing the rhsm-pulp credentials                               | No          | -                                                          |
| udcacheSecret   | Env specific secret containing the udcache credentials                                 | No          | -                                                          |
| cgwHostname     | The hostname of the content-gateway to publish the metadata to                         | Yes         | https://developers.redhat.com/content-gateway/rest/admin   |
| cgwSecret       | Env specific secret containing the content gateway credentials                         | No          | -                                                          |
| taskGitUrl      | The url to the git repo where the release-service-catalog tasks to be used are stored  | Yes         | https://github.com/konflux-ci/release-service-catalog.git  |
| taskGitRevision | The revision in the taskGitUrl repo to be used                                         | No          | -                                                          |
