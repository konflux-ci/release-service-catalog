# reduce-snapshot

Tekton task to reduce a snapshot to a single component based on the component that the snapshot was built for.

## Parameters

| Name                                | Description                                              | Optional | Default value |
|-------------------------------------|----------------------------------------------------------|----------|---------------|
| SNAPSHOT                            | String representation of Snapshot spec                   | No       | -             |
| SINGLE_COMPONENT                    | Single mode component enabled                            | No       | -             |
| SINGLE_COMPONENT_CUSTOM_RESOURCE    | Custom Resource to query for built component in Snapshot | No       | -             |
| SINGLE_COMPONENT_CUSTOM_RESOURCE_NS | Namespace where Custom Resource is found                 | No       | -             |
| SNAPSHOT_PATH                       | The location to place the reduced Snapshot               | No       | -             |
