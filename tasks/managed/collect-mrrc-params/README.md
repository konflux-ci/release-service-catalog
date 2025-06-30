# collect-mrrc-params

Tekton task that collects MRRC(maven.repository.redhat.com) configuration options from
the data file. MRRC is used to host maven artifacts of Red Hat Middleware products.
This task looks at the data file in the workspace to extract the params like
`mrrc.*`, `cosignPubKeySecret` and `charonAWSSecret` keys for MRRC.
`mrrc.*` will be stored in a mrrc.env file and are emitted as task results with
other three for downstream tasks to use.

## Parameters

| Name         | Description                                                        | Optional | Default value |
|--------------|--------------------------------------------------------------------|----------|---------------|
| dataJsonPath | path to data json file                                             | No       | -             |
| snapshotPath | Path to the JSON string of the Snapshot spec in the data workspace | No       | -             |
