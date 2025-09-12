# check-fbc-opt-in

Simple task to check FBC opt-in status in Pyxis for container images.
Returns opt-in status for each provided container image.

## Parameters

| Name            | Description                                                                        | Optional | Default value |
|-----------------|------------------------------------------------------------------------------------|----------|---------------|
| containerImages | JSON array of container images to check for FBC opt-in status                      | No       | -             |
| pyxisSecret     | Name of secret which contains the required credentials for authentication to pyxis | No       | -             |
| pyxisServer     | Pyxis server to use                                                                | Yes      | production    |
