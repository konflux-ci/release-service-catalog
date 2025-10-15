# process-file-updates-task

Tekton Task to update files in Git repositories. It is possible to seed a file with initial content and/or apply
replacements to a yaml file that already exists. It will attempt to create a Merge Request in Gitlab.

## Parameters

| Name                           | Description                                                                                                                                                                       | Optional | Default value                            |
|--------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------|------------------------------------------|
| upstream_repo                  | Upstream Git repository                                                                                                                                                           | No       | -                                        |
| repo                           | Git repository                                                                                                                                                                    | No       | -                                        |
| ref                            | Git branch                                                                                                                                                                        | No       | -                                        |
| paths                          | String containing a JSON array of file paths and its replacements or updates E.g. '[{"path":"file1.yaml","replacements":[{"key":".yamlkey1,","replacement":"|regex|replace|"}]}]' | No       | -                                        |
| application                    | Application being released                                                                                                                                                        | No       | -                                        |
| file_updates_secret            | The credentials used to update the git repo                                                                                                                                       | Yes      | file-updates-secret                      |
| tempDir                        | temp dir for cloning and updates                                                                                                                                                  | Yes      | /tmp/$(context.taskRun.uid)/file-updates |
| internalRequestPipelineRunName | name of the PipelineRun that called this task                                                                                                                                     | No       | -                                        |
| caTrustConfigMapName           | The name of the ConfigMap to read CA bundle data from                                                                                                                             | Yes      | trusted-ca                               |
| caTrustConfigMapKey            | The name of the key in the ConfigMap that contains the CA bundle data                                                                                                             | Yes      | ca-bundle.crt                            |
