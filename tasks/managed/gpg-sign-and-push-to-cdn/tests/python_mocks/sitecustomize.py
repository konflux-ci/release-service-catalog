"""Mock external I/O for gpg-sign-and-push-to-cdn unit tests."""

from __future__ import annotations

import json
import os
from pathlib import Path
from unittest.mock import patch

from release_service_utils.helpers import direct_sign_generic, internal_request, skopeo
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


_signing_counter = 0


def _mock_submit(request):
    global _signing_counter
    _signing_counter += 1

    data_dir = os.environ.get("DATA_DIR", "/tmp")
    record = {
        "keyname": request.keyname,
        "sign_method": request.sign_method,
        "onbehalfof": request.onbehalfof,
        "pipeline": request.pipeline,
        "service_account": request.service_account,
        "kerberos_keytab_secret": request.kerberos_keytab_secret,
        "kerberos_keytab": request.kerberos_keytab,
        "kerberos_principal": request.kerberos_principal,
        "intention": request.intention,
        "source_data_artifact": request.source_data_artifact,
    }
    with open(os.path.join(data_dir, "mock_signing_request.json"), "a") as fh:
        fh.write(json.dumps(record) + "\n")

    return {
        "sourceDataArtifact": f"oci://quay.io/mock-signed@sha256:signed{_signing_counter}",
    }


def _mock_ir_create(pipeline, params=None, **kwargs):
    data_dir = os.environ.get("DATA_DIR", "/tmp")
    record = {
        "pipeline": pipeline,
        "params": params or {},
    }
    with open(os.path.join(data_dir, "mock_publish_ir.json"), "a") as fh:
        fh.write(json.dumps(record) + "\n")
    return "mock-ir-name"


def _mock_ir_fetch_results(ir_name):
    return {"result": "Success"}


patch.object(skopeo, "copy", side_effect=_mock_skopeo_copy).start()
patch.object(oras_utils, "oras_push", side_effect=_mock_oras_push).start()
patch.object(
    oras_utils, "copy_all_layered_image_files", side_effect=_mock_copy_layered
).start()
patch.object(
    oras_utils, "copy_all_flat_artifact_files", side_effect=_mock_copy_layered
).start()
patch.object(direct_sign_generic, "submit", side_effect=_mock_submit).start()
patch.object(internal_request, "create", side_effect=_mock_ir_create).start()
patch.object(
    internal_request, "fetch_results", side_effect=_mock_ir_fetch_results
).start()
