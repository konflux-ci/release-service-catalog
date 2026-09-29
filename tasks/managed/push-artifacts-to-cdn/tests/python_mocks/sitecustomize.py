"""Capture InternalRequest calls without requiring an internal-services controller.

The test renderer prepends this directory to PYTHONPATH, so Python imports this
module before running the task. Keep the real module's constants and pure helpers
and replace only the calls that create/wait for requests and fetch their results.
The captured request travels through the trusted artifact to check-result.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from unittest.mock import patch

from release_service_utils.helpers import internal_request


def _create(pipeline, **kwargs):
    request_path = (
        Path(os.environ["PARAM_DATA_DIR"])
        / os.environ["PARAM_RESULTS_DIR_PATH"]
        / "internal-request.json"
    )
    request_path.parent.mkdir(parents=True, exist_ok=True)
    request_path.write_text(
        json.dumps({"pipeline": pipeline, **kwargs}), encoding="utf-8"
    )
    return "mock-push-artifacts-to-cdn-ir"


patch.object(internal_request, "create", autospec=True, side_effect=_create).start()
patch.object(
    internal_request,
    "fetch_results",
    autospec=True,
    return_value={
        "result": "Success",
        "checksum_map": "quay.io/checksum-map@sha256:abcdef",
    },
).start()
