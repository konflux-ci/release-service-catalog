# collect-data

Tekton task to collect the information added to the extraData field of the release resources.

The purpose of this task is to collect all the extra data and supply it to the other task in the pipeline by creating
a json file called `extra-data.json` in the workspace.

This task also stores the passed resources as json files in a workspace.

## Parameters

| Name                 | Description                                        | Optional | Default value |
|----------------------|----------------------------------------------------|----------|---------------|
| release              | Namespaced name of the Release                     | No       | -             |
| releaseplan          | Namespaced name of the ReleasePlan                 | No       | -             |
| releaseplanadmission | Namespaced name of the ReleasePlanAdmission        | No       | -             |
| releasestrategy      | Namespaced name of the ReleaseStrategy             | No       | -             |
| snapshot             | Namespaced name of the Snapshot                    | No       | -             |
