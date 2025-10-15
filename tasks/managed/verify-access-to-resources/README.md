# verify-access-to-resources

This Tekton task is used to verify access to various resources in the pipelines. It ensures that the necessary
resources, such as the release, release plan, release plan admission, release service config and snapshot,
are available and accessible. Additionally, it checks if internal requests can be created if
`requireInternalServices` is set to `true`.

## Parameters

| Name                    | Description                                                           | Optional | Default value |
|-------------------------|-----------------------------------------------------------------------|----------|---------------|
| release                 | Namespace/name of the Release                                         | No       | -             |
| releasePlan             | Namespace/name of the ReleasePlan                                     | No       | -             |
| releasePlanAdmission    | Namespace/name of the ReleasePlanAdmission                            | No       | -             |
| releaseServiceConfig    | Namespace/name of the ReleaseServiceConfig                            | No       | -             |
| snapshot                | Namespace/name of the Snapshot                                        | No       | -             |
| requireInternalServices | Whether internal services are required                                | Yes      | false         |
| caTrustConfigMapName    | The name of the ConfigMap to read CA bundle data from                 | Yes      | trusted-ca    |
| caTrustConfigMapKey     | The name of the key in the ConfigMap that contains the CA bundle data | Yes      | ca-bundle.crt |
