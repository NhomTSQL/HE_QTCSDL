import os
import unittest

from sqlalchemy import text

from app import create_app, db

# Cung bien moi truong voi test_auth_api.py; khong luu mat khau trong repo.
DEV_PASSWORD = os.environ.get("AR_IMMS_DEV_PASSWORD")


@unittest.skipUnless(DEV_PASSWORD, "Dat bien moi truong AR_IMMS_DEV_PASSWORD de chay test dashboard API")
class DashboardApiTest(unittest.TestCase):
    """Integration test cho /api/* — can DB da chay scripts 17, 19, 20."""

    @classmethod
    def setUpClass(cls):
        cls.app = create_app()
        cls.client = cls.app.test_client()
        cls.tokens = {}
        cls.user_ids = {}
        for username in ("admin", "operator", "technician"):
            resp = cls.client.post("/auth/login", json={"username": username, "password": DEV_PASSWORD})
            assert resp.status_code == 200, f"Dang nhap {username} that bai: {resp.status_code}"
            data = resp.get_json()
            cls.tokens[username] = data["access_token"]
            cls.user_ids[username] = data["user"]["id"]

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
        self.assertEqual(resp.status_code, 400)

    def test_marker_lookup_returns_node_and_containers(self):
        headers = self._bearer(self.tokens["technician"])
        resp = self.client.get("/api/markers/NODE-01", headers=headers)
        self.assertEqual(resp.status_code, 200)
        body = resp.get_json()
        self.assertEqual(body["node"]["node_id"], 1)
        self.assertGreaterEqual(len(body["containers"]), 1)

        resp_q = self.client.get("/api/markers/lookup?code=arimms://node/NODE-01", headers=headers)
        self.assertEqual(resp_q.status_code, 200)
        self.assertEqual(resp_q.get_json()["node"]["node_id"], 1)

        self.assertEqual(self.client.get("/api/markers/UNKNOWN-XYZ-999", headers=headers).status_code, 404)

    def test_thresholds_assets_and_summary_endpoints(self):
        tech_headers = self._bearer(self.tokens["technician"])
        op_headers = self._bearer(self.tokens["operator"])

        th = self.client.get("/api/thresholds", headers=tech_headers)
        self.assertEqual(th.status_code, 200)
        self.assertGreaterEqual(len(th.get_json()), 4)

        self.assertEqual(
            self.client.put(
                "/api/thresholds/1",
                json={"warning_threshold": 75, "critical_threshold": 90, "duration_seconds": 30, "is_active": True},
                headers=tech_headers,
            ).status_code,
            403,
        )
        self.assertEqual(
            self.client.put(
                "/api/thresholds/1",
                json={"warning_threshold": 95, "critical_threshold": 90, "duration_seconds": 30, "is_active": True},
                headers=op_headers,
            ).status_code,
            400,
        )

        assets = self.client.get("/api/assets", headers=tech_headers)
        self.assertEqual(assets.status_code, 200)
        self.assertGreaterEqual(len(assets.get_json()), 4)

        summary = self.client.get("/api/summary", headers=tech_headers)
        self.assertEqual(summary.status_code, 200)
        data = summary.get_json()
        self.assertIn("current_pue", data["summary"])
        self.assertIn("avg_mttr_minutes", data["summary"])
        self.assertGreaterEqual(len(data["racks"]), 2)

        self.assertEqual(self.client.get("/api/racks", headers=tech_headers).status_code, 200)
        self.assertEqual(self.client.get("/api/containers", headers=tech_headers).status_code, 200)
        self.assertEqual(self.client.get("/api/telemetry/history?node_id=1", headers=tech_headers).status_code, 200)
        self.assertEqual(self.client.get("/api/maintenance", headers=tech_headers).status_code, 200)

    def test_admin_rbac_for_users_and_audit_logs(self):
        for path in ("/api/users", "/api/audit-logs"):
            self.assertEqual(self.client.get(path, headers=self._bearer(self.tokens["technician"])).status_code, 403)
            self.assertEqual(self.client.get(path, headers=self._bearer(self.tokens["operator"])).status_code, 403)
            resp = self.client.get(path, headers=self._bearer(self.tokens["admin"]))
            self.assertEqual(resp.status_code, 200)
            self.assertIsInstance(resp.get_json(), list)

    def test_full_technician_ticket_workflow(self):
        op_headers = self._bearer(self.tokens["operator"])
        tech_headers = self._bearer(self.tokens["technician"])

        created = self.client.post(
            "/api/tickets",
            json={"node_id": 1, "title": "Automated workflow integration check", "description": "Check cooling fan", "priority": "HIGH"},
            headers=op_headers,
        )
        self.assertEqual(created.status_code, 201)
        ticket_id = created.get_json()["id"]

        try:
            assigned = self.client.patch(
                f"/api/tickets/{ticket_id}/assign",
                json={"assigned_to_user_id": self.user_ids["technician"]},
                headers=op_headers,
            )
            self.assertEqual(assigned.status_code, 200)
            self.assertEqual(assigned.get_json()["assigned_to_username"], "technician")

            started = self.client.patch(
                f"/api/tickets/{ticket_id}/status",
                json={"status": "IN_PROGRESS"},
                headers=tech_headers,
            )
            self.assertEqual(started.status_code, 200)

            # Technician khong duoc tu dong dong ticket sang CLOSED
            forbidden_close = self.client.patch(
                f"/api/tickets/{ticket_id}/status",
                json={"status": "CLOSED"},
                headers=tech_headers,
            )
            self.assertEqual(forbidden_close.status_code, 403)

            note_resp = self.client.post(
                f"/api/tickets/{ticket_id}/notes",
                json={"note_text": "Verified airflow and cleaned heatsink dust."},
                headers=tech_headers,
            )
            self.assertEqual(note_resp.status_code, 201)
            notes = self.client.get(f"/api/tickets/{ticket_id}/notes", headers=tech_headers)
            self.assertEqual(notes.status_code, 200)
            self.assertGreaterEqual(len(notes.get_json()), 1)

            closure = self.client.post(
                f"/api/tickets/{ticket_id}/closure-request",
                json={
                    "summary": "Cooling fan restored",
                    "resolution_details": "Cleaned fan assembly and verified thermal drop.",
                    "maintenance_type": "CORRECTIVE",
                },
                headers=tech_headers,
            )
            self.assertEqual(closure.status_code, 201)

            approved = self.client.post(
                f"/api/tickets/{ticket_id}/closure-review",
                json={"decision": "APPROVED"},
                headers=op_headers,
            )
            self.assertEqual(approved.status_code, 200)
            self.assertEqual(approved.get_json()["ticket_status"], "CLOSED")
        finally:
            with self.app.app_context():
                db.session.execute(text("DELETE FROM dbo.maintenance_histories WHERE ticket_id = :tid"), {"tid": ticket_id})
                db.session.execute(text("DELETE FROM dbo.ticket_closure_requests WHERE ticket_id = :tid"), {"tid": ticket_id})
                db.session.execute(text("DELETE FROM dbo.ticket_notes WHERE ticket_id = :tid"), {"tid": ticket_id})
                db.session.execute(text("DELETE FROM dbo.notifications WHERE title LIKE :pat"), {"pat": f"%#{ticket_id}"})
                db.session.execute(text("DELETE FROM dbo.tickets WHERE id = :tid"), {"tid": ticket_id})
                db.session.commit()

    def test_hierarchy_collectors_notifications_and_stream(self):
        tech_headers = self._bearer(self.tokens["technician"])
        op_headers = self._bearer(self.tokens["operator"])

        self.assertEqual(self.client.get("/api/stream?once=1").status_code, 401)
        stream_resp = self.client.get(f"/api/stream?once=1&token={self.tokens['technician']}")
        self.assertEqual(stream_resp.status_code, 200)
        self.assertIn("seq", stream_resp.get_json())

        for level in ("SITE", "ROOM", "RACK", "NODE"):
            r = self.client.get(f"/api/reports/hierarchy?group_by={level}&hours=24", headers=tech_headers)
            self.assertEqual(r.status_code, 200)
            self.assertGreaterEqual(len(r.get_json()), 1)

        self.assertEqual(self.client.get("/api/hierarchy", headers=tech_headers).status_code, 200)
        cols = self.client.get("/api/collectors", headers=tech_headers)
        self.assertEqual(cols.status_code, 200)
        self.assertGreaterEqual(len(cols.get_json()), 1)

        notifs = self.client.get("/api/notifications", headers=tech_headers)
        self.assertEqual(notifs.status_code, 200)
        self.assertIsInstance(notifs.get_json(), list)
        mark = self.client.post("/api/notifications/read", json={"notification_id": 999999}, headers=tech_headers)
        self.assertEqual(mark.status_code, 200)
        self.assertIn("unread_count", mark.get_json())

        # PUT /api/nodes/1 validation + update + restore
        with self.app.app_context():
            orig = db.session.execute(
                text("SELECT rack_id, name, hostname, ip_address, mac_address, rack_position_u, power_consumption_watts, status FROM dbo.nodes WHERE id = 1")
            ).mappings().first()
        try:
            upd = self.client.put(
                "/api/nodes/1",
                json={
                    "rack_id": orig["rack_id"],
                    "name": orig["name"],
                    "hostname": orig["hostname"],
                    "ip_address": orig["ip_address"],
                    "mac_address": orig["mac_address"],
                    "rack_position_u": orig["rack_position_u"],
                    "power_consumption_watts": orig["power_consumption_watts"],
                    "status": "MAINTENANCE",
                },
                headers=op_headers,
            )
            self.assertEqual(upd.status_code, 200)
            self.assertEqual(upd.get_json()["status"], "MAINTENANCE")
        finally:
            with self.app.app_context():
                db.session.execute(
                    text("UPDATE dbo.nodes SET status = :st WHERE id = 1"),
                    {"st": orig["status"]},
                )
                db.session.commit()

    def test_warning_alert_generation_and_lifecycle(self):
        op_headers = self._bearer(self.tokens["operator"])
        with self.app.app_context():
            max_tm_id = db.session.execute(text("SELECT COALESCE(MAX(id), 0) FROM dbo.telemetry_metrics")).scalar()
            orig_status = db.session.execute(text("SELECT status FROM dbo.nodes WHERE id = 1")).scalar()

        created_alert_id = None
        try:
            ing = self.client.post(
                "/telemetry",
                json={"node_id": 1, "metric_type": "cpu_usage_percent", "value": 85.0, "unit": "%"},
                headers={"X-API-Key": "demo-node-key-001"},
            )
            self.assertEqual(ing.status_code, 201)

            alerts_resp = self.client.get("/api/alerts?status=OPEN", headers=op_headers)
            self.assertEqual(alerts_resp.status_code, 200)
            matched = [a for a in alerts_resp.get_json() if a["node_id"] == 1 and a["alert_type"] == "cpu_usage_percent_OVERLOAD"]
            self.assertGreaterEqual(len(matched), 1)
            self.assertEqual(matched[0]["severity"], "WARNING")
            created_alert_id = matched[0]["id"]

            res_resp = self.client.patch(
                f"/api/alerts/{created_alert_id}/status",
                json={"status": "RESOLVED"},
                headers=op_headers,
            )
            self.assertEqual(res_resp.status_code, 200)
            self.assertEqual(res_resp.get_json()["status"], "RESOLVED")

            cls_resp = self.client.patch(
                f"/api/alerts/{created_alert_id}/status",
                json={"status": "CLOSED"},
                headers=op_headers,
            )
            self.assertEqual(cls_resp.status_code, 200)
            self.assertEqual(cls_resp.get_json()["status"], "CLOSED")
        finally:
            with self.app.app_context():
                if created_alert_id is not None:
                    db.session.execute(text("DELETE FROM dbo.alerts WHERE id = :aid"), {"aid": created_alert_id})
                db.session.execute(text("DELETE FROM dbo.telemetry_metrics WHERE id > :mid"), {"mid": max_tm_id})
                db.session.execute(text("UPDATE dbo.nodes SET status = :st WHERE id = 1"), {"st": orig_status})
                db.session.commit()

    def test_pagination_on_alerts_tickets_and_audit_logs(self):
        op_headers = self._bearer(self.tokens["operator"])
        admin_token = self.tokens.get("admin") or self.tokens.get("administrator")
        admin_headers = self._bearer(admin_token)

        for path, hdrs in [
            ("/api/alerts?status=OPEN,ACKNOWLEDGED,RESOLVED,CLOSED", op_headers),
            ("/api/tickets", op_headers),
            ("/api/audit-logs", admin_headers),
        ]:
            sep = "&" if "?" in path else "?"
            full_resp = self.client.get(f"{path}{sep}limit=100&offset=0", headers=hdrs)
            self.assertEqual(full_resp.status_code, 200, path)
            rows = full_resp.get_json()
            self.assertIsInstance(rows, list)
            if len(rows) >= 2:
                p0 = self.client.get(f"{path}{sep}limit=1&offset=0", headers=hdrs)
                p1 = self.client.get(f"{path}{sep}limit=1&offset=1", headers=hdrs)
                self.assertEqual(p0.status_code, 200)
                self.assertEqual(p1.status_code, 200)
                self.assertEqual(len(p0.get_json()), 1)
                self.assertEqual(len(p1.get_json()), 1)
                self.assertEqual(p0.get_json()[0]["id"], rows[0]["id"])
                self.assertEqual(p1.get_json()[0]["id"], rows[1]["id"])

        bad = self.client.get("/api/alerts?offset=-1", headers=op_headers)
        self.assertEqual(bad.status_code, 400)


if __name__ == "__main__":
    unittest.main()
