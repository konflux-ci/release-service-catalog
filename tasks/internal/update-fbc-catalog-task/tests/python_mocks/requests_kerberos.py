"""Stub requests_kerberos for Tekton tests (no live Kerberos credentials)."""

OPTIONAL = 1
REQUIRED = 2
DISABLED = 3


class HTTPKerberosAuth:
    def __init__(self, **kwargs):
        pass

    def __call__(self, r):
        return r
