"""Mock external I/O for gpg-sign-and-push-to-cdn-task unit tests."""

from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import patch, MagicMock

from release_service_utils.helpers import skopeo
from release_service_utils.helpers.oras_utils import (
    copy_all_flat_artifact_files,
    copy_all_layered_image_files,
    oras_pull,
)
from release_service_utils.helpers.cdn import cdn
import publish_to_cgw_wrapper


def _mock_skopeo_copy(src, dest_dir, **kwargs):
    dest = Path(dest_dir)
    dest.mkdir(parents=True, exist_ok=True)
    manifest = {
        "schemaVersion": 2,
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
    (extract / "test-binary-linux-amd64.tar.gz").write_bytes(b"fake-binary-content")


def _mock_oras_pull(pull_spec, pull_dir):
    pull_dir = Path(pull_dir)
    pull_dir.mkdir(parents=True, exist_ok=True)
    sig_dir = pull_dir / "signatures"
    sig_dir.mkdir(parents=True, exist_ok=True)
    (sig_dir / "test-binary-linux-amd64.tar.gz.sig").write_bytes(b"fake-signature")
    results = {
        "results": [
            {
                "file": "/releases/test-binary-linux-amd64.tar.gz",
                "signature_file": "signatures/test-binary-linux-amd64.tar.gz.sig",
            }
        ]
    }
    (pull_dir / "results.json").write_text(json.dumps(results))


patch.object(skopeo, "copy", side_effect=_mock_skopeo_copy).start()
patch.object(
    cdn, "create_exodus_conf", side_effect=lambda *a, **kw: None
).start()
patch.object(
    cdn, "push_files_to_cdn", side_effect=lambda *a, **kw: None
).start()
patch(
    "release_service_utils.helpers.oras_utils.copy_all_layered_image_files",
    side_effect=_mock_copy_layered,
).start()
patch(
    "release_service_utils.helpers.oras_utils.copy_all_flat_artifact_files",
    side_effect=_mock_copy_layered,
).start()
patch(
    "release_service_utils.helpers.oras_utils.oras_pull",
    side_effect=_mock_oras_pull,
).start()
patch.object(
    publish_to_cgw_wrapper, "process_component", side_effect=lambda **kw: None
).start()
