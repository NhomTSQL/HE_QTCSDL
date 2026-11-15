import hashlib
import os

from dotenv import load_dotenv
from flask import Flask, jsonify, request

from sqlalchemy import text
from sqlalchemy.engine import make_url
from sqlalchemy.exc import DBAPIError


from extensions import db
from auth import auth_bp


load_dotenv()

# Ma loi nghiep vu do usp_record_telemetry THROW (xem database/04_procedures_triggers_views.sql)
TELEMETRY_ERRORS = {
    "51030": "metric_type khong ton tai",
    "51031": "unit khong khop voi metric_type",
}


def hash_api_key(raw_key: str) -> str:
    return hashlib.sha256(raw_key.encode("utf-8")).hexdigest()


def find_node_id_by_api_key(raw_key: str):
    """Tra ve node_id cua agent ACTIVE co key khop, hoac None."""
    row = db.session.execute(
        text(
            "SELECT TOP 1 node_id FROM data_collector_agents "
            "WHERE api_key_hash = :key_hash AND status = 'ACTIVE'"
        ),
        {"key_hash": hash_api_key(raw_key)},
    ).first()
    return row[0] if row else None


def create_app() -> Flask:
    app = Flask(__name__)
    database_url = os.environ.get("DATABASE_URL")
    if not database_url:
        raise RuntimeError("DATABASE_URL is required; configure SQL Server in .env")

    url = make_url(database_url)
    app.config["SQLALCHEMY_DATABASE_URI"] = url.render_as_string(hide_password=False)
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {"pool_pre_ping": True}
    db.init_app(app)
    app.config["JWT_SECRET_KEY"] = os.environ.get("JWT_SECRET_KEY")
    app.register_blueprint(auth_bp)

    @app.get("/health")
    def health_check():
        try:
            with db.engine.connect() as connection:
                connection.execute(text("SELECT 1"))
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
        except DBAPIError as exc:
            db.session.rollback()
            detail = str(exc.orig)
            for code, message in TELEMETRY_ERRORS.items():
                if code in detail:
                    return jsonify({"error": "Telemetry khong hop le", "detail": message}), 422
            app.logger.exception("usp_record_telemetry failed")
            return jsonify({"error": "Loi may chu"}), 500

        return jsonify({"status": "recorded", "node_id": node_id}), 201

    return app


if __name__ == "__main__":
    create_app().run(host="0.0.0.0", port=int(os.environ.get("PORT", "5000")), debug=True)