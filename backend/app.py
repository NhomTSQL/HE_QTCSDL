import hashlib
import json
import os

from dotenv import load_dotenv
from flask import Flask, jsonify, request

from sqlalchemy import text
from sqlalchemy.engine import make_url
from sqlalchemy.exc import DBAPIError


from extensions import db, event_hub
from auth import auth_bp
from dashboard_api import api_bp


BACKEND_API_ERRORS = {
    "51050": (404, "Node not found."),
    "51051": (400, "collected_at is required."),
    "51052": (422, "Telemetry percentage is invalid."),
}


load_dotenv()

# Ma loi nghiep vu do usp_record_telemetry / usp_record_telemetry_batch / usp_upsert_container_telemetry THROW
TELEMETRY_ERRORS = {
    "51030": "metric_type khong ton tai",
    "51031": "unit khong khop voi metric_type",
    "51032": "batch telemetry payload khong hop le",
    "51062": "node khong ton tai",
    "51075": "trang thai container khong hop le",
}

CONTAINER_STATUSES = {"RUNNING", "STOPPED", "PAUSED", "RESTARTING", "EXITED"}


def hash_api_key(raw_key: str) -> str:
    return hashlib.sha256(raw_key.encode("utf-8")).hexdigest()


def find_node_id_by_api_key(raw_key: str):
    """Tra ve node_id cua agent ACTIVE co key khop qua Stored Procedure, hoac None."""
    result = db.session.execute(
        text("EXEC dbo.usp_authenticate_collector_agent @api_key_hash = :key_hash"),
        {"key_hash": hash_api_key(raw_key)},
    )
    row = result.first() if result.returns_rows else None
    db.session.commit()
    return row[0] if row and row[0] is not None else None


def create_app() -> Flask:
    app = Flask(__name__)
    database_url = os.environ.get("DATABASE_URL")
    if not database_url:
        raise RuntimeError("DATABASE_URL is required; configure SQL Server in .env")

    url = make_url(database_url)
    app.config["SQLALCHEMY_DATABASE_URI"] = url.render_as_string(hide_password=False)
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {
        "pool_pre_ping": True,
        "pool_size": 15,
        "max_overflow": 25,
        "pool_recycle": 1800,
    }
    db.init_app(app)
    app.config["JWT_SECRET_KEY"] = os.environ.get("JWT_SECRET_KEY")
    app.register_blueprint(auth_bp)
    app.register_blueprint(api_bp)

    @app.get("/health")
    def health_check():
        try:
            with db.engine.connect() as connection:
                connection.execute(text("EXEC dbo.usp_health_check"))
        except Exception:
            app.logger.exception("SQL Server health check failed")
            return jsonify({"status": "unhealthy", "database": "unavailable"}), 503
        return jsonify({"status": "healthy", "database": "connected"}), 200

    @app.post("/telemetry")
    def post_telemetry():
        # 1. Xac thuc truoc: thieu key hoac key sai/agent khong ACTIVE -> 401
        api_key = request.headers.get("X-API-Key", "")
        node_id = find_node_id_by_api_key(api_key) if api_key else None
        if node_id is None:
            return jsonify({"error": "API key khong hop le"}), 401

        # 2. Kiem tra body
        payload = request.get_json(silent=True)
        if not isinstance(payload, dict):
            return jsonify({"error": "Body phai la JSON object"}), 400

        metric_type = payload.get("metric_type")
        value = payload.get("value")
        unit = payload.get("unit")
        valid_body = (
            isinstance(metric_type, str) and metric_type
            and isinstance(value, (int, float)) and not isinstance(value, bool)
            and isinstance(unit, str) and unit
        )
        if not valid_body:
            return jsonify({
                "error": "Can 3 truong: metric_type (str), value (number), unit (str)"
            }), 400

        # 3. node_id (neu agent co gui) phai khop node cua key
        sent_node_id = payload.get("node_id")
        if sent_node_id is not None and sent_node_id != node_id:
            return jsonify({"error": "node_id khong khop voi API key"}), 403

        # 4. Goi stored procedure
        try:
            db.session.execute(
                text(
                    "EXEC dbo.usp_record_telemetry "
                    "@node_id = :node_id, @metric_type = :metric_type, "
                    "@value = :value, @unit = :unit"
                ),
                {"node_id": node_id, "metric_type": metric_type, "value": float(value), "unit": unit},
            )
            db.session.commit()
            event_hub.publish("telemetry", node_id=node_id, metric_type=metric_type)
        except DBAPIError as exc:
            db.session.rollback()
            detail = str(exc.orig)
            for code, message in TELEMETRY_ERRORS.items():
                if code in detail:
                    return jsonify({"error": "Telemetry khong hop le", "detail": message}), 422
            app.logger.exception("usp_record_telemetry failed")
            return jsonify({"error": "Loi may chu"}), 500

        return jsonify({"status": "recorded", "node_id": node_id}), 201

    @app.post("/telemetry/batch")
    def post_telemetry_batch():
        api_key = request.headers.get("X-API-Key", "")
        node_id = find_node_id_by_api_key(api_key) if api_key else None
        if node_id is None:
            return jsonify({"error": "API key khong hop le"}), 401

        payload = request.get_json(silent=True)
        if isinstance(payload, dict) and isinstance(payload.get("metrics"), list):
            items = payload["metrics"]
        elif isinstance(payload, list):
            items = payload
        else:
            return jsonify({"error": "Body phai la danh sach metrics hoac {\"metrics\": [...]}"}), 400

        if not items or len(items) > 500:
            return jsonify({"error": "So luong metrics trong batch phai tu 1 den 500"}), 400

        normalized = []
        for item in items:
            if not isinstance(item, dict):
                return jsonify({"error": "Moi metric phai la JSON object"}), 400
            sent_node_id = item.get("node_id")
            if sent_node_id is not None and sent_node_id != node_id:
                return jsonify({"error": "node_id khong khop voi API key"}), 403
            m_type = item.get("metric_type")
            val = item.get("value")
            unit = item.get("unit")
            ts = item.get("timestamp")
            valid_item = (
                isinstance(m_type, str) and bool(m_type)
                and isinstance(val, (int, float)) and not isinstance(val, bool)
                and isinstance(unit, str) and bool(unit)
                and (ts is None or isinstance(ts, str))
            )
            if not valid_item:
                return jsonify({
                    "error": "Moi metric can metric_type (str), value (number), unit (str)"
                }), 400
            entry = {"metric_type": m_type, "value": float(val), "unit": unit}
            if ts:
                entry["timestamp"] = ts
            normalized.append(entry)

        try:
            res = db.session.execute(
                text("EXEC dbo.usp_record_telemetry_batch @node_id = :node_id, @metrics_json = :metrics_json"),
                {"node_id": node_id, "metrics_json": json.dumps(normalized)},
            )
            row = res.first() if res.returns_rows else None
            recorded_count = int(row[0]) if row else len(normalized)
            db.session.commit()
            event_hub.publish("telemetry_batch", node_id=node_id, count=recorded_count)
        except DBAPIError as exc:
            db.session.rollback()
            detail = str(exc.orig)
            for code, message in TELEMETRY_ERRORS.items():
                if code in detail:
                    return jsonify({"error": "Batch telemetry khong hop le", "detail": message}), 422
            app.logger.exception("usp_record_telemetry_batch failed")
            return jsonify({"error": "Loi may chu"}), 500

        return jsonify({"status": "recorded", "node_id": node_id, "count": recorded_count}), 201

    @app.post("/telemetry/containers")
    def post_container_telemetry():
        api_key = request.headers.get("X-API-Key", "")
        node_id = find_node_id_by_api_key(api_key) if api_key else None
        if node_id is None:
            return jsonify({"error": "API key khong hop le"}), 401

        payload = request.get_json(silent=True)
        if isinstance(payload, dict) and isinstance(payload.get("containers"), list):
            items = payload["containers"]
        elif isinstance(payload, list):
            items = payload
        elif isinstance(payload, dict):
            items = [payload]
        else:
            return jsonify({"error": "Body phai la JSON object hoac danh sach containers"}), 400

        if not items:
            return jsonify({"error": "Danh sach containers rong"}), 400

        normalized = []
        for item in items:
            if not isinstance(item, dict):
                return jsonify({"error": "Moi container phai la JSON object"}), 400
            sent_node_id = item.get("node_id")
            if sent_node_id is not None and sent_node_id != node_id:
                return jsonify({"error": "node_id khong khop voi API key"}), 403
            cid = item.get("container_id")
            name = item.get("name")
            image = item.get("image")
            status = item.get("status", "RUNNING")
            cpu = item.get("cpu_usage_percent", 0.0)
            mem = item.get("memory_usage_mb", 0.0)
            restarts = item.get("restarted_count", 0)
            valid_item = (
                isinstance(cid, str) and bool(cid.strip())
                and isinstance(name, str) and bool(name.strip())
                and isinstance(image, str) and bool(image.strip())
                and isinstance(status, str) and status in CONTAINER_STATUSES
                and isinstance(cpu, (int, float)) and not isinstance(cpu, bool)
                and isinstance(mem, (int, float)) and not isinstance(mem, bool)
                and isinstance(restarts, int) and not isinstance(restarts, bool) and restarts >= 0
            )
            if not valid_item:
                return jsonify({"error": "Thieu hoac sai truong thong tin container"}), 400
            normalized.append({
                "node_id": node_id,
                "container_id": cid.strip()[:100],
                "name": name.strip()[:100],
                "image": image.strip()[:255],
                "status": status,
                "cpu_usage_percent": float(cpu),
                "memory_usage_mb": float(mem),
                "restarted_count": restarts,
            })

        try:
            for item in normalized:
                db.session.execute(
                    text(
                        "EXEC dbo.usp_upsert_container_telemetry "
                        "@node_id = :node_id, @container_id = :container_id, "
                        "@name = :name, @image = :image, @status = :status, "
                        "@cpu_usage_percent = :cpu_usage_percent, "
                        "@memory_usage_mb = :memory_usage_mb, "
                        "@restarted_count = :restarted_count"
                    ),
                    item,
                )
            db.session.commit()
            event_hub.publish("containers", node_id=node_id, count=len(normalized))
        except DBAPIError as exc:
            db.session.rollback()
            detail = str(exc.orig)
            for code, message in TELEMETRY_ERRORS.items():
                if code in detail:
                    return jsonify({"error": "Container telemetry khong hop le", "detail": message}), 422
            app.logger.exception("usp_upsert_container_telemetry failed")
            return jsonify({"error": "Loi may chu"}), 500

        return jsonify({"status": "recorded", "node_id": node_id, "count": len(normalized)}), 201

    return app


if __name__ == "__main__":
    create_app().run(host="0.0.0.0", port=int(os.environ.get("PORT", "5000")), debug=True)