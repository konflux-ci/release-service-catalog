# exchange-service-account-token

Tekton task to exchange a Kubernetes service account token for an ACS (Advanced Cluster Security)
authentication token using machine-to-machine (M2M) authentication. The resulting roxctl configuration
is stored in the workspace for use by downstream tasks.

## Parameters

| Name                  | Description                                                           | Optional | Default value                                                                                                                           |
|-----------------------|-----------------------------------------------------------------------|----------|-----------------------------------------------------------------------------------------------------------------------------------------|
| roxImage              | Image providing the roxctl tool                                       | Yes      | registry.redhat.io/advanced-cluster-security/rhacs-roxctl-rhel8@sha256:d6d5e50d1deda1e7b232d4e3f60fda6f3d27266b6fc007c8ec48a324e1c6c15c |
| roxCentralEndpoint    | The address:port tuple for RHACS Stackrox Central                     | Yes      | https://acs-d4dgfbkto15c73biblcg.acs.rhcloud.com                                                                                        |
| insecureSkipTlsVerify | Do not verify TLS certificates when set to "true"                     | Yes      | false                                                                                                                                   |
| roxConfigDir          | The relative path in the workspace to store the roxctl configuration  | No       | -                                                                                                                                       |
| caTrustConfigMapName  | The name of the ConfigMap to read CA bundle data from                 | Yes      | trusted-ca                                                                                                                              |
| caTrustConfigMapKey   | The name of the key in the ConfigMap that contains the CA bundle data | Yes      | ca-bundle.crt                                                                                                                           |
