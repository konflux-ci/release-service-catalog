"""Capture InternalRequest calls and return success without a signing controller.

The test renderer loads this module through PYTHONPATH before running the real
task. The captured request is included in the output trusted artifact.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from unittest.mock import patch

from release_service_utils.helpers import internal_request

_IR_NAME = "mock-sign-and-push-to-internal-oci-ir"


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
    return _IR_NAME


def _fetch_results(internal_request_name, **kwargs):
    if internal_request_name != _IR_NAME:
        raise ValueError(f"Unexpected InternalRequest name: {internal_request_name}")
    return {"result": "Success"}


patch.object(internal_request, "create", autospec=True, side_effect=_create).start()
patch.object(
    internal_request, "fetch_results", autospec=True, side_effect=_fetch_results
).start()
