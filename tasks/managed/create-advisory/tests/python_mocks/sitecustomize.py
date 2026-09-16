"""Return canned InternalRequest results for Tekton unit tests.

create stays real so check-result can inspect the InternalRequest CR. Only
fetch_results is stubbed: with synchronously=false there is no controller to
populate status.results.
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
    },
).start()
