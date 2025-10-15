# pulp-push-disk-images

Tekton task to push disk images with Pulp

## Parameters

| Name                 | Description                                                           | Optional | Default value |
|----------------------|-----------------------------------------------------------------------|----------|---------------|
| snapshot_json        | String containing a JSON representation of the snapshot spec          | No       | -             |
| concurrentLimit      | The maximum number of images to be pulled at once                     | Yes      | 3             |
| exodusGwSecret       | Env specific secret containing the Exodus Gateway configs             | No       | -             |
| exodusGwEnv          | Environment to use in the Exodus Gateway. Options are [live, pre]     | No       | -             |
| pulpSecret           | Env specific secret containing the rhsm-pulp credentials              | No       | -             |
| udcacheSecret        | Env specific secret containing the udcache credentials                | No       | -             |
| cgwHostname          | Env specific hostname for content gateway                             | No       | -             |
| cgwSecret            | Env specific secret containing the content gateway credentials        | No       | -             |
| caTrustConfigMapName | The name of the ConfigMap to read CA bundle data from                 | Yes      | trusted-ca    |
| caTrustConfigMapKey  | The name of the key in the ConfigMap that contains the CA bundle data | Yes      | ca-bundle.crt |
