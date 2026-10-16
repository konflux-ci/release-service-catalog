"""Record and verify boto3 S3 uploads for Tekton tests.

Loaded automatically by the Python interpreter from PYTHONPATH before the task
script runs. Replaces boto3.client with a fake that records keys and rejects
dirty kernel-version paths. After run() returns, required object keys are
asserted.
"""

from __future__ import annotations

from unittest.mock import patch

_EXPECTED_PREFIX = "mocked-vendor-s3/1.2.3-s3/6.5.0-s3/x86_64/"
_DIRTY_KERNEL = "6.5.0-s3.x86_64"
_REQUIRED_SUFFIXES = ("mod1.ko", "envfile", "signed_kmods_checksums_x86_64.txt")
_keys: list[str] = []


class _FakeS3:
    """S3 client stub that records upload_file keys."""

    def upload_file(self, Filename: str, Bucket: str, Key: str) -> None:
        """Record an upload and reject unexpected buckets or dirty kernel paths."""
        if Bucket != "mock-bucket":
            raise RuntimeError(f"unexpected bucket: {Bucket}")
        if _DIRTY_KERNEL in Key:
            raise RuntimeError(f"dirty kernel version in key: {Key}")
        _keys.append(Key)


def _client(service_name: str, **kwargs: object) -> _FakeS3:
    """Return a fake S3 client."""
    if service_name != "s3":
        raise RuntimeError(f"unexpected client: {service_name}")
    return _FakeS3()


patch("boto3.client", _client).start()

from release_service_utils.tasks.managed.push_oot_kmods_to_s3 import (  # noqa: E402
    push_oot_kmods_to_s3 as task,
)

_orig_run = task.run


def _run(*args: object, **kwargs: object) -> None:
    """Call the real run() then assert required uploads were recorded."""
    _orig_run(*args, **kwargs)
    missing = [
        suffix
        for suffix in _REQUIRED_SUFFIXES
        if not any(key.endswith(suffix) for key in _keys)
    ]
    if missing:
        raise RuntimeError(f"S3 mock missing uploads: {missing}; keys={_keys}")
    if not any(_EXPECTED_PREFIX in key for key in _keys):
        raise RuntimeError(
            f"S3 mock missing expected prefix {_EXPECTED_PREFIX}; keys={_keys}"
        )


task.run = _run
