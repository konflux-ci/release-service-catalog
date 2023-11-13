# check-data-keys

Tekton task to check that all required information is present in the data file in order to make a
call to the specified system(s). If any required keys are missing, the task will fail.

For example, if `advisory` is passed as a system and the data file does not have all the required
advisory keys, the task will fail.

Currently, `advisory` is the only supported system.

## Parameters

| Name     | Description                                             | Optional | Default value |
|----------|---------------------------------------------------------|----------|---------------|
| dataPath | Path to the JSON string of the merged data to use       | Yes      | data.json     |
| systems  | The systems to check that all data keys are present for | Yes      | []            |

## Changes since 0.1.0
- Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead