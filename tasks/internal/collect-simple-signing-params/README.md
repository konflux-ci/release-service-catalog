# collect-simple-signing-params

Task to collect parameters for the simple signing pipeline

## Parameters

| Name                 | Description                                                           | Optional | Default value |
|----------------------|-----------------------------------------------------------------------|----------|---------------|
| config_map_name      | Name of a configmap with pipeline configuration                       | No       | -             |
| caTrustConfigMapName | The name of the ConfigMap to read CA bundle data from                 | Yes      | trusted-ca    |
| caTrustConfigMapKey  | The name of the key in the ConfigMap that contains the CA bundle data | Yes      | ca-bundle.crt |
