# apply-mapping

Tekton task to apply a mapping to a Snapshot.

The purpose of this task is to merge a mapping with the components contained in a Snapshot.
The mapping is expected to be present in the data field of the ReleasePlanAdmission provided in
the `releasePlanAdmissionPath`. If the data field does not contain a `mapping` key, the original
Snapshot is returned. If there is a `mapping` key, it is merged with the `components` key in the
Snapshot based on component name.

A `mapped` result is also returned from this task containing a simple true/false value that is
meant to inform whether a mapped Snapshot is being returned or the original one.

This task supports variable expansion in tag values from the mapping. The currently supported variables are:
* "{{ timestamp }}" -> The build-date label from the image in the format provided by timestampFormat or %s as the
  default.
  If the build-date label is not available, we use the Created field in the image metadata as a fallback.
* "{{ release_timestamp }}" -> The current time in the format provided by timestampFormat or %s as the default
* "{{ git_sha }}" -> The git sha that triggered the snapshot being processed
* "{{ git_short_sha }}" -> The git sha reduced to 7 characters
* "{{ digest_sha }}" -> The image digest of the respective component
* "{{ incrementer }}" -> Automatically finds the highest existing incremented tag in the
  repository and generates the next sequential tag (e.g., if the highest tag is v1.0.0-2, it will generate v1.0.0-3)
* "{{ oci_version }}" -> The version from OCI image annotations for Helm charts as media type, and from OCI image
  labels for the other supported media types (extracts org.opencontainers.image.version and converts + to _ for
  tag compliance)

You can also expand image labels, e.g. "{{ labels.mylabel }}" -> The value of image label "mylabel"

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value        |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|----------------------|
| snapshotPath            | Path to the JSON string of the Snapshot spec in the config workspace to apply the mapping to                               | No       | -                    |
| dataPath                | Path to the JSON string of the merged data to use in the data workspace                                                    | No       | -                    |
| failOnEmptyResult       | Fail the task if the resulting snapshot contains 0 components                                                              | Yes      | false                |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                   |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                   |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                   |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                   |
| dataDir                 | The location where data will be stored                                                                                     | Yes      | /var/workdir/release |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | -                    |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | No       | -                    |
| caTrustConfigMapName    | The name of the ConfigMap to read CA bundle data from                                                                      | Yes      | trusted-ca           |
| caTrustConfigMapKey     | The name of the key in the ConfigMap that contains the CA bundle data                                                      | Yes      | ca-bundle.crt        |
