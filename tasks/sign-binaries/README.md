# sign-binaries

Tekton task to sign windows and mac binaries before they are pushed to the Red Hat Developer Portal

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| quayUrl | Quay URL of the repo where content will be shared | No |  |
| quaySecret | Secret to interact with Quay | No |  |
| windowsCredentials | Secret to interact with the Windows signing host | No |  |
| windowsSSHKey | Secret containing private key and fingerprint for Windows signing host | Yes | windows-ssh-key |
| macHostCredentials | Secret to interact with the Mac signing host | No |  |
| macSigningCredentials | Secret to interact with the Mac signing utils | No |  |
| macSSHKey | Secret containing SSH private key for the Mac signing host | Yes | mac-ssh-key |
| pipelineRunUid | Unique ID of the pipelineRun | No |  |


## Changes in 1.0.0
* Added parameters for mac signing steps
