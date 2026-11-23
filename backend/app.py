"""Compatibility entrypoint for the AR-IMMS Flask application."""

import pathlib
import sys

if __package__ is None:
    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

from backend.core.application import (
    create_app,
    db,
    event_hub,
    auth_bp,
    api_bp,
)  # noqa: E402

__all__ = ["create_app", "db", "event_hub", "auth_bp", "api_bp"]

if __name__ == "__main__":
    create_app().run(host="0.0.0.0", port=5000, debug=False)

