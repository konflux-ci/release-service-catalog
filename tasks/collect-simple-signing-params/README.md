# collect-simple-signing-params

Task to collect parameters for the simple signing pipeline

## Parameters

| Name             | Description                                                                           | Optional | Default value                                          |
|------------------|---------------------------------------------------------------------------------------|----------|--------------------------------------------------------|
| pipeline_image   | An image of operator-pipeline-images for the steps to run in.                         | Yes      | quay.io/redhat-isv/operator-pipelines-images:released  |
| config_map_name  | Name of a configmap with pipeline configuration                                       | No       | -                                                      |
