# filter-already-released-advisory-images-task

Filters out images from a snapshot if they are already published in an advisory
stored in the GitLab advisory repo. Returns a list of component names
that still need to be released (i.e., not found in any advisory).

## Parameters

| Name                           | Description                                                       | Optional | Default value |
|--------------------------------|-------------------------------------------------------------------|----------|---------------|
| snapshot                       | Base64 string of gzipped JSON representation of the snapshot spec | No       | -             |
| origin                         | The origin workspace for the release CR                           | No       | -             |
| advisory_secret_name           | Name of the secret containing advisory metadata                   | No       | -             |
| internalRequestPipelineRunName | Name of the PipelineRun that requested this task                  | No       | -             |
