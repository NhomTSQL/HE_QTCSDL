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


if __name__ == "__main__":
    unittest.main()