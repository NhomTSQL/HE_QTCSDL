import unittest

from sqlalchemy import text

from app import create_app, db

DEMO_KEY = "demo-node-key-001"  # khop voi database/08_dev_node_api_key.sql


class TelemetryApiTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = create_app()
        cls.client = cls.app.test_client()
        with cls.app.app_context():
            cls.node_id = db.session.execute(
                text("SELECT node_id FROM data_collector_agents WHERE agent_version = N'dev-demo'")
            ).scalar()
        if cls.node_id is None:
            raise RuntimeError("Chua co agent demo. Chay database/08_dev_node_api_key.sql truoc.")

    def _count(self):
        with self.app.app_context():
            return db.session.execute(
                text("SELECT COUNT(*) FROM telemetry_metrics WHERE node_id = :n"),
                {"n": self.node_id},
            ).scalar()

    @staticmethod
    def _payload(**override):
        data = {"metric_type": "cpu_usage_percent", "value": 42.5, "unit": "%"}
        data.update(override)
        return data

    def test_valid_key_inserts_row(self):
        before = self._count()
        resp = self.client.post("/telemetry", json=self._payload(), headers={"X-API-Key": DEMO_KEY})
        self.assertEqual(resp.status_code, 201)
        self.assertEqual(resp.get_json()["node_id"], self.node_id)
        self.assertEqual(self._count(), before + 1)

    def test_wrong_key_rejected(self):
        before = self._count()
        resp = self.client.post("/telemetry", json=self._payload(), headers={"X-API-Key": "sai-key"})
        self.assertEqual(resp.status_code, 401)
        self.assertEqual(self._count(), before)

    def test_missing_key_rejected(self):
        resp = self.client.post("/telemetry", json=self._payload())
        self.assertEqual(resp.status_code, 401)

    def test_mismatched_node_id_rejected(self):
        before = self._count()
        resp = self.client.post(
            "/telemetry",
            json=self._payload(node_id=self.node_id + 999999),
            headers={"X-API-Key": DEMO_KEY},
        )
        self.assertEqual(resp.status_code, 403)
        self.assertEqual(self._count(), before)

    def test_bad_unit_rejected_without_writing(self):
        before = self._count()
        resp = self.client.post("/telemetry", json=self._payload(unit="XYZ"), headers={"X-API-Key": DEMO_KEY})
        self.assertEqual(resp.status_code, 422)
        self.assertEqual(self._count(), before)

    def test_bad_body_rejected(self):
        resp = self.client.post("/telemetry", json={"value": 1}, headers={"X-API-Key": DEMO_KEY})
        self.assertEqual(resp.status_code, 400)

    def test_health_endpoint_via_sp(self):
        resp = self.client.get("/health")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.get_json(), {"status": "healthy", "database": "connected"})

    def test_container_telemetry_ingest(self):
        self.assertEqual(self.client.post("/telemetry/containers", json=[]).status_code, 401)
        resp = self.client.post(
            "/telemetry/containers",
            json={
                "node_id": self.node_id,
                "container_id": "cnt-alpha01-flask",
                "name": "ar-imms-flask-api",
                "image": "python:3.12-slim",
                "status": "RUNNING",
                "cpu_usage_percent": 5.2,
                "memory_usage_mb": 220.0,
                "restarted_count": 0,
            },
            headers={"X-API-Key": DEMO_KEY},
        )
        self.assertEqual(resp.status_code, 201)
        self.assertEqual(resp.get_json()["count"], 1)

    def test_batch_telemetry_ingest_and_atomic_rollback(self):
        with self.app.app_context():
            max_tm_id = db.session.execute(
                text("SELECT COALESCE(MAX(id), 0) FROM dbo.telemetry_metrics")
            ).scalar()

        try:
            before = self._count()
            ok_resp = self.client.post(
                "/telemetry/batch",
                json={
                    "metrics": [
                        {"metric_type": "cpu_usage_percent", "value": 42.5, "unit": "%"},
                        {"metric_type": "memory_usage_percent", "value": 55.0, "unit": "%"},
                    ]
                },
                headers={"X-API-Key": DEMO_KEY},
            )
            self.assertEqual(ok_resp.status_code, 201)
            body = ok_resp.get_json()
            self.assertEqual(body["status"], "recorded")
            self.assertEqual(body["node_id"], self.node_id)
            self.assertEqual(body["count"], 2)
            self.assertEqual(self._count(), before + 2)

            with self.app.app_context():
                mem_snap = db.session.execute(
                    text(
                        "SELECT nlm.value FROM dbo.node_latest_metrics nlm "
                        "JOIN dbo.metric_types mt ON mt.id = nlm.metric_type_id "
                        "WHERE nlm.node_id = :n AND mt.code = N'memory_usage_percent'"
                    ),
                    {"n": self.node_id},
                ).scalar()
                self.assertEqual(float(mem_snap), 55.0)

            bad_resp = self.client.post(
                "/telemetry/batch",
                json=[
                    {"metric_type": "cpu_usage_percent", "value": 41.0, "unit": "%"},
                    {"metric_type": "cpu_usage_percent", "value": 42.0, "unit": "BAD_UNIT"},
                ],
                headers={"X-API-Key": DEMO_KEY},
            )
            self.assertEqual(bad_resp.status_code, 422)
            self.assertEqual(self._count(), before + 2)

            self.assertEqual(
                self.client.post("/telemetry/batch", json=[self._payload()], headers={"X-API-Key": "wrong-key"}).status_code,
                401,
            )
            self.assertEqual(
                self.client.post(
                    "/telemetry/batch",
                    json=[self._payload(node_id=self.node_id + 9999)],
                    headers={"X-API-Key": DEMO_KEY},
                ).status_code,
                403,
            )
        finally:
            with self.app.app_context():
                db.session.execute(text("DELETE FROM dbo.telemetry_metrics WHERE id > :mid"), {"mid": max_tm_id})
                db.session.commit()


if __name__ == "__main__":
    unittest.main()