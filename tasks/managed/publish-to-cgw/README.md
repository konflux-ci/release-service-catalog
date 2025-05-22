# publish-to-cgw

Tekton task to publish content to Red Hat's Developer portal using content-gateway API.

 - This task _expects_ the content is already pushed to CDN, it _exposes_ the metadata to Developer portal using content-gateway
 - This task is idempotent; it will not push new files if a file with the same label, short URL, and download URL already exists in the product version.

## Parameters

| Name        | Description                                                     | Optional | Default value |
|-------------|-----------------------------------------------------------------|----------|---------------|
| dataPath    | Path to the JSON string of the merged data to use in the data   | No       | -             |
| contentDir  | Path where the content to push is stored in the workspace       | No       | -             |
| cgwHostname | The hostname of the content-gateway to publish the metadata to  | yes      | https://developers.redhat.com/content-gateway/rest/admin |
| cgwSecret   | The kubernetes secret to use to authenticate to content-gateway | yes      | publish-to-cgw-secret |

## Changes in 1.0.0
* Make the task idempotent by checking if files are
  already present in the product name and version.
  * Removal of the 'pubtools-content-gateway' command
    and calling the content-gateway API directly.

## Changes in 0.2.6
* Invoke Content Gateway without password in command

## Changes in 0.2.5
* Support pushes to mirror.openshift.com (ShortUrl)

## Changes in 0.2.4
* Raise Exception correctly when `pubtools-content-gateway` fails
* Create unique shortURL for each product version

## Changes in 0.2.3
* Added logic to handle checksum files
* Fix bug in computing shortUrl

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
