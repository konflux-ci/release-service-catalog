# publish-to-cgw

Tekton task to publish content to Red Hat's Developer portal using pubtools-content-gateway

 - This task _expects_ the content is already push to CDN, it _exposes_ the metadata to Developer portal using content-gateway 
 - This task uses [pubtools-content-gateway](https://github.com/release-engineering/pubtools-content-gateway) to publish content to content-gateway.



## Parameters

| Name        | Description                                                     | Optional | Default value |
|-------------|-----------------------------------------------------------------|----------|---------------|
| dataPath    | Path to the JSON string of the merged data to use in the data   | No       | -             |
| contentDir  | Path where the content to push is stored in the workspace       | No       | -             |
| cgwHostname | The hostname of the content-gateway to publish the metadata to  | yes      | https://developers.redhat.com/content-gateway/rest/admin |
| cgwSecret   | The kubernetes secret to use to authenticate to content-gateway | yes      | publish-to-cgw-secret |

## Changes in 0.2.2
* Update the base image used in this task to provide jsonschema module

## Changes in 0.2.1
* Update cgw_metadata file creation
  * update downloadURL prefix
  * update shortURL
  * remove filename
* Report better result output

## Changes in 0.2.0
* Updated the base image used in this task
