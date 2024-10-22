# sign-binaries

Tekton task to sign windows and mac binaries before they are pushed to the Red Hat Developer Portal

If any help is needed with this task, please ping in [#clouddst](https://redhat.enterprise.slack.com/archives/C04QRCD4SQZ) slack channel. 

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| relasePath | Path to the release data JSON file | No | |
| quayUrl | Quay URL of the repo where content will be shared | No |  |
| quaySecret | Secret to interact with Quay | No |  |
| windowsCredentials | Secret to interact with the Windows signing host | No |  |
| windowsSSHKey | Secret containing private key and fingerprint for Windows signing host | Yes | windows-ssh-key |
| macHostCredentials | Secret to interact with the Mac signing host | No |  |
| macSigningCredentials | Secret to interact with the Mac signing utils | No |  |
| macSSHKey | Secret containing SSH private key for the Mac signing host | Yes | mac-ssh-key |
| checksumUser | User to interact with the checksum host | No | |
| checksumHost | Hostname of the checksum host | No | |
| checksumKeytab | Secret containing the keytab for the checksum host | Yes | checksum-keytab |
| checksumFingerprint | Secret containing the fingerprint for the checksum host | Yes | checksum-fingerprint |
| kerberosRealm | Kerberos realm for the checksum host | No | |
| contentDir | Path where the content to push is stored in the workspace | No | |
| pipelineRunUid | Unique ID of the pipelineRun | No |  |


## Changes in 2.1.0
* Added sign-mac-binaries step
* Added push-unsigned-using-oras step
* Added a new task result named 'binaries_path' that can be utilized by subsequent tasks.
* Fix sign-windows-binaries step

## Changes in 2.0.0
* Add checksum signing step

## Changes in 1.0.0
* Added parameters for mac signing steps
