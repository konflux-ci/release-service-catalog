"""Mock pyxis module for smoke tests."""

import json
import logging

_CALL_COUNT = 0


class _Response:
    def __init__(self, data):
        self._data = data
        self.status_code = 200

    def json(self):
        return self._data

    def raise_for_status(self):
        pass


def setup_logger(level=logging.INFO):
    logging.basicConfig(level=level)


def get(url):
    global _CALL_COUNT
    _CALL_COUNT += 1
    return _Response({"data": []})


def post(url, data):
    global _CALL_COUNT
    _CALL_COUNT += 1
    return _Response({"_id": f"mock-image-{_CALL_COUNT}"})


def patch(url, data):
    global _CALL_COUNT
    _CALL_COUNT += 1
    return _Response({"_id": f"mock-image-{_CALL_COUNT}"})


def graphql_query(api_url, body):
    return {"data": {"get_image": {"data": None, "error": None}}}
