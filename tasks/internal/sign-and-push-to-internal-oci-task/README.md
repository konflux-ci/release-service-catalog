# sign-and-push-to-internal-oci-task

Extract artifacts from a snapshot, push unsigned content to a source Quay repository, then sign Mac and Windows binaries on remote VMs via SSH. Signed artifacts are pushed to a configurable destination Quay repository

## Parameters

| Name                  | Description                                                           | Optional | Default value             |
|-----------------------|-----------------------------------------------------------------------|----------|---------------------------|
| snapshot_json         | String containing a JSON representation of the snapshot spec          | No       | -                         |
| concurrentLimit       | The maximum number of images to be pulled at once                     | Yes      | 3                         |
| quayURL               | Quay URL of the repo where unsigned content is shared between tasks   | Yes      | quay.io/konflux-artifacts |
| destQuayURL           | Destination Quay URL where signed artifacts will be pushed            | Yes      | ""                        |
| origin                | Origin tenant namespace that triggered the release                    | No       | -                         |
| quaySecret            | Secret to interact with the source Quay repository                    | Yes      | quay-credentials          |
| destQuaySecret        | Secret to interact with the destination Quay repository               | Yes      | quay-credentials          |
| windowsCredentials    | Secret to interact with the Windows signing host                      | Yes      | windows-credentials       |
| windowsSSHKey         | Secret containing SSH private key for the Windows signing host        | Yes      | windows-ssh-key           |
| macHostCredentials    | Secret to interact with the Mac signing host                          | Yes      | mac-host-credentials      |
| macSigningCredentials | Secret to interact with the Mac signing utils                         | Yes      | mac-signing-credentials   |
| macSSHKey             | Secret containing SSH private key for the Mac signing host            | Yes      | mac-ssh-key               |
| macSigningScript      | Path to the macOS signing script on the remote host                   | Yes      | ""                        |
| windowsSigningScript  | Path to the Windows signing script on the remote host                 | Yes      | ""                        |
| caTrustConfigMapName  | The name of the ConfigMap to read CA bundle data from                 | Yes      | trusted-ca                |
| caTrustConfigMapKey   | The name of the key in the ConfigMap that contains the CA bundle data | Yes      | ca-bundle.crt             |
