# collect-simple-signing-params

Task to collect parameters for the simple signing pipeline

## Parameters

| Name             | Description                                                                           | Optional | Default value                                          |
|------------------|---------------------------------------------------------------------------------------|----------|--------------------------------------------------------|
| config_map_name  | Name of a configmap with pipeline configuration                                       | No       | -                                                      |

## Changes in 0.4.0
* Added compute resource limits

## Changes in 0.3.0
* Removed the `ssl_cert_secret_name`, `ssl_cert_file_name`, and `ssl_key_file_name` results
  * The results added in 0.2.0 take their places

## Changes in 0.2.0
* Added the `[pyxis,umb]_ssl_cert_file_name`, `[pyxis,umb]_ssl_cert_secret_name` and `[pyxis,umb]_ssl_key_file_name`
  results
  * These keys now exist in the configMaps used in this task
  * They were added to break apart Pyxis and UMB credentials
  * They take the place of `ssl_cert_file_name`, `ssl_cert_secret_name` and `ssl_key_file_name` respectively, but
    the old parameters can not be removed yet as the `simple-signing-pipeline` used in E2E will be the one on the stage
    cluster, not the one from this PR. So, because the current `simple-signing-pipeline` relies on these results, they
    have to wait for the next PR to be removed
