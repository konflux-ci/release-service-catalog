# collectors-no-cve

This is a variant of the `collectors` integration test that exercises the **no-CVE path**.

## What it tests

When a component image has no CVEs (i.e., the commit message does not reference any CVE IDs):

- The CVE collector produces an empty `releaseNotes.cves` array
- `set-advisory-severity` leaves severity unset (null) since the advisory type remains RHBA
- The advisory description contains no CVE entries
- The release notes `cves` array is empty

This complements the standard `collectors` test which always runs with CVE-2024-8260
present in the commit message.

## Running locally

```bash
./integration-tests/run-test.sh collectors-no-cve
```

## Relationship to `collectors`

This suite shares all Kubernetes resource definitions, vault secrets, and pipeline
configuration with the `collectors` suite via symlinks. The only differences are:

- `test.env`: Unique resource names to avoid collisions with parallel runs, and
  `export NO_CVE="true"` (vs `NO_CVE="false"` in the `collectors` suite)
- `test.sh`: Symlink to `collectors/test.sh` (same verification logic for both paths)
