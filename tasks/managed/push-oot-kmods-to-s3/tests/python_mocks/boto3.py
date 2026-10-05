"""Mock boto3 for Tekton tests of push-oot-kmods-to-s3.

``import boto3`` hits this module (PYTHONPATH prepend). ``botocore.config``
stays the real package. Uploaded keys are checked at interpreter exit so the
task does not need to wrap ``run()``.
"""

from __future__ import annotations

import atexit
import os
import sys

_EXPECTED_PREFIX = "mocked-vendor-s3/1.2.3-s3/6.5.0-s3/x86_64/"
_DIRTY_KERNEL = "6.5.0-s3.x86_64"
_REQUIRED_KEYS = (
    f"{_EXPECTED_PREFIX}mod1.ko",
    f"{_EXPECTED_PREFIX}envfile",
    f"{_EXPECTED_PREFIX}signed_kmods_checksums_x86_64.txt",
)
_keys: list[str] = []
_client_created = False


class _FakeS3:
    """S3 client stub that records upload_file keys."""

    def upload_file(self, Filename: str, Bucket: str, Key: str) -> None:
        """Record an upload and reject unexpected buckets or dirty kernel paths."""
        if Bucket != "mock-bucket":
            raise RuntimeError(f"unexpected bucket: {Bucket}")
        if _DIRTY_KERNEL in Key:
            raise RuntimeError(f"dirty kernel version in key: {Key}")
        _keys.append(Key)


def client(service_name: str, **kwargs: object) -> _FakeS3:
    """Return a fake S3 client."""
    global _client_created
    if service_name != "s3":
        raise RuntimeError(f"unexpected client: {service_name}")
    _client_created = True
    return _FakeS3()


def _assert_uploads() -> None:
    """Fail if the task created an S3 client but skipped required objects."""
    if not _client_created:
        return
    missing = [key for key in _REQUIRED_KEYS if key not in _keys]
    if missing:
        _fail(f"S3 mock missing uploads: {missing}; keys={_keys}")


def _fail(message: str) -> None:
    """Abort the process. Exceptions raised from atexit are ignored."""
    print(message, file=sys.stderr, flush=True)
    os._exit(1)


atexit.register(_assert_uploads)
