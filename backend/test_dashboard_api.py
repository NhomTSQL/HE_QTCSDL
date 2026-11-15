import os
import unittest

from app import create_app

# Cung bien moi truong voi test_auth_api.py; khong luu mat khau trong repo.
DEV_PASSWORD = os.environ.get("AR_IMMS_DEV_PASSWORD")


@unittest.skipUnless(DEV_PASSWORD, "Dat bien moi truong AR_IMMS_DEV_PASSWORD de chay test dashboard API")
class DashboardApiTest(unittest.TestCase):
    """Smoke test cho /api/* — can DB da chay 17_dashboard_api_procedures.sql.

    Test chi doc du lieu va kiem tra validation, khong tao/sua ticket that.
    """

    @classmethod
    def setUpClass(cls):
        cls.app = create_app()
        cls.client = cls.app.test_client()
        cls.tokens = {}
        for username in ("admin", "operator", "technician"):
            resp = cls.client.post("/auth/login", json={"username": username, "password": DEV_PASSWORD})
            assert resp.status_code == 200, f"Dang nhap {username} that bai: {resp.status_code}"
            cls.tokens[username] = resp.get_json()["access_token"]

    @staticmethod
    def _bearer(token):
        return {"Authorization": f"Bearer {token}"}

    def test_nodes_requires_token(self):
        self.assertEqual(self.client.get("/api/nodes").status_code, 401)

    def test_technician_can_read_nodes(self):
        resp = self.client.get("/api/nodes", headers=self._bearer(self.tokens["technician"]))
        self.assertEqual(resp.status_code, 200)
        self.assertIsInstance(resp.get_json(), list)

    def test_alerts_reject_invalid_status_filter(self):
        resp = self.client.get(
            "/api/alerts?status=OPEN;DROP", headers=self._bearer(self.tokens["admin"])
        )
        self.assertEqual(resp.status_code, 400)

    def test_technician_cannot_create_ticket(self):
        resp = self.client.post(
            "/api/tickets",
            json={"node_id": 1, "title": "Test ticket"},
            headers=self._bearer(self.tokens["technician"]),
        )
        self.assertEqual(resp.status_code, 403)

    def test_create_ticket_validation(self):
        headers = self._bearer(self.tokens["admin"])
        cases = [
            {"title": "Thieu node_id"},
            {"node_id": 0, "title": "node_id sai"},
            {"node_id": 1, "title": ""},
            {"node_id": 1, "title": "x" * 201},
            {"node_id": 1, "title": "Sai priority", "priority": "NORMAL"},
        ]
        for body in cases:
            with self.subTest(body=body):
                self.assertEqual(self.client.post("/api/tickets", json=body, headers=headers).status_code, 400)

    def test_ticket_status_rejects_invalid_state(self):
        resp = self.client.patch(
            "/api/tickets/999999/status",
            json={"status": "DONE"},
            headers=self._bearer(self.tokens["admin"]),
        )
        # 51067 (invalid state) duoc kiem tra truoc 51065 (khong tim thay ticket).
        self.assertEqual(resp.status_code, 400)


if __name__ == "__main__":
    unittest.main()
