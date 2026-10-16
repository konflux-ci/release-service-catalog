"""Sitecustomize for publish-index-image-task tests - mocks skopeo inspect and copy.

Python loads sitecustomize.py automatically on startup.
DO NOT import the real module here - that defeats the purpose of mocking.
"""

from __future__ import annotations

import json
import sys
from subprocess import CompletedProcess
from types import ModuleType
from typing import Any

# Mock data for different images
# Note: inspect() is called without docker:// prefix, copy() is called with it
_MOCK_DATA_INSPECT = {
    # Match scenario - source and target have same digest
    "registry-proxy.engineering.redhat.com/match@sha256:match1234567890": {
        "config": {
            "config": {
                "Labels": {
                    "com.redhat.index.delivery.version": "v4.12"
                }
            }
        },
        "plain": {
            "Digest": "sha256:match1234567890"
        }
    },
    "quay.io/match-target-digest": {
        "plain": {
            "Digest": "sha256:match1234567890",
            "Labels": {
                "com.redhat.index.delivery.version": "v4.12"
            }
        }
    },
    # Success scenario - different digests
    "quay.io/source@sha256:abcdef1234567890": {
        "config": {
            "config": {
                "Labels": {
                    "com.redhat.index.delivery.version": "v4.12"
                }
            }
        }
    },
    "quay.io/target": {
        "plain": {
            "Digest": "sha256:target1234567890",
            "Labels": {
                "com.redhat.index.delivery.version": "v4.12"
            }
        }
    },
    # Registry proxy scenario
    "registry-proxy.engineering.redhat.com/foo@sha256:0987654321fedcba": {
        "config": {
            "config": {
                "Labels": {
                    "com.redhat.index.delivery.version": "v4.12"
                }
            }
        }
    },
    "registry-proxy.engineering.redhat.com/foo": {
        "plain": {
            "Digest": "sha256:0987654321fedcba",
            "Labels": {
                "com.redhat.index.delivery.version": "v4.12"
            }
        }
    },
    # Failure scenario
    "registry-proxy.engineering.redhat.com/fail@sha256:0987654321fedcba": {
        "config": {
            "config": {
                "Labels": {
                    "com.redhat.index.delivery.version": "v4.12"
                }
            }
        }
    },
    "registry-proxy.engineering.redhat.com/fail": {
        "plain": None  # Will return error
    },
    # Version mismatch scenarios
    "quay.io/version-mismatch@sha256:versionmismatch123": {
        "config": {
            "config": {
                "Labels": {
                    "com.redhat.index.delivery.version": "v4.11"
                }
            }
        }
    },
    "quay.io/version-mismatch-target:v4.12": {
        "plain": {
            "Digest": "sha256:different9999",
            "Labels": {
                "com.redhat.index.delivery.version": "v4.12"
            }
        }
    },
    # Version mismatch v4.12 vs v4.13
    "registry-proxy.engineering.redhat.com/mismatchver@sha256:1234567890": {
        "config": {
            "config": {
                "Labels": {
                    "com.redhat.index.delivery.version": "v4.12"
                }
            }
        }
    },
    "quay.io/mismatch-ver-target-digest:v4.20": {
        "plain": {
            "Digest": "sha256:mismatch999",
            "Labels": {
                "com.redhat.index.delivery.version": "v4.13"
            }
        }
    }
}


def mock_inspect(image: str, *, config: bool = False, **kwargs: Any) -> CompletedProcess:
    """Mock skopeo inspect operation.

    Args:
        image: Image reference WITHOUT docker:// prefix (e.g., "registry.io/image:tag").
        config: Whether to inspect the image config.
        **kwargs: Other arguments (creds, retry_times, etc.) - ignored in mock.

    Returns:
        CompletedProcess with stdout containing JSON or error.
    """
    # Check if we have mock data for this image
    if image in _MOCK_DATA_INSPECT:
        data = _MOCK_DATA_INSPECT[image]

        if config and "config" in data:
            # Return config inspection
            stdout = json.dumps(data["config"])
            return CompletedProcess(
                args=["skopeo", "inspect", "--config", image],
                returncode=0,
                stdout=stdout,
                stderr=""
            )
        elif not config and "plain" in data:
            # Return regular inspection
            if data["plain"] is None:
                # Simulate error
                return CompletedProcess(
                    args=["skopeo", "inspect", image],
                    returncode=1,
                    stdout="",
                    stderr="Error: image does not exist"
                )
            stdout = json.dumps(data["plain"])
            return CompletedProcess(
                args=["skopeo", "inspect", image],
                returncode=0,
                stdout=stdout,
                stderr=""
            )

    # Image not found in mocks
    return CompletedProcess(
        args=["skopeo", "inspect", image],
        returncode=1,
        stdout="",
        stderr="Error: image does not exist"
    )


def mock_copy(source: str, destination: str, **kwargs: Any) -> CompletedProcess:
    """Mock skopeo copy operation.

    Args:
        source: Source image reference.
        destination: Destination image reference.
        **kwargs: Other arguments (creds, all, preserve_digests, etc.) - ignored in mock.

    Returns:
        CompletedProcess indicating success or failure.
    """
    # print(f"MOCK: copy({source}, {destination})", flush=True)

    # Check for specific failure scenarios
    if "fail" in source:
        return CompletedProcess(
            args=["skopeo", "copy", source, destination],
            returncode=1,
            stdout="",
            stderr="Error: copy failed"
        )

    # Default: success
    return CompletedProcess(
        args=["skopeo", "copy", source, destination],
        returncode=0,
        stdout="",
        stderr=""
    )


# Create mock skopeo module
class _MockSkopeoModule(ModuleType):
    """Mock skopeo module that provides inspect and copy functions."""

    # Set module-level attributes
    inspect = staticmethod(mock_inspect)
    copy = staticmethod(mock_copy)

    def __getattr__(self, name):
        # Only support inspect and copy
        if name == "inspect":
            return mock_inspect
        elif name == "copy":
            return mock_copy
        raise AttributeError(f"module 'release_service_utils.helpers.skopeo' has no attribute '{name}'")


_skopeo_mod = _MockSkopeoModule("skopeo")

# Inject mock into sys.modules BEFORE any real import happens
sys.modules["release_service_utils.helpers.skopeo"] = _skopeo_mod

# Debug: confirm mock loaded (to stderr to avoid polluting stdout/results)
print("MOCK: sitecustomize loaded, skopeo mocked", file=sys.stderr, flush=True)
