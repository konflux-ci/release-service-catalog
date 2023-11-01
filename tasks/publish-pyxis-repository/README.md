# publish-pyxis-repository

Tekton task to mark all repositories in the mapped snapshot as published in Pyxis.
This is currently only meant to be used in the rh-push-to-registry-redhat-io pipeline,
so it will convert the values to the ones used for registry.redhat.io releases.
E.g. repository "quay.io/redhat-prod/my-product----my-image" will be converted to use
registry "registry.access.redhat.com" and repository "my-product/my-image" to identify
the right Container Registry object in Pyxis.


## Parameters

| Name         | Description                                                                                       | Optional | Default value      |
|--------------|---------------------------------------------------------------------------------------------------|----------|--------------------|
| server       | The server type to use. Options are 'production' and 'stage'                                      | Yes      | production         |
| pyxisSecret  | The kubernetes secret to use to authenticate to Pyxis. It needs to contain two keys: key and cert | No       | -                  |
| snapshotPath | Path to the JSON string of the mapped Snapshot spec in the data workspace                         | Yes      | snapshot_spec.json |

## Changes since 0.1

* Minor change to logging to provide more context about the pyxis repo request on failure
