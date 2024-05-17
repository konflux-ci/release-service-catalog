# push-rpm-manifests-to-pyxis

Tekton task that extracts all rpms from the sboms and pushes them to Pyxis as an RPM Manifest.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| pyxisJsonPath | Path to the JSON string of the saved Pyxis data in the data workspace | No | - |
| pyxisSecret | The kubernetes secret to use to authenticate to Pyxis. It needs to contain two keys: key and cert | No | - |
| server | The server type to use. Options are 'production' and 'stage' | Yes | production |
| concurrentLimit | The maximum number of images to be processed at once | Yes | 4 |

## Changes in 0.1.1
* multi-arch images are now properly supported
