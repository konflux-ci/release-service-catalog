# publish-to-mrrc

Tekton task that publishes the maven artifacts to MRRC(maven.repository.redhat.com)
service. MRRC is used to host maven artifacts of Red Hat Middleware products.
This task will work with [collect-mrrc-task](../collect-mrrc-params/README.md)
together to do the MRRC publishment work.
It accepts the `mrrc.env` file from the
[collect-mrrc-task](../collect-mrrc-params/README.md)
and use the variables in it as parameters for the MRRC publishing task.

## Parameters

| Name                 | Description                                          | Optional | Default value |
|----------------------|------------------------------------------------------|----------|---------------|
| mrrcParamFilePath    | path of the env file for mrrc parameters to use      | No       | -             |
| charonConfigFilePath | path of the charon config file for charon to consume | No       | -             |
| charonAWSSecret      | the secret name for charon aws credential file       | No       | -             |
