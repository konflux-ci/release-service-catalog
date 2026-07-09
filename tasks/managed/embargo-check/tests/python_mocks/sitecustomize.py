"""Redirect Jira API requests to the local mock server for Tekton tests.

Loaded automatically by the Python interpreter from PYTHONPATH before the task
script runs.  Patches requests.adapters.HTTPAdapter.send to rewrite URLs for
known Jira hosts to the local mock.

Activated only when JIRA_BASE_URL is set (by mock_server_for_env_var in
mocks.yaml).
"""

from __future__ import annotations

import os
import sys

_MOCK_URL = os.environ.get("JIRA_BASE_URL", "")
if _MOCK_URL:
    from urllib.parse import urlparse, urlunparse

    import requests.adapters

    _JIRA_HOSTS = frozenset(
        {"redhat.atlassian.net", "issues.redhat.com", "bugzilla.redhat.com"}
    )
    _mock_parsed = urlparse(_MOCK_URL)

    _ca_cert = os.environ.get("REQUESTS_CA_BUNDLE", "")
    if _ca_cert and not os.environ.get("SSL_CERT_FILE"):
        os.environ["SSL_CERT_FILE"] = _ca_cert

    _real_send = requests.adapters.HTTPAdapter.send

    def _mock_send(self, request, *args, **kwargs):
        parsed = urlparse(request.url)
        if parsed.hostname in _JIRA_HOSTS:
            request.url = urlunparse(
                parsed._replace(scheme=_mock_parsed.scheme, netloc=_mock_parsed.netloc)
            )
            if "verify" in kwargs:
                kwargs["verify"] = _ca_cert or kwargs["verify"]
        return _real_send(self, request, *args, **kwargs)

    requests.adapters.HTTPAdapter.send = _mock_send
