"""Mock fetch_results so the test doesn't need a real internal-services controller.

Loaded automatically by the Python interpreter from PYTHONPATH before the task
script runs.
"""

from __future__ import annotations

from unittest.mock import patch

from release_service_utils.helpers import internal_request

# synchronously=false, so create() never waits on status, so only the results
# needs faking. IR is created for real (see pre-apply-task-hook.sh).
patch.object(
    internal_request,
    "fetch_results",
    autospec=True,
    return_value={
        "result": "Success",
        "advisory_url": "https://access.redhat.com/errata/RHBA-2025:1111",
    },
).start()
