"""Capture InternalRequest calls without requiring an internal-services controller.

The test renderer prepends this directory to PYTHONPATH, so Python imports this
module before running the task. Keep the real module's constants and pure helpers
and replace only the calls that create/wait for requests and fetch their results.
The captured request travels through the trusted artifact to check-result.
"""

from __future__ import annotations

import base64
import gzip
import json
import os
from pathlib import Path
from unittest.mock import patch

from release_service_utils.helpers import internal_request

# Intercept InternalRequest creation and patch a successful IIB result onto status.
_JSON_BUILD_INFO = base64.b64encode(
    gzip.compress(
        json.dumps(
            {
                "updated": "2024-03-06T16:39:11.314092Z",
                "index_image": "redhat.com/rh-stage/iib:01",
                "internal_index_image_copy_resolved": "redhat.com/rh-stage/iib@sha256:abcdefghijk",
            }
        ).encode()
    )
).decode()


def _create(pipeline, **kwargs):
    request_path = (
        Path(os.environ["DATA_DIR"]) / os.environ["RESULTS_DIR_PATH"] / "internal-request.json"
    )
    request_path.parent.mkdir(parents=True, exist_ok=True)
    request_path.write_text(
        json.dumps({"pipeline": pipeline, **kwargs}), encoding="utf-8"
    )
    return "mock-add-fbc-contribution-ir"


patch.object(internal_request, "create", autospec=True, side_effect=_create).start()
patch.object(
    internal_request,
    "fetch_results",
    autospec=True,
    return_value={
        "jsonBuildInfo": _JSON_BUILD_INFO,
        "indexImageDigests": "quay.io/a quay.io/b",
        "iibLog": "Dummy IIB Log",
        "exitCode": "0",
    },
).start()
