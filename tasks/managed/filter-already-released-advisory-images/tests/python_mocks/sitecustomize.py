"""Mock fetch_results so the test doesn't need a real internal-services controller.

Loaded automatically by the Python interpreter from PYTHONPATH before the task
script runs.
"""

from __future__ import annotations

import base64
import gzip
import json
from unittest.mock import patch

from release_service_utils.helpers import internal_request

# synchronously=false, so create() never waits on status. So only the results
# needs faking. IR is created for real (see pre-apply-task-hook.sh).
_UNRELEASED = base64.b64encode(gzip.compress(json.dumps(["new-component"]).encode())).decode()

patch.object(
    internal_request,
    "fetch_results",
    autospec=True,
    return_value={
        "result": "Success",
        "unreleased_components": _UNRELEASED,
        "advisory_url": "https://access.redhat.com/errata/RHBA-2024:1234",
        "advisory_internal_url": (
            "https://gitlab.example.com/repo/-/raw/main/data/advisories/dev/2024/1234/advisory.yaml"
        ),
    },
).start()
