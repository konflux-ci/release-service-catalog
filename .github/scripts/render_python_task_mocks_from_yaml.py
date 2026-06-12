#!/usr/bin/env python3
"""Emit bash for Tekton steps that run a Python task with local mocks.

Reads ``tests/mocks.yaml`` and optional ``tests/mocks/`` under the task tests
directory. Invoked from ``test_tekton_tasks.sh`` when merging mocks into a
Python entrypoint step.

YAML is loaded with ``yq -o=json`` (same tool as the Tekton test harness), so
PyYAML is not required.

Schema version 1
----------------
version: 1                    # required

services:                     # optional list
  - type: http_json
    port: 8080                # optional; default 8080
    bind: 127.0.0.1           # optional; default 127.0.0.1
    routes:                   # first match wins; GET only
      - path_suffix: /auth/token
        body: '{"ok": true}'
      - path_contains: /api/v1/widgets
        body: '{}'
    # Task reads its API base URL from this env var (e.g. PYXIS_URL in the Task
    # spec). http_json only starts the mock server; mock_server_for_env_var sets
    # that var to http://BIND:PORT/v1 so requests hit the mock, not production.
    # If the URL lives in a secret mount file instead, use rewrite_secret_mount.
    mock_server_for_env_var: PYXIS_URL
    rewrite_secret_mount:     # optional; after server is listening
      source: /mnt/osidb-service-account
      env_var: OSIDB_SERVICE_ACCOUNT_MOUNT
      url_file: osidb_url

**Mock binaries:** add executable scripts as regular files under ``tests/mocks/``
(e.g. ``tests/mocks/kinit``). Basenames become names on ``PATH`` (``kinit``,
``curl``, …). File contents are embedded into the generated step script at
render time (the task pod does not mount the git tree).

**Mock Python modules:** add ``.py`` files under ``tests/python_mocks/``
(e.g. ``tests/python_mocks/requests_kerberos.py``). They are written to a temp
directory prepended to ``PYTHONPATH``, so ``import requests_kerberos`` loads the
mock instead of the real package. Use this when the task script imports a Python
library that cannot work in the test environment (e.g. libraries that need live
credentials).

``http_json`` uses ``.github/scripts/mock_http_json.py`` (copied into the step
at render time). At most one ``http_json`` service per file (v1). Extend this
module for new ``type`` values.
"""

from __future__ import annotations

import base64
import json
import re
import secrets
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Any

_NAME_SAFE = re.compile(r"^[a-zA-Z0-9._-]+$")
_ENV_SAFE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
_MOCK_HTTP_JSON = Path(__file__).resolve().parent / "mock_http_json.py"


def _die(msg: str) -> None:
    sys.stderr.write(f"render_python_task_mocks_from_yaml: {msg}\n")
    raise SystemExit(1)


def _load_mocks(path: Path) -> dict[str, Any]:
    try:
        raw = subprocess.check_output(
            ["yq", "-o=json", ".", str(path)],
            text=True,
        )
    except FileNotFoundError:
        _die("yq not found on PATH")
    except subprocess.CalledProcessError as exc:
        _die(f"yq failed: {exc}")
    if not raw.strip():
        return {}
    return json.loads(raw)


def _http_json_services(data: dict[str, Any]) -> list[dict[str, Any]]:
    services = data.get("services") or []
    return [s for s in services if isinstance(s, dict) and s.get("type") == "http_json"]


def _heredoc_lines(dest: str, body: str, label: str) -> list[str]:
    """Emit ``cat <<'DELIM' >dest`` … ``DELIM`` for a quoted heredoc."""
    for _ in range(8):
        delim = "TEKTONMOCK" + secrets.token_hex(16)
        if delim not in body:
            break
    else:
        _die(f"could not pick a heredoc delimiter for {label}")
    return [
        f"cat <<'{delim}' >{dest}",
        body.rstrip("\n"),
        delim,
        "",
    ]


def _heredoc_embed(dest_var: str, body: str, label: str) -> list[str]:
    """Write ``body`` to a new temp file stored in ``$dest_var``."""
    return [
        f'{dest_var}="$(mktemp)"',
        *_heredoc_lines(f'"${{{dest_var}}}"', body, label),
    ]


def _render_http_json(svc: dict[str, Any]) -> str:
    port = int(svc.get("port", 8080))
    bind = str(svc.get("bind", "127.0.0.1"))
    routes = svc.get("routes")
    if not isinstance(routes, list):
        _die("http_json service requires a routes list")
    routes_b64 = base64.standard_b64encode(
        json.dumps(routes).encode("utf-8")
    ).decode("ascii")

    if not _MOCK_HTTP_JSON.is_file():
        _die(f"missing {_MOCK_HTTP_JSON}")
    mock_http_body = _MOCK_HTTP_JSON.read_text(encoding="utf-8")

    lines = [
        "# Generated from tests/mocks.yaml + tests/mocks/ "
        "(render_python_task_mocks_from_yaml.py).",
        "# TASK_ENTRYPOINT is prepended by test_tekton_tasks.sh.",
        "",
        "set -eux",
        "",
        f"PORT={port}",
        f"BIND={shlex.quote(bind)}",
        f"export TEKTON_ROUTES_B64='{routes_b64}'",
        'export TEKTON_HTTP_BIND="${BIND}"',
        "",
    ]
    lines += _heredoc_embed("MOCK_HTTP_JSON", mock_http_body, "mock_http_json.py")
    lines += [
        'python3 "${MOCK_HTTP_JSON}" "$PORT" &',
        "",
        r"for _ in $(seq 1 50); do",
        r'  if (echo >/dev/tcp/"${BIND}"/"${PORT}") 2>/dev/null; then',
        r"    break",
        r"  fi",
        r"  sleep 0.1",
        r"done",
        "",
    ]
    mock_server_for_env_var = svc.get("mock_server_for_env_var")
    if mock_server_for_env_var is not None:
        if not isinstance(mock_server_for_env_var, str) or not _ENV_SAFE.match(
            mock_server_for_env_var
        ):
            _die(f"invalid mock_server_for_env_var: {mock_server_for_env_var!r}")
        lines += [
            f'export {mock_server_for_env_var}="http://${{BIND}}:${{PORT}}/v1"',
            "",
        ]
    rw = svc.get("rewrite_secret_mount")
    if rw:
        if not isinstance(rw, dict):
            _die("rewrite_secret_mount must be a mapping")
        src = rw.get("source")
        env_var = rw.get("env_var")
        url_file = rw.get("url_file")
        ok = (
            isinstance(src, str)
            and isinstance(env_var, str)
            and isinstance(url_file, str)
        )
        if not ok:
            _die("rewrite_secret_mount needs source, env_var, url_file strings")
        if not _ENV_SAFE.match(env_var):
            _die(f"invalid env_var for rewrite_secret_mount: {env_var!r}")
        if not _NAME_SAFE.match(url_file):
            _die(f"invalid url_file for rewrite_secret_mount: {url_file!r}")
        qsrc = shlex.quote(src + "/.")
        lines += [
            r'MOCK_SA="$(mktemp -d)"',
            rf'cp -a {qsrc} "${{MOCK_SA}}/"',
            r'chmod -R u+w "${MOCK_SA}"',
            (
                'printf \'%s\\n\' "http://${BIND}:${PORT}" '
                f'> "${{MOCK_SA}}/{url_file}"'
            ),
            f'export {env_var}="${{MOCK_SA}}"',
            "",
        ]
    return "\n".join(lines)


def _render_mock_binaries_from_dir(tests_dir: Path) -> str:
    """Turn ``tests/mocks/<name>`` files into a temp dir prepended to ``PATH``."""
    mock_dir = tests_dir / "mocks"
    if not mock_dir.is_dir():
        return ""
    paths = sorted(
        p
        for p in mock_dir.iterdir()
        if p.is_file() and not p.name.startswith(".")
    )
    if not paths:
        return ""
    lines = [
        'MOCK_BIN_ROOT="$(mktemp -d)"',
        'export PATH="${MOCK_BIN_ROOT}:${PATH}"',
        "",
    ]
    for path in paths:
        if not _NAME_SAFE.match(path.name):
            _die(
                "mock binary filename must match "
                f"^[a-zA-Z0-9._-]+$: {path.name!r} ({path})"
            )
        body = path.read_text(encoding="utf-8")
        dest = f'"${{MOCK_BIN_ROOT}}/{path.name}"'
        lines += _heredoc_lines(dest, body, path.name)
        lines.append(f"chmod +x {dest}")
        lines.append("")
    return "\n".join(lines)


def _render_python_module_mocks_from_dir(tests_dir: Path) -> str:
    """Turn ``tests/python_mocks/<mod>.py`` files into a temp dir prepended to ``PYTHONPATH``."""
    mock_dir = tests_dir / "python_mocks"
    if not mock_dir.is_dir():
        return ""
    paths = sorted(
        p
        for p in mock_dir.iterdir()
        if p.is_file() and p.suffix == ".py" and not p.name.startswith(".")
    )
    if not paths:
        return ""
    lines = [
        'MOCK_PYMOD_ROOT="$(mktemp -d)"',
        'export PYTHONPATH="${MOCK_PYMOD_ROOT}:${PYTHONPATH:-}"',
        "",
    ]
    for path in paths:
        if not _NAME_SAFE.match(path.name):
            _die(
                "mock Python module filename must match "
                f"^[a-zA-Z0-9._-]+$: {path.name!r} ({path})"
            )
        body = path.read_text(encoding="utf-8")
        dest = f'"${{MOCK_PYMOD_ROOT}}/{path.name}"'
        lines += _heredoc_lines(dest, body, path.name)
        lines.append("")
    return "\n".join(lines)


def render(tests_dir: Path) -> str:
    mocks_path = tests_dir / "mocks.yaml"
    if not mocks_path.is_file():
        _die(f"missing {mocks_path}")

    data = _load_mocks(mocks_path)
    if data.get("version") != 1:
        _die("mocks.yaml must set version: 1")

    if data.get("binaries"):
        _die(
            "mocks.yaml field 'binaries' is not supported; "
            "use one file per command under tests/mocks/<name> instead"
        )

    http_svcs = _http_json_services(data)
    if len(http_svcs) > 1:
        _die("at most one http_json service (v1)")

    parts: list[str] = []
    if http_svcs:
        parts.append(_render_http_json(http_svcs[0]))
    parts.append(_render_mock_binaries_from_dir(tests_dir))
    parts.append(_render_python_module_mocks_from_dir(tests_dir))
    parts.append('exec "${TASK_ENTRYPOINT[@]}"')
    return "\n".join(p for p in parts if p)


def main() -> None:
    if len(sys.argv) != 2:
        _die("usage: render_python_task_mocks_from_yaml.py <tests_dir>")
    out = render(Path(sys.argv[1]))
    sys.stdout.write(out)
    if not out.endswith("\n"):
        sys.stdout.write("\n")


if __name__ == "__main__":
    main()
