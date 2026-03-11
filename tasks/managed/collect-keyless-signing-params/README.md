# collect-keyless-signing-params

Tekton task to collect Konflux configuration parameters related to
keyless signing using cosign. The task attempts to read the "cluster-config"
ConfigMap in the "konflux-info" namespace to extract signing parameters.

In case the ConfigMap is not found, the task will output empty strings for all parameters,
allowing the pipeline to continue without signing parameters.

## Parameters

| Name                 | Description                                                           | Optional | Default value  |
|----------------------|-----------------------------------------------------------------------|----------|----------------|
| configMapName        | The name of the ConfigMap to read signing parameters from             | Yes      | cluster-config |
| configMapNamespace   | The namespace where the ConfigMap is located                          | Yes      | konflux-info   |
| caTrustConfigMapName | The name of the ConfigMap to read CA bundle data from                 | Yes      | trusted-ca     |
| caTrustConfigMapKey  | The name of the key in the ConfigMap that contains the CA bundle data | Yes      | ca-bundle.crt  |
