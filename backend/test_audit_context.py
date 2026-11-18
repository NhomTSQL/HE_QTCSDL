import os
import unittest
import uuid

from sqlalchemy import text

from app import create_app, db

# Mat khau dev dat bang scripts/set_dev_passwords.py (qua bien moi truong, khong luu trong repo)
DEV_PASSWORD = os.environ.get("AR_IMMS_DEV_PASSWORD")


@unittest.skipUnless(DEV_PASSWORD, "Dat bien moi truong AR_IMMS_DEV_PASSWORD de chay test audit")
class AuditContextTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = create_app()
        cls.client = cls.app.test_client()
        cls.headers = {}
        for username in ("admin", "operator"):
            resp = cls.client.post("/auth/login", json={"username": username, "password": DEV_PASSWORD})
            assert resp.status_code == 200, f"Dang nhap {username} that bai: {resp.status_code}"
            cls.headers[username] = {"Authorization": "Bearer " + resp.get_json()["access_token"]}
        with cls.app.app_context():
            cls.node_id = db.session.execute(text("SELECT MIN(id) FROM nodes")).scalar()

    def _new_open_alert(self):
        alert_type = "TEST_AUDIT_" + uuid.uuid4().hex[:8]
        with self.app.app_context():
            db.session.execute(
                text(
                    "INSERT INTO alerts (node_id, alert_type, severity, status, message, metric_value, triggered_at) "
                    "VALUES (:node_id, :alert_type, N'CRITICAL', N'OPEN', N'test audit context', 0.0, SYSUTCDATETIME())"
                ),
                {"node_id": self.node_id, "alert_type": alert_type},
            )
            db.session.commit()
            return db.session.execute(
                text("SELECT id FROM alerts WHERE alert_type = :alert_type"), {"alert_type": alert_type}
            ).scalar()

    def _usernames(self, action, target_id):
        with self.app.app_context():
            rows = db.session.execute(
                text(
                    "SELECT username FROM audit_logs "
                    "WHERE action = :action AND target_id = :target_id ORDER BY id"
                ),
                {"action": action, "target_id": str(target_id)},
            ).all()
        return [row[0] for row in rows]

    def _new_ticket(self, as_user="admin"):
        resp = self.client.post(
            "/api/tickets",
            json={"node_id": self.node_id, "title": "TEST audit context", "priority": "LOW"},
            headers=self.headers[as_user],
        )
        self.assertEqual(resp.status_code, 201)
        return resp.get_json()["id"]

    def _patch_status(self, ticket_id, status, as_user):
        resp = self.client.patch(
            f"/api/tickets/{ticket_id}/status", json={"status": status}, headers=self.headers[as_user]
        )
        self.assertEqual(resp.status_code, 200)

    def test_ack_records_the_user_who_acknowledged(self):
        alert_a, alert_b = self._new_open_alert(), self._new_open_alert()
        self.assertEqual(self.client.post(f"/api/alerts/{alert_a}/ack", headers=self.headers["admin"]).status_code, 200)
        self.assertEqual(self.client.post(f"/api/alerts/{alert_b}/ack", headers=self.headers["operator"]).status_code, 200)
        self.assertEqual(self._usernames("ALERT_ACKNOWLEDGED", alert_a), ["admin"])
        self.assertEqual(self._usernames("ALERT_ACKNOWLEDGED", alert_b), ["operator"])

    def test_ticket_status_changes_record_each_user(self):
        ticket_id = self._new_ticket("admin")
        self._patch_status(ticket_id, "IN_PROGRESS", "admin")
        self._patch_status(ticket_id, "PENDING_CLOSURE", "operator")
        self.assertEqual(self._usernames("TICKET_STATUS_CHANGED", ticket_id), ["admin", "operator"])

    def test_context_does_not_leak_to_later_connections_without_user(self):
        ticket_id = self._new_ticket("admin")
        self._patch_status(ticket_id, "IN_PROGRESS", "operator")
        # Cap nhat truc tiep (khong qua request/nguoi dung): phai ghi SYSTEM, khong duoc ghi nhan nguoi cu
        with self.app.app_context():
            db.session.execute(
                text("UPDATE tickets SET status = N'PENDING_CLOSURE' WHERE id = :id"), {"id": ticket_id}
            )
            db.session.commit()
        self.assertEqual(self._usernames("TICKET_STATUS_CHANGED", ticket_id), ["operator", "SYSTEM"])


if __name__ == "__main__":
    unittest.main()