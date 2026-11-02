"""Mock InternalRequest operations for the request-advisory-oci-artifact task test.

The test renderer prepends this directory to ``PYTHONPATH``, causing Python to
load this module before the task. The test cluster has no InternalRequest
controller, so the mock supplies a completed request and its result.
"""

from __future__ import annotations

from unittest.mock import patch

from release_service_utils.helpers import internal_request


patch.object(
    internal_request,
    "create",
    autospec=True,
    return_value="abc-ir",
).start()
patch.object(
    internal_request,
    "fetch_results",
    autospec=True,
    return_value={
        "result": "Success",
        "advisory_oci_artifact": "oci:quay.io/konflux-ci/abc@sha256:a51f9ce8",
    },
).start()
