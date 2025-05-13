# collect-push-rpm-params

Tekton task to get params for task(push-rpm-to-koji) of pushing konflux build rpms to koji instance.

## Parameters

| Name                 | Description                                                               | Optional | Default value |
|----------------------|---------------------------------------------------------------------------|----------|---------------|
| dataPath             | Path to the JSON file of the merged data to use in the data workspace     | No       | -             |

## Changes in 0.2.0
* Added compute resource limits
