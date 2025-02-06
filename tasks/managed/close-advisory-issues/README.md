# close-advisory-issues

Tekton task to close all issues referenced in the releaseNotes. It is meant to run after the advisory is published.
A comment will be added to each closed issue with a link to the advisory it was fixed in.

Note: This task currently only supports issues in issues.redhat.com due to it requiring authentication.
Issues in other servers will be skipped without the task failing.

## Parameters

| Name        | Description                                                                               | Optional | Default value |
|-------------|-------------------------------------------------------------------------------------------|----------|---------------|
| dataPath    | Path to data JSON in the data workspace                                                   | No       | -             |
| advisoryUrl | The url of the advisory the issues were fixed in. This is added in a comment on the issue | No       | -             |
