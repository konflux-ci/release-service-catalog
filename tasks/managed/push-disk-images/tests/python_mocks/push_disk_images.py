"""Mock push_disk_images for task tests - patches only the InternalRequest boundary.

The real push_disk_images module is loaded and executed so that production
parsing and result-writing logic runs unchanged.  Only the Kubernetes
InternalRequest calls are replaced with lightweight fakes.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from unittest.mock import MagicMock


def _find_real_module() -> Path:
    """Locate the installed push_disk_images.py, skipping this mock file."""
    this_file = Path(__file__).resolve()
    for entry in sys.path:
        if not entry:
            continue
        candidate = Path(entry) / "push_disk_images.py"
        if candidate.resolve() != this_file and candidate.is_file():
            return candidate
    raise RuntimeError("Could not locate the real push_disk_images module on sys.path")


def _install_ir_mock() -> None:
    """Pre-populate sys.modules so the real module sees faked InternalRequest calls."""
    mock_ir = MagicMock()
    mock_ir.InternalRequestWaitError = RuntimeError
    mock_ir.create.return_value = "mock-ir-name"
    mock_ir.fetch_results.return_value = {"result": "Success"}

    for name in (
        "release_service_utils.helpers.internal_request",
        "release_service_utils.helpers.internal_request.internal_request",
    ):
        sys.modules[name] = mock_ir


def main() -> int:
    """Patch the IR boundary, then delegate to the real push_disk_images.main()."""
    _install_ir_mock()

    real_path = _find_real_module()
    spec = importlib.util.spec_from_file_location("_push_disk_images_real", real_path)
    real_mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(real_mod)

    return real_mod.main()


if __name__ == "__main__":
    raise SystemExit(main())
