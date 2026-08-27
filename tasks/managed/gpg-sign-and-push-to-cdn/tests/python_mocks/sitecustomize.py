"""Mock external I/O for gpg-sign-and-push-to-cdn unit tests.

Loaded via PYTHONPATH before the task script runs. Patches skopeo, oras,
and internal_request so the task exercises its real logic without hitting
any cluster API or OCI registry.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from unittest.mock import patch

from release_service_utils.helpers import internal_request, skopeo
from release_service_utils.helpers import oras_utils


def _mock_skopeo_copy(src, dest_dir, **kwargs):
    dest = Path(dest_dir)
    dest.mkdir(parents=True, exist_ok=True)
    manifest = {
        "schemaVersion": 2,
        "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
        "config": {
            "mediaType": "application/vnd.docker.container.image.v1+json",
            "size": 100,
            "digest": "sha256:fakeconfig",
        },
        "layers": [
            {
                "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
                "size": 200,
                "digest": "sha256:fakelayer",
            }
        ],
    }
    (dest / "manifest.json").write_text(json.dumps(manifest))


def _mock_copy_layered(manifest, image_dir, extract_dir):
    extract = Path(extract_dir)
    extract.mkdir(parents=True, exist_ok=True)
    (extract / "test-binary.tar.gz").write_bytes(b"fake-binary-content")


def _mock_oras_push(tag, context_dir, path, name, **kwargs):
    return "sha256:mockdigest123"


_ir_counter = 0


def _mock_create(pipeline, *, params, labels=None, sync=True, timeout=3600,
                 service_account=None, **kwargs):
    global _ir_counter
    _ir_counter += 1

    data_dir = os.environ.get("DATA_DIR", "/tmp")
    record = {
        "pipeline": pipeline,
        "params": params,
        "labels": labels or {},
        "sync": sync,
        "timeout": timeout,
        "service_account": service_account,
    }
    with open(os.path.join(data_dir, "mock_internal_request.json"), "a") as fh:
        fh.write(json.dumps(record) + "\n")

    return f"mock-ir-{_ir_counter}"


patch.object(skopeo, "copy", side_effect=_mock_skopeo_copy).start()
patch.object(oras_utils, "oras_push", side_effect=_mock_oras_push).start()
patch.object(
    oras_utils, "copy_all_layered_image_files", side_effect=_mock_copy_layered
).start()
patch.object(
    oras_utils, "copy_all_flat_artifact_files", side_effect=_mock_copy_layered
).start()
patch.object(internal_request, "create", side_effect=_mock_create).start()
