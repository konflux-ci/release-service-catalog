"""Stub pyxis for Tekton tests (no live Pyxis credentials or server needed)."""

from __future__ import annotations
from typing import Any


def graphql_query(
    graphql_api: str, body: dict[str, Any], allow_not_found: bool = False
) -> dict[str, Any]:
    return {"find_signatures": {"data": [], "error": None}}


def _get_session(retry_allowed_methods: Any = None) -> None:
    return None
