# rh-sign-cosign

Signs container images in provided snapshot.

## Parameters

| Name                    | Description                                                             | Optional | Default value          |
|-------------------------|-------------------------------------------------------------------------|----------|------------------------|
| r_signer_wrapper_cosign | Configuration of signing wrapper                                        | No       |                        |
| r_dst_quay_client       | Configuration of QuayClient                                             | No       |                        |
| i_snapshot_str          | Snapshot string                                                         | Yes      | ""                     |
| i_snapshot_file         | Path to snapshot filename                                               | Yes      | ""                     |
|                         | One of i_snapshot_file or i_snapshot_str needs to be set                |          |                        |
| i_signing_key           | Signing key which should be used for the signing process                | No       |                        |
| i_task_id               | Task id identifier - can by any value, not used for cosign signing      | No       |                        |
| a_pool_size             | number of workers for parallel processing                               | Yes      | 10                     |
| a_executor_type         | type of worker for parallel processing (LOCAL, THREAD, PROCESS)         | Yes      | THREAD                 |

## Parameters description
 All parameters are accepted as YAML string. Here's example of r_dst_quay_client parameter how it's used in TaskRun:
 ```
 params:
    - name: r_dst_quay_client
      value: |-
        ---
          r:
            username: 'test'
            password: 'password'
            host: "quay.io"
 ```
 In general all value parameters are YAML strings. For non-complex attributes (like strings, numbers) YAML consists
 of dictionary "data": "value", like this one (example of params from TaskRun):
 ```
 params:
    - name: i_signing_key
      value: |-
        ---
          data: 'test-signing-key'
 ```

## Outputs
 Besides the logs, the task will output the following files:
 - $(workspaces.outputs.path)/root::o_sign_entries
    List of signed containers. The file contains YAML with following structure:
    ```
      name: o_sign_entries
      data: |
        data:
        - arch: '' # empty string or <arch> in the case entry coresponds to manifest in manifest list.
          digest: sha256:xxxx # sha256 digest of the manifest
          reference: "" # reference of the image or null in the case digest container referenced was used on the input
          repo: image0 # repository name parsed from input container image. <registry>:<repo>[:<tag>,@<digest>]
          signing_key: signing key or it's alias which was used for signing
      EOF
    ```
 - $(workspaces.outputs.path)/root::stats
    Statistics of the signing process. The file contains YAML with following structure:
    ```
    name: stats
    data: |
      finished: 'yyyy-mm-ddThh:MM:ss.msecs'
      skipped: true|false
      started: 'yyyy-mm-ddThh:MM:ss.msecs'
    ```
 - $(workspaces.outputs.path)/root::state
    Final state of the task. The file contains YAML with following structure:
    ```
    name: stats
    data: |
        data: 'finished' # finished or failed
    ```
    For this specific case state can be only finished. In case of probles, code fails with
    exception and state output won't be saved.

## Changes in 1.0.0
First version of rh-sign-cosign
