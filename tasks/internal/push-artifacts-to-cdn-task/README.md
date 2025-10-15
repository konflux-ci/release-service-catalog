# push-artifacts-to-cdn-task

Tekton task to push artifacts to the Customer Portal using Pulp and optionally to
the Developer Portal using exodus-rsync with optional signing. It uses logic based
on the snapshot data to determine which targets to publish to: if components contain
both `staged` and `contentGateway` data, artifacts are pushed to the Customer Portal
(Pulp) and to CGW; if components contain `staged` data only, artifacts are
pushed to the Customer Portal (Pulp); if components contain `contentGateway`
data only, artifacts are pushed to the Developer Portal (exodus-rsync) and CGW.

## Parameters

| Name                  | Description                                                                     | Optional | Default value             |
|-----------------------|---------------------------------------------------------------------------------|----------|---------------------------|
| snapshot_json         | String containing a JSON representation of the snapshot spec                    | No       | -                         |
| concurrentLimit       | The maximum number of images to be pulled at once                               | Yes      | 3                         |
| author                | Author taken from Release to be used for checksum signing                       | No       | -                         |
| signingKeyName        | Signing key name to be used for checksum signing                                | No       | -                         |
| quayURL               | Quay URL of the repo where content will be shared between tasks                 | Yes      | quay.io/konflux-artifacts |
| quaySecret            | Secret to interact with Quay                                                    | Yes      | quay-credentials          |
| windowsCredentials    | Secret to interact with the Windows signing host                                | Yes      | windows-credentials       |
| windowsSSHKey         | Secret containing SSH private key for the Windows signing host                  | Yes      | windows-ssh-key           |
| macHostCredentials    | Secret to interact with the Mac signing host                                    | Yes      | mac-host-credentials      |
| macSigningCredentials | Secret to interact with the Mac signing utils                                   | Yes      | mac-signing-credentials   |
| macSSHKey             | Secret containing SSH private key for the Mac signing host                      | Yes      | mac-ssh-key               |
| checksumCredentials   | Secret containing the keytab, user, host, and fingerprint for the checksum host | Yes      | checksum-credentials      |
| kerberosRealm         | Kerberos realm for the checksum host                                            | Yes      | IPA.REDHAT.COM            |
| exodusGwSecret        | Env specific secret containing the Exodus Gateway configs                       | No       | -                         |
| exodusGwEnv           | Environment to use in the Exodus Gateway. Options are [live, pre]               | No       | -                         |
| pulpSecret            | Env specific secret containing the rhsm-pulp credentials                        | No       | -                         |
| udcacheSecret         | Env specific secret containing the udcache credentials                          | No       | -                         |
| cgwHostname           | Env specific hostname for content gateway                                       | No       | -                         |
| cgwSecret             | Env specific secret containing the content gateway credentials                  | No       | -                         |
| caTrustConfigMapName  | The name of the ConfigMap to read CA bundle data from                           | Yes      | trusted-ca                |
| caTrustConfigMapKey   | The name of the key in the ConfigMap that contains the CA bundle data           | Yes      | ca-bundle.crt             |
