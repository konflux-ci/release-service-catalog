# prepare-validation

Tekton task to extract a pull spec from a Snapshot.

The purpose of this task is to extract just a single component's pullSpec from a passed Snapshot.

## Parameters

| Name                 | Description                                                           | Optional | Default value |
|----------------------|-----------------------------------------------------------------------|----------|---------------|
| snapshot             | The Snapshot in JSON format to apply the mapping to                   | No       | -             |
| caTrustConfigMapName | The name of the ConfigMap to read CA bundle data from                 | Yes      | trusted-ca    |
| caTrustConfigMapKey  | The name of the key in the ConfigMap that contains the CA bundle data | Yes      | ca-bundle.crt |
