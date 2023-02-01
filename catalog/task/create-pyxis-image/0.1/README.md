# create-pyxis-image

Tekton task that executes a python script to push a container image's metadata to Pyxis.
The task expects a workspace to be mounted containing a file with the `skopeo inspect` output of the
container that will have its metadata uploaded to Pyxis.

The ID of the created `containerImage` is stored as a task result.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| server | The server type to use. Options are 'production' and 'stage' | No | production |
| pyxisSecret | The kubernetes secret to use to authenticate to Pyxis | No | - |
| certified | If set to true, the image will be marked as certified in its Pyxis entry | No | false |
| tag | The tag to use when pushing the container image metadata to Pyxis | No | - |
| isLatest | If set to true, the image will have a latest tag added with its pyxis entry | No | false |
| skopeoInspectFile | The filename of the saved skopeo inspect output stored on the input workspace | No | skopeo-inspect.json |
