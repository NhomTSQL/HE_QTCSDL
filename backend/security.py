"""Request boundaries and single-process abuse limits for the local testbed."""
import hashlib
import threading
import time
from collections import OrderedDict

from flask import jsonify, request


class AttemptLimiter:
    def __init__(self, limit=10, window=60, max_keys=4096):
        self.limit, self.window, self.max_keys = limit, window, max_keys
        self.entries = OrderedDict()
        self.lock = threading.Lock()

    def allow(self, key):
        now = time.monotonic()
        with self.lock:
            started, count = self.entries.pop(key, (now, 0))
            if now - started >= self.window:
                started, count = now, 0
            self.entries[key] = (started, count + 1)
            while len(self.entries) > self.max_keys:
                self.entries.popitem(last=False)
            return count < self.limit


def install_security(app):
    app.config.setdefault("MAX_CONTENT_LENGTH", 1024 * 1024)
    if app.config.get("MAX_CONTENT_LENGTH") is None:
        app.config["MAX_CONTENT_LENGTH"] = 1024 * 1024
    limiter = AttemptLimiter()
    limited = {"/auth/login", "/auth/request-access", "/auth/reset-password",
               "/auth/change-password", "/auth/mfa/setup", "/auth/mfa/enable", "/auth/mfa/disable"}

    @app.before_request
    def request_boundary():
        # BFF users share an address: production requires a shared gateway limiter.
        # Do not trust arbitrary X-Forwarded-For headers here.
        if request.path in limited and request.method == "POST":
            digest = hashlib.sha256((request.remote_addr or "unknown").encode()).hexdigest()
            if not limiter.allow((request.path, digest)):
                return jsonify(error="Too many attempts. Try again in one minute."), 429, {"Retry-After": "60"}
        if request.path.startswith(("/auth/", "/api/")) and request.method in {"POST", "PATCH", "PUT"}:
            if (request.content_length or request.is_json) and not isinstance(request.get_json(silent=True), dict):
                return jsonify(error="Body must be a JSON object."), 400

    @app.after_request
    def response_boundary(response):
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "no-referrer"
        return response

    @app.errorhandler(404)
    def handle_not_found(_exc):
        return jsonify(error="Not found."), 404

    @app.errorhandler(405)
    def handle_method_not_allowed(_exc):
        return jsonify(error="Method not allowed."), 405

    @app.errorhandler(413)
    def handle_payload_too_large(_exc):
        return jsonify(error="Payload too large."), 413
