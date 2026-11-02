"""Mock Azure SDK for Tekton tests of push-oot-kmods-to-azure.

``import azure`` hits this module (PYTHONPATH prepend), the same way the S3
task mocks ``boto3``. Nested imports (``azure.identity``, ``azure.storage.blob``,
``azure.core.exceptions``) are registered in ``sys.modules`` so the real SDK
packages are never loaded. Uploaded blob names are checked at interpreter exit.
"""

from __future__ import annotations

import atexit
import os
import sys
import types

# Treat this file as the ``azure`` package so ``import azure.identity`` works.
__path__: list[str] = []

_EXPECTED_PREFIX = "mocked-vendor-azure/1.2.3-az/6.5.0-az/x86_64/"
_DIRTY_KERNEL = "6.5.0-az.x86_64"
_REQUIRED_KEYS = (
    f"{_EXPECTED_PREFIX}mod1.ko",
    f"{_EXPECTED_PREFIX}envfile",
    f"{_EXPECTED_PREFIX}signed_kmods_checksums_x86_64.txt",
)
_EXPECTED_CONTAINER = "mock-container"
_EXPECTED_ACCOUNT_URL = "https://mockstorageaccount.blob.core.windows.net"
_blobs: list[str] = []
_client_created = False


class ResourceExistsError(Exception):
    """Stub of azure.core.exceptions.ResourceExistsError."""


class ClientSecretCredential:
    """Stub service-principal credential."""

    def __init__(self, tenant_id: str, client_id: str, client_secret: str) -> None:
        """Record constructor args used by the task."""
        if tenant_id != "mock-tenant-id":
            raise RuntimeError(f"unexpected tenant: {tenant_id}")
        if client_id != "mock-client-id":
            raise RuntimeError(f"unexpected client id: {client_id}")
        if client_secret != "mock-client-secret":
            raise RuntimeError("unexpected client secret")


class _FakeBlob:
    """Blob client stub that records upload_blob names."""

    def __init__(self, container: str, blob: str) -> None:
        """Store the target container and blob name."""
        if container != _EXPECTED_CONTAINER:
            raise RuntimeError(f"unexpected container: {container}")
        if _DIRTY_KERNEL in blob:
            raise RuntimeError(f"dirty kernel version in blob: {blob}")
        self._blob = blob

    def upload_blob(self, data: object, overwrite: bool = False) -> None:
        """Record an upload and require overwrite=True."""
        if not overwrite:
            raise RuntimeError(f"upload of {self._blob} missing overwrite=True")
        _blobs.append(self._blob)


class BlobServiceClient:
    """BlobServiceClient stub that records container create and uploads."""

    def __init__(self, account_url: str, credential: object) -> None:
        """Record that a client was constructed for the mock account."""
        global _client_created
        if account_url != _EXPECTED_ACCOUNT_URL:
            raise RuntimeError(f"unexpected account url: {account_url}")
        if credential is None:
            raise RuntimeError("missing credential")
        _client_created = True

    def create_container(self, name: str) -> None:
        """Accept container create for the mock container name."""
        if name != _EXPECTED_CONTAINER:
            raise RuntimeError(f"unexpected container create: {name}")

    def get_blob_client(self, container: str, blob: str) -> _FakeBlob:
        """Return a fake blob client for *blob* in *container*."""
        return _FakeBlob(container, blob)


def _assert_uploads() -> None:
    """Fail if the task created a client but skipped required objects."""
    if not _client_created:
        return
    missing = [key for key in _REQUIRED_KEYS if key not in _blobs]
    if missing:
        _fail(f"Azure mock missing uploads: {missing}; blobs={_blobs}")


def _fail(message: str) -> None:
    """Abort the process. Exceptions raised from atexit are ignored."""
    print(message, file=sys.stderr, flush=True)
    os._exit(1)


def _install_submodule(name: str, **attrs: object) -> types.ModuleType:
    """Register ``azure.*`` submodule *name* on this package and in sys.modules."""
    module = types.ModuleType(name)
    for key, value in attrs.items():
        setattr(module, key, value)
    sys.modules[name] = module
    return module


identity = _install_submodule(
    "azure.identity",
    ClientSecretCredential=ClientSecretCredential,
)
storage = _install_submodule("azure.storage")
storage.blob = _install_submodule(
    "azure.storage.blob",
    BlobServiceClient=BlobServiceClient,
)
core = _install_submodule("azure.core")
core.exceptions = _install_submodule(
    "azure.core.exceptions",
    ResourceExistsError=ResourceExistsError,
)

atexit.register(_assert_uploads)
