"""Mock completed InternalRequest results for the create-advisory task test.

The task creates the InternalRequest through the Kubernetes Python client, so
the test keeps that operation real to allow the check step to inspect the CR.
Only result retrieval is mocked because no InternalRequest controller runs in
the test cluster to populate ``status.results``.
"""

from __future__ import annotations

from unittest.mock import patch

from release_service_utils.helpers import internal_request


patch.object(
    internal_request,
    "fetch_results",
    autospec=True,
    return_value={
        "result": "Success",
        "advisory_url": "https://access.redhat.com/errata/RHBA-2025:1111",
        "advisory_internal_url": "",
    },
).start()
