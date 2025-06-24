# prepare-validation

Tekton task to extract a pull spec from a Snapshot.

The purpose of this task is to extract just a single component's pullSpec from a passed Snapshot.

## Parameters

| Name     | Description                                         | Optional | Default value |
|----------|-----------------------------------------------------|----------|---------------|
| snapshot | The Snapshot in JSON format to apply the mapping to | No       | -             |
