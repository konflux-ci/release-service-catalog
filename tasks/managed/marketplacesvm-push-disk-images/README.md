# marketplacesvm-push-disk-images

Tekton Task to publish VM disk images into various cloud marketplaces using `pubtools-marketplacesvm`.

It currently supports images in `raw` and `vhd` formats for `AWS` and `Azure` respectively.

## Parameters

| Name                    | Description                                                                            | Optional | Default value   |
| ----------------------- | -------------------------------------------------------------------------------------- | -------- | --------------- |
| snapshotPath            | Path to the JSON string of the mapped snapshot spec in the data workspace.             | No       | -               |
| cloudMarketplacesSecret | Env specific secret containing the marketplaces credentials.                           | No       | -               |
| prePush                 | Whether perform a pre-push (true) or not (false). When true it will not publish PROD.  | Yes      | false           |
| concurrentLimit         | The maximum number of images to be pulled at once.                                     | Yes      | 3               |
