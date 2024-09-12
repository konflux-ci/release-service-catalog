# sign-binaries

Tekton task to sign windows and mac binaries before they are pushed to the Red Hat Developer Portal

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| quayUrl | Quay URL of the repo where content will be shared | No |  |
| quaySecret | Secret to interact with Quay | No |  |
| windowsCredentials | Secret to interact with the Windows signing host | No |  |
| windowsSSHKey | Secret containing private key and fingerprint for Windows signing host | Yes | windows-ssh-key |
| pipelineRunUid | Unique ID of the pipelineRun | No |  |
