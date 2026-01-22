# publish-to-nrrc

Tekton task that publishes the npm archives to NRRC(npm.registry.redhat.com)
service. NRRC is used to host npm artifacts of Red Hat products.
This task will work with [collect-charon-task](../collect-charon-params/README.md)
together to do the NRRC publishment work.
It accepts the `charon.env` file from the
[collect-charon-task](../collect-charon-params/README.md)
and use the variables in it as parameters for the NRRC publishing task.

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value        |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|----------------------|
| caTrustConfigMapName    | The name of the ConfigMap to read CA bundle data from                                                                      | Yes      | trusted-ca           |
| caTrustConfigMapKey     | The name of the key in the ConfigMap that contains the CA bundle data                                                      | Yes      | ca-bundle.crt        |
| charonParamFilePath     | path of the env file for nrrc parameters to use                                                                            | No       | -                    |
| charonConfigFilePath    | path of the charon config file for charon to consume                                                                       | No       | -                    |
| charonAWSSecret         | the secret name for charon aws credential file                                                                             | No       | -                    |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                   |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                   |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                   |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                   |
| dataDir                 | The location where data will be stored                                                                                     | Yes      | /var/workdir/release |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | -                    |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | No       | -                    |
