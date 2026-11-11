# get-iib-builds-load

Gets the number of in-progress IIB builds submitted by the given user for each given from_index, using
the IIB url from the iib-services-config secret. A from_index whose count can't be fetched is left out
of the loads result.
The task will always exit 0 even if something fails. This is because the task result will not be
set if the task fails, and the task result should always be set and propagated back to the cluster
that creates the internal request. The success/failure is handled in the task creating the internal
request.

## Parameters

| Name        | Description                                                               | Optional | Default value |
|-------------|---------------------------------------------------------------------------|----------|---------------|
| fromIndexes | JSON array of from_index pullspecs to get the in-progress build count for | No       | -             |
| user        | IIB user whose in-progress builds are counted                             | No       | -             |
