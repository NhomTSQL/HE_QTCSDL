"""Security regression tests: isolated Flask app and mocked SQL, no live writes."""
import datetime
import unittest
import uuid
from unittest.mock import MagicMock, patch

import jwt
from flask import Flask
from sqlalchemy.exc import DBAPIError

import auth
from dashboard_api import api_bp
from security import install_security


def row(value):
    result = MagicMock()
    result.mappings.return_value.first.return_value = value
    result.mappings.return_value.all.return_value = [value] if value else []
    return result


class SecurityTests(unittest.TestCase):
    def setUp(self):
        self.app = Flask(__name__)
        self.app.config.update(TESTING=True, JWT_SECRET_KEY="isolated-test-signing-key-" * 2)
        install_security(self.app)
        self.app.register_blueprint(auth.auth_bp)
        self.app.register_blueprint(api_bp)
        self.client = self.app.test_client()
        self.principal = {"user_id": 2, "username": "tech", "role_name": auth.ROLE_TECHNICIAN}
        self.sql_patch = patch.object(auth.db, "session", MagicMock())
        self.sql = self.sql_patch.start()
        self.addCleanup(self.sql_patch.stop)
        self.sql.execute.return_value = row(self.principal)

    def token(self, **overrides):
        claims = {"sub": "2", "jti": str(uuid.uuid4()), "security_version": 1,
                  "role": auth.ROLE_TECHNICIAN,
                  "exp": datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(minutes=5)}
        claims.update(overrides)
        return jwt.encode(claims, self.app.config["JWT_SECRET_KEY"], algorithm="HS256")

    def headers(self, **claims):
        return {"Authorization": "Bearer " + self.token(**claims)}

    def test_missing_session_schema_cannot_issue_token(self):
        self.sql.execute.side_effect = DBAPIError("CALL", {}, Exception("2812 missing procedure"))
        with self.app.app_context(), self.assertRaises(DBAPIError):
            auth._issue_token({"user_id": 2, "username": "tech", "role_name": auth.ROLE_TECHNICIAN})

    def test_missing_session_schema_cannot_authorize(self):
        self.sql.execute.side_effect = DBAPIError("CALL", {}, Exception("2812 missing procedure"))
        self.assertEqual(self.client.get("/auth/me", headers=self.headers()).status_code, 503)

    def test_revoked_session_denied(self):
        self.sql.execute.return_value = row(None)
        self.assertEqual(self.client.get("/auth/me", headers=self.headers()).status_code, 401)

    def test_current_database_role_overrides_token_role(self):
        response = self.client.get("/auth/demo/admin", headers=self.headers(role=auth.ROLE_ADMIN))
        self.assertEqual(response.status_code, 403)

    def test_malformed_sub_is_401_not_500(self):
        self.assertEqual(self.client.get("/auth/me", headers=self.headers(sub="oops")).status_code, 401)
        self.sql.execute.assert_not_called()

    def test_legacy_token_without_session_claims_denied(self):
        self.assertEqual(self.client.get("/auth/me", headers=self.headers(jti=None)).status_code, 401)

    def test_expired_token_denied(self):
        self.assertEqual(self.client.get("/auth/me", headers=self.headers(exp=1)).status_code, 401)

    def test_unsigned_token_denied(self):
        unsigned = jwt.encode({"sub": "2", "exp": 9999999999}, key="", algorithm="none")
        self.assertEqual(self.client.get("/auth/me", headers={"Authorization": "Bearer " + unsigned}).status_code, 401)

    def test_sse_checks_revocation(self):
        self.sql.execute.return_value = row(None)
        self.assertEqual(self.client.get("/api/stream?once=1", headers=self.headers()).status_code, 401)

    def test_sse_closes_on_revocation_before_next_event(self):
        self.sql.execute.side_effect = [row(self.principal), row(None)]
        response = self.client.get("/api/stream", headers=self.headers(), buffered=False)
        with patch("dashboard_api.event_hub.wait_next", return_value=(999, {"type": "secret"})):
            data = b"".join(response.response)
        self.assertNotIn(b"secret", data)

    def test_cross_user_ticket_writes_blocked_before_mutation(self):
        for method, endpoint, payload in [
            ("patch", "/api/tickets/999/status", {"status": "IN_PROGRESS"}),
            ("post", "/api/tickets/999/notes", {"note_text": "probe"}),
            ("post", "/api/tickets/999/closure-request",
             {"summary": "probe", "resolution_details": "probe", "maintenance_type": "CORRECTIVE"}),
            ("post", "/api/containers/999/restart", {}),
        ]:
            with self.subTest(endpoint=endpoint):
                self.sql.reset_mock()
                self.sql.execute.side_effect = [row(self.principal),
                    DBAPIError("CALL", {}, Exception("51130 requires assigned ticket"))]
                response = getattr(self.client, method)(endpoint, headers=self.headers(), json=payload)
                self.assertEqual(response.status_code, 403)
                self.sql.commit.assert_not_called()
                statement = str(self.sql.execute.call_args_list[-1].args[0])
                self.assertIn("usp_authorize_", statement)

    def test_json_array_rejected_before_database(self):
        self.assertEqual(self.client.post("/auth/mfa/enable", json=[1]).status_code, 400)
        self.sql.execute.assert_not_called()

    def test_notification_unknown_fields_do_not_mark_everything_read(self):
        response = self.client.post("/api/notifications/read", json={"user_id": 999}, headers=self.headers())
        self.assertEqual(response.status_code, 400)
        self.sql.commit.assert_not_called()

    def test_actor_mass_assignment_ignored(self):
        self.sql.execute.side_effect = [row(self.principal), MagicMock(), row({"id": 5})]
        response = self.client.post("/api/tickets/5/notes", headers=self.headers(),
                                   json={"note_text": "note", "author_user_id": 999, "role": auth.ROLE_ADMIN})
        self.assertEqual(response.status_code, 201)
        params = self.sql.execute.call_args_list[-1].args[1]
        self.assertEqual(params["author_user_id"], 2)

    def test_notification_object_id_is_scoped_to_authenticated_user(self):
        self.sql.execute.side_effect = [row(self.principal), row({"unread_count": 1})]
        response = self.client.post("/api/notifications/read", headers=self.headers(), json={"notification_id": 999})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.sql.execute.call_args.args[1], {"user_id": 2, "notification_id": 999})

    def test_legacy_mfa_setup_cannot_read_users_directly(self):
        self.sql.execute.side_effect = [row({**self.principal, "role_name": auth.ROLE_ADMIN}),
                                       row({"mfa_setup_secret_encrypted": None})]
        response = self.client.post("/auth/mfa/enable", headers=self.headers(), json={"code": "000000"})
        self.assertEqual(response.status_code, 409)
        self.assertIn("usp_get_own_mfa_state", str(self.sql.execute.call_args.args[0]))

    def test_public_account_request_cannot_request_admin_role(self):
        response = self.client.post("/auth/request-access", json={"username": "new",
            "full_name": "New User", "email": "test@example.invalid", "requested_role": auth.ROLE_ADMIN})
        self.assertEqual(response.status_code, 400)
        self.sql.execute.assert_not_called()

    def test_string_false_does_not_rotate_collector_key(self):
        self.sql.execute.return_value = row({**self.principal, "role_name": auth.ROLE_ADMIN})
        response = self.client.post("/api/collectors", headers=self.headers(),
                                   json={"node_id": 1, "rotate_key": "false"})
        self.assertEqual(response.status_code, 400)
        self.sql.commit.assert_not_called()

    def test_sql_injection_username_is_bound_parameter(self):
        self.sql.execute.return_value = row(None)
        probe = "' OR 1=1--"
        response = self.client.post("/auth/login", json={"username": probe, "password": "probe"})
        self.assertEqual(response.status_code, 401)
        statement, params = self.sql.execute.call_args.args
        self.assertNotIn(probe, str(statement))
        self.assertEqual(params["username"], probe)

    def test_login_rate_limit(self):
        self.sql.execute.return_value = row(None)
        for _ in range(10):
            self.client.post("/auth/login", json={"username": "probe", "password": "probe"})
        response = self.client.post("/auth/login", json={"username": "probe", "password": "probe"})
        self.assertEqual(response.status_code, 429)
        self.assertEqual(response.headers["Retry-After"], "60")

    def test_large_body_413(self):
        response = self.client.post("/auth/login", data=b"x" * (1024 * 1024 + 1),
                                    content_type="application/json")
        self.assertEqual(response.status_code, 413)
        self.assertTrue(response.is_json)
        self.assertEqual(response.get_json(), {"error": "Payload too large."})

    def test_auth_responses_are_not_cached(self):
        response = self.client.get("/auth/me")
        self.assertEqual(response.headers["Cache-Control"], "no-store")
        self.assertEqual(response.headers["X-Content-Type-Options"], "nosniff")
        self.assertEqual(response.headers["X-Frame-Options"], "DENY")
        self.assertEqual(response.headers["Referrer-Policy"], "no-referrer")


if __name__ == "__main__":
    unittest.main()
