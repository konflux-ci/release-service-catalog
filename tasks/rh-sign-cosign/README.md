# rh-sign-cosign

Signs container images in provided snapshot.

## Parameters

| Name                                                              | Description                                                    | Optional | Default value |
|-------------------------------------------------------------------|----------------------------------------------------------------|----------|---------------|
| r_signer_wrapper_cosign.r.fake_entry_point_runs                   | (TESTING ONLY) list of fake pubtools-sign entry point runs     | Yes      | []            |
| r_signer_wrapper_cosign.r.fake_entry_point_returns                | (TESTING ONLY) list of fake pubtools-sign entry point returns  | Yes      | []            |
| r_signer_wrapper_cosign.r.fake_entry_point_requests               | (TESTING ONLY) list of fake pubtools-sign entry point requests | Yes      | []            |
| r_signer_wrapper_cosign.r.config_file                             | path to pubtools-sign configuration file                       | No       | ""            |
| r_signer_wrapper_cosign.r.MAX_MANIFEST_DIGESTS_PER_SEARCH_REQUEST | (RADAS ONLY) pyxis search chunk size                           | Yes      | 50            |
| r_signer_wrapper_cosign.r.settings.num_thread_pyxis               | (RADAS ONLY) number of threads when accessing pyxis API        | Yes      | 7             |
| r_signer_wrapper_cosign.r.settings.pyxis_ssl_key_file             | (RADAS ONLY) path to pyxis client certificate                  | No       | ""            |
| r_signer_wrapper_cosign.r.settings.pyxis_ssl_crt_file             | (RADAS ONLY) path to pyxis client certificate key              | No       |               |
| r_signer_wrapper_cosign.r.settings.pyxis_server                   | (RADAS ONLY) Pyxis server hostname                             | No       | ""            |
| r_dst_quay_client.r.fake_manifests                                | (TESTING ONLY) List of fake manifests for testing              | Yes      |               |
| r_dst_quay_client.r.host                                          | Quay host                                                      | No       | ""            |
| r_dst_quay_client.r.password                                      | Quay password                                                  | No       |               |
| r_dst_quay_client.r.username                                      | Quay username                                                  | No       |               |
| i_snapshot_str.data                                               | String with SnapshotSpec in json format                        | No       |               |
| i_signing_key.data                                                | Signing key used to sign containers                            | No       |               |
| i_task_id.data                                                    | (RADAS ONLY) task id sign request identifier                   | No       |               |
| a_pool_size.a                                                     | Number of thread/process executors use for processing data     | Yes      | 10            |
| a_executor_type.a                                                 | Type of paralelism when processing data (THREAD|PROCESS|LOCAL) | Yes      | THREAD        |

## Parameters description
All parameters accept json compatible elements (string, number, boolean, list, dictionary).
If prefix '@' is used, then data are read from file path following the '@'.

## Outputs
 Besides the logs, the task will output the following files:
 - $(workspaces.outputs.path)/root::o_sign_entries
    List of signed containers. The file contains following json structure
    ```
    [
      {
        "name": "o_sign_entries"
          "data": {
            "arch": "", # empty string or <arch> in the case entry coresponds to manifest in manifest list.
            "digest": "sha256:xxxx", # sha256 digest of the manifest
            "reference": "", # reference of the image or null in the case digest container referenced was used on the input
            "repo": "image0", # repository name parsed from input container image. <registry>:<repo>[:<tag>,@<digest>]
            "signing_key": "signing key" or it's alias which was used for signing
          }
      },
      ...
    ]
    ```
 - $(workspaces.outputs.path)/root::stats
    Statistics of the signing process. The file contains YAML with following structure:
    ```
      {
        "name": "stats",
        "data": {
          "finished": "yyyy-mm-ddThh:MM:ss.msecs",
          "skipped": true|false,
          "started": "yyyy-mm-ddThh:MM:ss.msecs"
        }
      }
    ```
 - $(workspaces.outputs.path)/root::state
    Final state of the task. The file contains YAML with following structure:
    ```
    {
      "name": "state",
      "data": "finished"|"failed"
    }
    ```
    For this specific case state can be only finished. In case of probles, code fails with
    exception and state output won't be saved.

## Changes in 1.0.0
First version of rh-sign-cosign
