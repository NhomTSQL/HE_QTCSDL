"""Dashboard REST endpoints backed only by SQL Server stored procedures."""
import datetime
import hashlib
import json
import secrets

import jwt
from flask import Blueprint, Response, current_app, g, jsonify, request, stream_with_context
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError
from werkzeug.security import generate_password_hash

from backend.api.auth import ROLE_ADMIN, ROLE_OPERATOR, ROLE_TECHNICIAN, require_roles, validate_session_token
from backend.core.extensions import db, event_hub
from backend.db.gateway import rows as _rows

api_bp = Blueprint("dashboard_api", __name__, url_prefix="/api")
_READ_ROLES = (ROLE_ADMIN, ROLE_OPERATOR, ROLE_TECHNICIAN)
_OPERATOR_ROLES = (ROLE_ADMIN, ROLE_OPERATOR)

TICKET_STATUSES = {"OPEN", "IN_PROGRESS", "PENDING_CLOSURE", "CLOSED"}
MAINTENANCE_TYPES = {"PREVENTIVE", "CORRECTIVE", "EMERGENCY", "INSPECTION"}
VALID_ROLES = {ROLE_ADMIN, ROLE_OPERATOR, ROLE_TECHNICIAN}

_PROCEDURE_ERROR_CODES = {
    "51050": (400, "Invalid password format or missing password."),
    "51060": (404, "Alert not found."),
    "51061": (409, "Alert is not open."),
    "51062": (404, "Node not found."),
    "51063": (400, "Invalid priority."),
    "51064": (404, "Alert not found."),
    "51065": (404, "Ticket not found."),
    "51066": (409, "Invalid ticket status transition."),
    "51067": (400, "Invalid ticket status."),
    "51070": (404, "Rack not found."),
    "51071": (404, "Marker or node not found."),
    "51072": (404, "Assignee user not found or inactive."),
    "51073": (409, "Invalid closure decision or no pending closure request."),
    "51074": (400, "Invalid alert threshold configuration."),
    "51075": (400, "Invalid container status."),
    "51076": (404, "Container not found."),
    "51077": (409, "Marker code already exists."),
    "51078": (400, "Invalid marker type or code."),
    "51079": (400, "Invalid maintenance type."),
    "51080": (400, "Invalid role name."),
    "51081": (409, "User not found or username/email already exists."),
    "51082": (400, "Invalid node status."),
    "51083": (400, "Invalid hierarchy entity_type."),
    "51084": (409, "Hierarchy code already exists."),
    "51085": (404, "Site not found."),
    "51086": (404, "Room not found."),
    "51087": (400, "group_by must be SITE, ROOM, RACK or NODE."),
    "51088": (400, "Invalid collector agent configuration."),
    "51090": (403, "Audit logs are immutable."),
    "51130": (403, "This operation requires an assigned ticket."),
}


def _authorize_ticket_write(ticket_id):
    db.session.execute(text("{CALL dbo.usp_authorize_ticket_write (:ticket_id, :actor_user_id)}"),
                       {"ticket_id": ticket_id, "actor_user_id": g.current_user["user_id"]})


def _positive_int(value):
    return not isinstance(value, bool) and isinstance(value, int) and value > 0


def _parse_optional_iso_datetime(value):
    if value is None or value == "":
        return None, True
    if not isinstance(value, str):
        return None, False
    cleaned = value.strip()
    if not cleaned:
        return None, True
    try:
        if cleaned.endswith("Z"):
            cleaned = cleaned[:-1]
        if len(cleaned) == 10:
            return datetime.datetime.fromisoformat(cleaned + "T00:00:00"), True
        return datetime.datetime.fromisoformat(cleaned), True
    except ValueError:
        return None, False


def _procedure_error(exc):
    db.session.rollback()
    message = str(exc.orig)
    for code, (status, detail) in _PROCEDURE_ERROR_CODES.items():
        if code in message:
            return jsonify({"error": detail}), status
    return jsonify({"error": "Database operation failed."}), 503


@api_bp.get("/stream")
def stream_events():
    secret = current_app.config.get("JWT_SECRET_KEY")
    if not secret:
        return jsonify({"error": "Server configuration error."}), 500
    scheme, _, hdr_token = request.headers.get("Authorization", "").partition(" ")
    token = hdr_token.strip() if scheme.lower() == "bearer" and hdr_token.strip() else request.args.get("token", "").strip()
    if not token:
        return jsonify({"error": "Missing token."}), 401
    try:
        _, claims = validate_session_token(token)
    except jwt.InvalidTokenError:
        return jsonify({"error": "Invalid or expired token."}), 401
    except DBAPIError:
        db.session.rollback()
        return jsonify({"error": "Authentication service unavailable."}), 503

    if request.args.get("once") == "1":
        seq, payload = event_hub.snapshot()
        return jsonify({"seq": seq, "event": payload})

    db.session.rollback()  # Release the DB read transaction before waiting on SSE.

    def generate():
        seq, payload = event_hub.snapshot()
        yield f"data: {json.dumps(payload)}\n\n"
        while True:
            next_seq, next_payload = event_hub.wait_next(seq, timeout=15.0)
            try:
                if datetime.datetime.now(datetime.timezone.utc).timestamp() >= claims["exp"]:
                    return
                validate_session_token(token)
                db.session.rollback()
            except (jwt.InvalidTokenError, DBAPIError):
                db.session.rollback()
                return
            if next_seq != seq:
                seq = next_seq
                yield f"data: {json.dumps(next_payload)}\n\n"
            else:
                yield ": keepalive\n\n"

    return Response(
        stream_with_context(generate()),
        mimetype="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@api_bp.get("/summary")
@require_roles(*_READ_ROLES)
def get_summary():
    raw_site_id = request.args.get("site_id", "1")
    try:
        site_id = int(raw_site_id)
    except ValueError:
        return jsonify({"error": "site_id must be an integer."}), 400
    try:
        summary_rows = _rows("EXEC dbo.usp_get_analytics_summary @site_id = :site_id", {"site_id": site_id})
        capacity_rows = _rows("EXEC dbo.usp_get_capacity_report")
        return jsonify({"summary": summary_rows[0] if summary_rows else {}, "racks": capacity_rows})
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.get("/telemetry/history")
@require_roles(*_READ_ROLES)
def get_telemetry_history():
    raw_node_id = request.args.get("node_id")
    if not raw_node_id or not raw_node_id.isdigit():
        return jsonify({"error": "node_id must be a positive integer."}), 400
    metric_type = request.args.get("metric_type", "cpu_usage_percent")
    if len(metric_type) > 50 or not metric_type.replace("_", "").isalnum():
        return jsonify({"error": "Invalid metric_type."}), 400
    raw_limit = request.args.get("limit", "40")
    try:
        limit = max(1, min(200, int(raw_limit)))
    except ValueError:
        return jsonify({"error": "limit must be an integer."}), 400
    try:
        rows = _rows(
            "{CALL dbo.usp_get_telemetry_history (:node_id, :metric_type, :limit)}",
            {"node_id": int(raw_node_id), "metric_type": metric_type, "limit": limit},
        )
        return jsonify(rows)
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.get("/racks")
@require_roles(*_READ_ROLES)
def list_racks():
    try:
        return jsonify(_rows("EXEC dbo.usp_list_racks"))
    except DBAPIError as exc:
        return _procedure_error(exc)


def _parse_pagination(default_limit: int = 100, max_limit: int = 500):
    raw_limit = request.args.get("limit", str(default_limit))
    raw_offset = request.args.get("offset", "0")
    try:
        limit = max(1, min(max_limit, int(raw_limit)))
    except ValueError:
        return None, None, (jsonify({"error": "limit must be an integer."}), 400)
    try:
        offset = int(raw_offset)
        if offset < 0:
            raise ValueError()
    except ValueError:
        return None, None, (jsonify({"error": "offset must be a non-negative integer."}), 400)
    return limit, offset, None


def _parse_optional_pos_int(arg_name: str):
    raw = request.args.get(arg_name)
    if raw is None or raw == "":
        return None, None
    try:
        val = int(raw)
        if val <= 0:
            raise ValueError()
        return val, None
    except ValueError:
        return None, (jsonify({"error": f"{arg_name} must be a positive integer."}), 400)


@api_bp.get("/nodes")
@require_roles(*_READ_ROLES)
def list_nodes():
    rack_id, err = _parse_optional_pos_int("rack_id")
    if err:
        return err
    limit, offset, err = _parse_pagination()
    if err:
        return err
    try:
        return jsonify(_rows(
            "{CALL dbo.usp_list_nodes_latest (:rack_id, :limit, :offset)}",
            {"rack_id": rack_id, "limit": limit, "offset": offset},
        ))
    except DBAPIError:
        db.session.rollback()
        return jsonify({"error": "Failed to list nodes."}), 503


@api_bp.post("/nodes")
@require_roles(*_OPERATOR_ROLES)
def register_node():
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return jsonify({"error": "Body must be a JSON object."}), 400

    rack_id = payload.get("rack_id")
    name = payload.get("name")
    hostname = payload.get("hostname")
    ip_address = payload.get("ip_address")
    mac_address = payload.get("mac_address")
    rack_position_u = payload.get("rack_position_u", 1)
    power_watts = payload.get("power_consumption_watts", 150.0)
    marker_code = payload.get("marker_code")
    raw_api_key = payload.get("api_key")

    if not _positive_int(rack_id):
        return jsonify({"error": "rack_id must be a positive integer."}), 400
    if not isinstance(name, str) or not name.strip() or len(name.strip()) > 100:
        return jsonify({"error": "name must be 1-100 characters."}), 400
    if not isinstance(hostname, str) or not hostname.strip() or len(hostname.strip()) > 100:
        return jsonify({"error": "hostname must be 1-100 characters."}), 400
    if not isinstance(ip_address, str) or not ip_address.strip() or len(ip_address.strip()) > 50:
        return jsonify({"error": "ip_address must be 1-50 characters."}), 400
    if mac_address is not None and (not isinstance(mac_address, str) or len(mac_address.strip()) > 50):
        return jsonify({"error": "mac_address must be <= 50 characters."}), 400
    if not _positive_int(rack_position_u):
        return jsonify({"error": "rack_position_u must be a positive integer."}), 400
    if isinstance(power_watts, bool) or not isinstance(power_watts, (int, float)) or power_watts <= 0:
        return jsonify({"error": "power_consumption_watts must be positive."}), 400
    if marker_code is not None and (not isinstance(marker_code, str) or len(marker_code.strip()) > 100):
        return jsonify({"error": "marker_code must be <= 100 characters."}), 400

    if raw_api_key is None or (isinstance(raw_api_key, str) and not raw_api_key.strip()):
        generated_key = f"arimms-{secrets.token_urlsafe(18)}"
    elif isinstance(raw_api_key, str):
        generated_key = raw_api_key.strip()
    else:
        return jsonify({"error": "api_key must be a string."}), 400

    api_key_hash = hashlib.sha256(generated_key.encode("utf-8")).hexdigest()
    clean_marker = marker_code.strip() if isinstance(marker_code, str) and marker_code.strip() else None

    try:
        rows = _rows(
            "{CALL dbo.usp_register_node (:rack_id, :name, :hostname, :ip_address, :mac_address, "
            ":rack_position_u, :power_watts, :marker_code, :api_key_hash, :actor_user_id)}",
            {
                "rack_id": rack_id,
                "name": name.strip(),
                "hostname": hostname.strip(),
                "ip_address": ip_address.strip(),
                "mac_address": mac_address.strip() if isinstance(mac_address, str) else None,
                "rack_position_u": rack_position_u,
                "power_watts": float(power_watts),
                "marker_code": clean_marker,
                "api_key_hash": api_key_hash,
                "actor_user_id": g.current_user["user_id"],
            },
        )
        db.session.commit()
        event_hub.publish("node_registered", node_id=rows[0]["id"])
        return jsonify({
            "id": rows[0]["id"],
            "api_key": generated_key,
            "marker_code": clean_marker,
        }), 201
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.put("/nodes/<int:node_id>")
@require_roles(*_OPERATOR_ROLES)
def update_node(node_id):
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return jsonify({"error": "Body must be a JSON object."}), 400
    rack_id = payload.get("rack_id")
    name = payload.get("name")
    hostname = payload.get("hostname")
    ip_address = payload.get("ip_address")
    mac_address = payload.get("mac_address")
    rack_position_u = payload.get("rack_position_u", 1)
    power_watts = payload.get("power_consumption_watts", 150.0)
    status = payload.get("status", "ONLINE")

    if not _positive_int(rack_id):
        return jsonify({"error": "rack_id must be a positive integer."}), 400
    if not isinstance(name, str) or not name.strip() or len(name.strip()) > 100:
        return jsonify({"error": "name must be 1-100 characters."}), 400
    if not isinstance(hostname, str) or not hostname.strip() or len(hostname.strip()) > 100:
        return jsonify({"error": "hostname must be 1-100 characters."}), 400
    if not isinstance(ip_address, str) or not ip_address.strip() or len(ip_address.strip()) > 50:
        return jsonify({"error": "ip_address must be 1-50 characters."}), 400
    if mac_address is not None and (not isinstance(mac_address, str) or len(mac_address.strip()) > 50):
        return jsonify({"error": "mac_address must be <= 50 characters."}), 400
    if not _positive_int(rack_position_u):
        return jsonify({"error": "rack_position_u must be a positive integer."}), 400
    if isinstance(power_watts, bool) or not isinstance(power_watts, (int, float)) or power_watts <= 0:
        return jsonify({"error": "power_consumption_watts must be positive."}), 400
    if not isinstance(status, str) or status not in {"ONLINE", "WARNING", "CRITICAL", "UNAVAILABLE", "MAINTENANCE"}:
        return jsonify({"error": "Invalid node status."}), 400

    try:
        rows = _rows(
            "{CALL dbo.usp_update_node (:node_id, :rack_id, :name, :hostname, :ip_address, "
            ":mac_address, :rack_position_u, :power_watts, :status, :actor_user_id)}",
            {
                "node_id": node_id,
                "rack_id": rack_id,
                "name": name.strip(),
                "hostname": hostname.strip(),
                "ip_address": ip_address.strip(),
                "mac_address": mac_address.strip() if isinstance(mac_address, str) else None,
                "rack_position_u": rack_position_u,
                "power_watts": float(power_watts),
                "status": status,
                "actor_user_id": g.current_user["user_id"],
            },
        )
        db.session.commit()
        event_hub.publish("node_updated", node_id=node_id)
        return jsonify(rows[0] if rows else {"id": node_id, "status": status})
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.get("/hierarchy")
@require_roles(*_READ_ROLES)
def get_hierarchy():
    try:
        sites_rooms = _rows("EXEC dbo.usp_list_sites_and_rooms")
        racks = _rows("EXEC dbo.usp_list_racks")
        return jsonify({"sites_rooms": sites_rooms, "racks": racks})
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.post("/hierarchy")
@require_roles(*_OPERATOR_ROLES)
def manage_hierarchy():
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return jsonify({"error": "Body must be a JSON object."}), 400
    entity_type = payload.get("entity_type")
    item_id = payload.get("id")
    parent_id = payload.get("parent_id")
    name = payload.get("name")
    code = payload.get("code")
    extra_text = payload.get("extra_text")
    unit_capacity = payload.get("unit_capacity", 42)
    power_capacity = payload.get("power_capacity_watts", 5000.0)

    if not isinstance(entity_type, str) or entity_type.upper() not in {"SITE", "ROOM", "RACK"}:
        return jsonify({"error": "entity_type must be SITE, ROOM or RACK."}), 400
    if item_id is not None and not _positive_int(item_id):
        return jsonify({"error": "id must be a positive integer."}), 400
    if entity_type.upper() in {"ROOM", "RACK"} and not _positive_int(parent_id):
        return jsonify({"error": "parent_id must be a positive integer."}), 400
    if not isinstance(name, str) or not name.strip() or len(name.strip()) > 100:
        return jsonify({"error": "name must be 1-100 characters."}), 400
    if not isinstance(code, str) or not code.strip() or len(code.strip()) > 50:
        return jsonify({"error": "code must be 1-50 characters."}), 400
    if extra_text is not None and not isinstance(extra_text, str):
        return jsonify({"error": "extra_text must be a string."}), 400
    if not _positive_int(unit_capacity):
        return jsonify({"error": "unit_capacity must be a positive integer."}), 400
    if isinstance(power_capacity, bool) or not isinstance(power_capacity, (int, float)) or power_capacity <= 0:
        return jsonify({"error": "power_capacity_watts must be positive."}), 400

    try:
        rows = _rows(
            "{CALL dbo.usp_manage_hierarchy (:entity_type, :id, :parent_id, :name, :code, "
            ":extra_text, :unit_capacity, :power_capacity, :actor_user_id)}",
            {
                "entity_type": entity_type.upper(),
                "id": item_id,
                "parent_id": parent_id,
                "name": name.strip(),
                "code": code.strip(),
                "extra_text": extra_text.strip() if isinstance(extra_text, str) else None,
                "unit_capacity": unit_capacity,
                "power_capacity": float(power_capacity),
                "actor_user_id": g.current_user["user_id"],
            },
        )
        db.session.commit()
        event_hub.publish("hierarchy_updated", entity_type=entity_type.upper())
        return jsonify(rows[0] if rows else {"entity_type": entity_type.upper(), "code": code.strip()}), 201 if item_id is None else 200
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.get("/containers")
@require_roles(*_READ_ROLES)
def list_containers():
    raw_node_id = request.args.get("node_id")
    node_id = None
    if raw_node_id is not None and raw_node_id != "":
        if not raw_node_id.isdigit():
            return jsonify({"error": "node_id must be a positive integer."}), 400
        node_id = int(raw_node_id)
    try:
        return jsonify(_rows("{CALL dbo.usp_list_containers (:node_id)}", {"node_id": node_id}))
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.post("/containers/<int:container_db_id>/restart")
@require_roles(*_READ_ROLES)
def restart_container(container_db_id):
    try:
        db.session.execute(text("{CALL dbo.usp_authorize_container_restart (:container_id, :actor_user_id)}"),
                           {"container_id": container_db_id, "actor_user_id": g.current_user["user_id"]})
        rows = _rows(
            "{CALL dbo.usp_restart_container (:container_db_id, :actor_user_id)}",
            {"container_db_id": container_db_id, "actor_user_id": g.current_user["user_id"]},
        )
        db.session.commit()
        event_hub.publish("container_restarted", container_id=container_db_id)
        return jsonify(rows[0] if rows else {"id": container_db_id, "status": "RUNNING"})
    except DBAPIError as exc:
        return _procedure_error(exc)


def _lookup_marker_response(marker_code: str):
    cleaned = marker_code.strip()
    if not cleaned or len(cleaned) > 100:
        return jsonify({"error": "marker_code must be 1-100 characters."}), 400
    try:
        node_rows = _rows("{CALL dbo.usp_lookup_node_by_marker (:marker_code)}", {"marker_code": cleaned})
        if not node_rows:
            return jsonify({"error": "Marker or node not found."}), 404
        node = node_rows[0]
        node_id = node["node_id"]
        containers = _rows("{CALL dbo.usp_list_containers (:node_id)}", {"node_id": node_id})
        alerts = _rows(
            "{CALL dbo.usp_list_alerts (:statuses, :node_id, :limit, :offset)}",
            {"statuses": "OPEN,ACKNOWLEDGED", "node_id": node_id, "limit": 50, "offset": 0},
        )
        tickets = _rows(
            "{CALL dbo.usp_list_tickets (:statuses, :node_id, :limit, :offset)}",
            {"statuses": None, "node_id": node_id, "limit": 50, "offset": 0},
        )
        histories = _rows("{CALL dbo.usp_list_maintenance_histories (:node_id)}", {"node_id": node_id})
        return jsonify({
            "node": node,
            "containers": containers,
            "alerts": alerts,
            "tickets": tickets,
            "maintenance_histories": histories,
        })
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.get("/markers/lookup")
@require_roles(*_READ_ROLES)
def lookup_marker_query():
    code = request.args.get("code", "")
    return _lookup_marker_response(code)


@api_bp.get("/markers/<path:marker_code>")
@require_roles(*_READ_ROLES)
def lookup_marker_path(marker_code):
    return _lookup_marker_response(marker_code)


@api_bp.post("/markers")
@require_roles(*_OPERATOR_ROLES)
def manage_marker():
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return jsonify({"error": "Body must be a JSON object."}), 400
    node_id = payload.get("node_id")
    marker_type = payload.get("marker_type", "QR")
    marker_code = payload.get("marker_code")
    if not _positive_int(node_id):
        return jsonify({"error": "node_id must be a positive integer."}), 400
    if not isinstance(marker_type, str) or marker_type not in {"QR", "ARUCO"}:
        return jsonify({"error": "marker_type must be QR or ARUCO."}), 400
    if not isinstance(marker_code, str) or not marker_code.strip() or len(marker_code.strip()) > 100:
        return jsonify({"error": "marker_code must be 1-100 characters."}), 400
    try:
        rows = _rows(
            "{CALL dbo.usp_manage_marker (:node_id, :marker_type, :marker_code, :actor_user_id)}",
            {
                "node_id": node_id,
                "marker_type": marker_type,
                "marker_code": marker_code.strip(),
                "actor_user_id": g.current_user["user_id"],
            },
        )
        db.session.commit()
        return jsonify(rows[0] if rows else {"node_id": node_id, "marker_code": marker_code.strip()}), 201
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.get("/alerts")
@require_roles(*_READ_ROLES)
def list_alerts():
    statuses = request.args.get("status", "OPEN,ACKNOWLEDGED")
    if len(statuses) > 200 or any(not (c.isupper() or c.isdigit() or c in "_, ") for c in statuses):
        return jsonify({"error": "Invalid status filter."}), 400
    node_id, err = _parse_optional_pos_int("node_id")
    if err:
        return err
    limit, offset, err = _parse_pagination()
    if err:
        return err
    try:
        return jsonify(_rows(
            "{CALL dbo.usp_list_alerts (:statuses, :node_id, :limit, :offset)}",
            {"statuses": statuses, "node_id": node_id, "limit": limit, "offset": offset},
        ))
    except DBAPIError:
        db.session.rollback()
        return jsonify({"error": "Failed to list alerts."}), 503


@api_bp.post("/alerts/<int:alert_id>/ack")
@require_roles(*_OPERATOR_ROLES)
def acknowledge_alert(alert_id):
    try:
        rows = _rows(
            "{CALL dbo.usp_acknowledge_alert (:alert_id, :user_id)}",
            {"alert_id": alert_id, "user_id": g.current_user["user_id"]},
        )
        db.session.commit()
        event_hub.publish("alert_updated", alert_id=alert_id)
        return jsonify(rows[0] if rows else {"id": alert_id, "status": "ACKNOWLEDGED"})
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.patch("/alerts/<int:alert_id>/status")
@require_roles(*_OPERATOR_ROLES)
def update_alert_status(alert_id):
    payload = request.get_json(silent=True)
    status = payload.get("status") if isinstance(payload, dict) else None
    if not isinstance(status, str) or status not in {"ACKNOWLEDGED", "RESOLVED", "CLOSED"}:
        return jsonify({"error": "status must be ACKNOWLEDGED, RESOLVED or CLOSED."}), 400
    try:
        rows = _rows(
            "{CALL dbo.usp_update_alert_status (:alert_id, :status, :actor_user_id)}",
            {"alert_id": alert_id, "status": status, "actor_user_id": g.current_user["user_id"]},
        )
        db.session.commit()
        event_hub.publish("alert_updated", alert_id=alert_id, status=status)
        return jsonify(rows[0] if rows else {"id": alert_id, "status": status})
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.get("/thresholds")
@require_roles(*_READ_ROLES)
def list_thresholds():
    try:
        return jsonify(_rows("EXEC dbo.usp_list_alert_thresholds"))
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.put("/thresholds/<int:metric_type_id>")
@require_roles(*_OPERATOR_ROLES)
def update_threshold(metric_type_id):
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return jsonify({"error": "Body must be a JSON object."}), 400
    warning = payload.get("warning_threshold")
    critical = payload.get("critical_threshold")
    duration = payload.get("duration_seconds", 30)
    is_active = payload.get("is_active", True)
    if isinstance(warning, bool) or not isinstance(warning, (int, float)):
        return jsonify({"error": "warning_threshold must be a number."}), 400
    if isinstance(critical, bool) or not isinstance(critical, (int, float)):
        return jsonify({"error": "critical_threshold must be a number."}), 400
    if float(warning) >= float(critical):
        return jsonify({"error": "warning_threshold must be less than critical_threshold."}), 400
    if not _positive_int(duration):
        return jsonify({"error": "duration_seconds must be a positive integer."}), 400
    if not isinstance(is_active, bool):
        return jsonify({"error": "is_active must be a boolean."}), 400
    try:
        rows = _rows(
            "{CALL dbo.usp_update_alert_threshold (:metric_type_id, :warning, :critical, "
            ":duration, :is_active, :actor_user_id)}",
            {
                "metric_type_id": metric_type_id,
                "warning": float(warning),
                "critical": float(critical),
                "duration": duration,
                "is_active": 1 if is_active else 0,
                "actor_user_id": g.current_user["user_id"],
            },
        )
        db.session.commit()
        event_hub.publish("threshold_updated", metric_type_id=metric_type_id)
        return jsonify(rows[0] if rows else {"metric_type_id": metric_type_id})
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.get("/tickets")
@require_roles(*_READ_ROLES)
def list_tickets():
    statuses = request.args.get("status")
    if statuses is not None and (len(statuses) > 200 or any(not (c.isupper() or c.isdigit() or c in "_, ") for c in statuses)):
        return jsonify({"error": "Invalid status filter."}), 400
    node_id, err = _parse_optional_pos_int("node_id")
    if err:
        return err
    limit, offset, err = _parse_pagination()
    if err:
        return err
    try:
        return jsonify(_rows(
            "{CALL dbo.usp_list_tickets (:statuses, :node_id, :limit, :offset)}",
            {"statuses": statuses, "node_id": node_id, "limit": limit, "offset": offset},
        ))
    except DBAPIError:
        db.session.rollback()
        return jsonify({"error": "Failed to list tickets."}), 503


@api_bp.post("/tickets")
@require_roles(*_OPERATOR_ROLES)
def create_ticket():
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return jsonify({"error": "Body must be a JSON object."}), 400
    node_id = payload.get("node_id")
    title = payload.get("title")
    description = payload.get("description", "")
    priority = payload.get("priority", "MEDIUM")
    alert_id = payload.get("alert_id")
    if not _positive_int(node_id):
        return jsonify({"error": "node_id must be a positive integer."}), 400
    if not isinstance(title, str) or not title.strip() or len(title) > 200:
        return jsonify({"error": "title must be 1-200 characters."}), 400
    if not isinstance(description, str):
        return jsonify({"error": "description must be a string."}), 400
    if not isinstance(priority, str) or priority not in {"LOW", "MEDIUM", "HIGH", "URGENT", "CRITICAL"}:
        return jsonify({"error": "Invalid priority."}), 400
    if alert_id is not None and not _positive_int(alert_id):
        return jsonify({"error": "alert_id must be a positive integer."}), 400
    try:
        rows = _rows(
            "{CALL dbo.usp_create_ticket (:node_id, :title, :description, :priority, "
            ":user_id, :alert_id)}",
            {"node_id": node_id, "title": title.strip(), "description": description,
             "priority": priority, "user_id": g.current_user["user_id"], "alert_id": alert_id},
        )
        db.session.commit()
        event_hub.publish("ticket_created", ticket_id=rows[0]["id"])
        return jsonify({"id": rows[0]["id"], "status": "OPEN"}), 201
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.patch("/tickets/<int:ticket_id>/status")
@require_roles(*_READ_ROLES)
def update_ticket_status(ticket_id):
    payload = request.get_json(silent=True)
    status = payload.get("status") if isinstance(payload, dict) else None
    if not isinstance(status, str) or status not in TICKET_STATUSES:
        return jsonify({"error": "status must be OPEN, IN_PROGRESS, PENDING_CLOSURE or CLOSED."}), 400
    if g.current_user["role"] == ROLE_TECHNICIAN and status not in {"IN_PROGRESS", "PENDING_CLOSURE"}:
        return jsonify({"error": "Technicians can only move tickets to IN_PROGRESS or PENDING_CLOSURE."}), 403
    try:
        _authorize_ticket_write(ticket_id)
        rows = _rows(
            "{CALL dbo.usp_update_ticket_status (:ticket_id, :status, :actor_user_id)}",
            {"ticket_id": ticket_id, "status": status, "actor_user_id": g.current_user["user_id"]},
        )
        db.session.commit()
        event_hub.publish("ticket_updated", ticket_id=ticket_id, status=status)
        return jsonify(rows[0] if rows else {"id": ticket_id, "status": status})
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.patch("/tickets/<int:ticket_id>/assign")
@require_roles(*_OPERATOR_ROLES)
def assign_ticket(ticket_id):
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return jsonify({"error": "Body must be a JSON object."}), 400
    assigned_to_user_id = payload.get("assigned_to_user_id")
    if not _positive_int(assigned_to_user_id):
        return jsonify({"error": "assigned_to_user_id must be a positive integer."}), 400
    try:
        rows = _rows(
            "{CALL dbo.usp_assign_ticket (:ticket_id, :assigned_to_user_id, :actor_user_id)}",
            {
                "ticket_id": ticket_id,
                "assigned_to_user_id": assigned_to_user_id,
                "actor_user_id": g.current_user["user_id"],
            },
        )
        db.session.commit()
        event_hub.publish("ticket_assigned", ticket_id=ticket_id)
        return jsonify(rows[0] if rows else {"id": ticket_id, "assigned_to_user_id": assigned_to_user_id})
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.get("/tickets/<int:ticket_id>/notes")
@require_roles(*_READ_ROLES)
def list_ticket_notes(ticket_id):
    try:
        return jsonify(_rows("{CALL dbo.usp_list_ticket_notes (:ticket_id)}", {"ticket_id": ticket_id}))
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.post("/tickets/<int:ticket_id>/notes")
@require_roles(*_READ_ROLES)
def add_ticket_note(ticket_id):
    payload = request.get_json(silent=True)
    note_text = payload.get("note_text") if isinstance(payload, dict) else None
    if not isinstance(note_text, str) or not note_text.strip():
        return jsonify({"error": "note_text is required."}), 400
    try:
        _authorize_ticket_write(ticket_id)
        rows = _rows(
            "{CALL dbo.usp_add_ticket_note (:ticket_id, :author_user_id, :note_text)}",
            {
                "ticket_id": ticket_id,
                "author_user_id": g.current_user["user_id"],
                "note_text": note_text.strip(),
            },
        )
        db.session.commit()
        return jsonify(rows[0] if rows else {"ticket_id": ticket_id}), 201
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.post("/tickets/<int:ticket_id>/closure-request")
@require_roles(*_READ_ROLES)
def submit_ticket_closure_request(ticket_id):
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return jsonify({"error": "Body must be a JSON object."}), 400
    summary = payload.get("summary")
    resolution_details = payload.get("resolution_details")
    maintenance_type = payload.get("maintenance_type", "CORRECTIVE")
    if not isinstance(summary, str) or not summary.strip() or len(summary.strip()) > 255:
        return jsonify({"error": "summary must be 1-255 characters."}), 400
    if not isinstance(resolution_details, str) or not resolution_details.strip():
        return jsonify({"error": "resolution_details is required."}), 400
    if not isinstance(maintenance_type, str) or maintenance_type not in MAINTENANCE_TYPES:
        return jsonify({"error": "Invalid maintenance_type."}), 400
    try:
        _authorize_ticket_write(ticket_id)
        rows = _rows(
            "{CALL dbo.usp_submit_ticket_closure_request (:ticket_id, :requested_by_user_id, "
            ":summary, :resolution_details, :maintenance_type)}",
            {
                "ticket_id": ticket_id,
                "requested_by_user_id": g.current_user["user_id"],
                "summary": summary.strip(),
                "resolution_details": resolution_details.strip(),
                "maintenance_type": maintenance_type,
            },
        )
        db.session.commit()
        event_hub.publish("ticket_closure_requested", ticket_id=ticket_id)
        return jsonify(rows[0] if rows else {"ticket_id": ticket_id, "status": "PENDING"}), 201
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.post("/tickets/<int:ticket_id>/closure-review")
@require_roles(*_OPERATOR_ROLES)
def review_ticket_closure_request(ticket_id):
    payload = request.get_json(silent=True)
    decision = payload.get("decision") if isinstance(payload, dict) else None
    if not isinstance(decision, str) or decision not in {"APPROVED", "REJECTED"}:
        return jsonify({"error": "decision must be APPROVED or REJECTED."}), 400
    try:
        rows = _rows(
            "{CALL dbo.usp_review_ticket_closure_request (:ticket_id, :reviewer_user_id, :decision)}",
            {
                "ticket_id": ticket_id,
                "reviewer_user_id": g.current_user["user_id"],
                "decision": decision,
            },
        )
        db.session.commit()
        event_hub.publish("ticket_closure_reviewed", ticket_id=ticket_id, decision=decision)
        return jsonify(rows[0] if rows else {"id": ticket_id, "closure_status": decision})
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.get("/assets")
@require_roles(*_READ_ROLES)
def list_assets():
    try:
        return jsonify(_rows("EXEC dbo.usp_list_assets"))
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.put("/assets/<int:node_id>")
@require_roles(*_OPERATOR_ROLES)
def upsert_asset(node_id):
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return jsonify({"error": "Body must be a JSON object."}), 400

    required_strings = ("cpu_model", "os_name", "os_version", "vendor", "model_number", "serial_number")
    for field in required_strings:
        val = payload.get(field)
        if not isinstance(val, str) or not val.strip():
            return jsonify({"error": f"{field} is required."}), 400

    cpu_cores = payload.get("cpu_cores")
    ram_gb = payload.get("total_ram_gb")
    storage_gb = payload.get("total_storage_gb")
    if not _positive_int(cpu_cores):
        return jsonify({"error": "cpu_cores must be a positive integer."}), 400
    if isinstance(ram_gb, bool) or not isinstance(ram_gb, (int, float)) or ram_gb <= 0:
        return jsonify({"error": "total_ram_gb must be positive."}), 400
    if isinstance(storage_gb, bool) or not isinstance(storage_gb, (int, float)) or storage_gb <= 0:
        return jsonify({"error": "total_storage_gb must be positive."}), 400

    warranty_end, valid_date = _parse_optional_iso_datetime(payload.get("warranty_end"))
    if not valid_date:
        return jsonify({"error": "warranty_end must be an ISO date or datetime string."}), 400
    support_contact = payload.get("support_contact")
    if support_contact is not None and not isinstance(support_contact, str):
        return jsonify({"error": "support_contact must be a string."}), 400

    try:
        rows = _rows(
            "{CALL dbo.usp_upsert_asset_warranty (:node_id, :cpu_model, :cpu_cores, :ram, :storage, "
            ":os_name, :os_version, :vendor, :model_number, :serial_number, :warranty_end, "
            ":support_contact, :actor_user_id)}",
            {
                "node_id": node_id,
                "cpu_model": payload["cpu_model"].strip()[:100],
                "cpu_cores": cpu_cores,
                "ram": float(ram_gb),
                "storage": float(storage_gb),
                "os_name": payload["os_name"].strip()[:100],
                "os_version": payload["os_version"].strip()[:50],
                "vendor": payload["vendor"].strip()[:100],
                "model_number": payload["model_number"].strip()[:100],
                "serial_number": payload["serial_number"].strip()[:100],
                "warranty_end": warranty_end,
                "support_contact": support_contact.strip()[:255] if isinstance(support_contact, str) and support_contact.strip() else None,
                "actor_user_id": g.current_user["user_id"],
            },
        )
        db.session.commit()
        return jsonify(rows[0] if rows else {"node_id": node_id, "status": "updated"})
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.get("/maintenance")
@require_roles(*_READ_ROLES)
def list_maintenance():
    raw_node_id = request.args.get("node_id")
    node_id = None
    if raw_node_id is not None and raw_node_id != "":
        if not raw_node_id.isdigit():
            return jsonify({"error": "node_id must be a positive integer."}), 400
        node_id = int(raw_node_id)
    try:
        return jsonify(_rows("{CALL dbo.usp_list_maintenance_histories (:node_id)}", {"node_id": node_id}))
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.get("/technicians")
@require_roles(*_OPERATOR_ROLES)
def list_technicians():
    try:
        return jsonify(_rows("EXEC dbo.usp_list_assignable_technicians"))
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.get("/users")
@require_roles(ROLE_ADMIN)
def list_users():
    try:
        return jsonify(_rows("EXEC dbo.usp_list_users"))
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.post("/users")
@require_roles(ROLE_ADMIN)
def manage_user():
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return jsonify({"error": "Body must be a JSON object."}), 400

    user_id = payload.get("id", payload.get("user_id"))
    if user_id is not None and not _positive_int(user_id):
        return jsonify({"error": "user_id must be a positive integer."}), 400

    username = payload.get("username")
    email = payload.get("email")
    full_name = payload.get("full_name")
    role_name = payload.get("role_name")
    is_active = payload.get("is_active", True)
    password = payload.get("password")

    if not isinstance(username, str) or not username.strip() or len(username.strip()) > 50:
        return jsonify({"error": "username must be 1-50 characters."}), 400
    if not isinstance(email, str) or "@" not in email or len(email.strip()) > 100:
        return jsonify({"error": "Valid email is required."}), 400
    if not isinstance(full_name, str) or not full_name.strip() or len(full_name.strip()) > 100:
        return jsonify({"error": "full_name must be 1-100 characters."}), 400
    if not isinstance(role_name, str) or role_name not in VALID_ROLES:
        return jsonify({"error": "Invalid role_name."}), 400
    if not isinstance(is_active, bool):
        return jsonify({"error": "is_active must be a boolean."}), 400

    password_hash = None
    if password is not None and password != "":
        if not isinstance(password, str) or len(password) < 8:
            return jsonify({"error": "password must be at least 8 characters."}), 400
        password_hash = generate_password_hash(password)
    elif user_id is None:
        return jsonify({"error": "password is required when creating a user."}), 400

    try:
        rows = _rows(
            "{CALL dbo.usp_manage_user (:user_id, :username, :email, :full_name, :role_name, "
            ":is_active, :password_hash, :actor_user_id)}",
            {
                "user_id": user_id,
                "username": username.strip(),
                "email": email.strip(),
                "full_name": full_name.strip(),
                "role_name": role_name,
                "is_active": 1 if is_active else 0,
                "password_hash": password_hash,
                "actor_user_id": g.current_user["user_id"],
            },
        )
        db.session.commit()
        return jsonify(rows[0] if rows else {"username": username.strip()}), 201 if user_id is None else 200
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.get("/account-requests")
@require_roles(ROLE_ADMIN)
def list_account_requests():
    try:
        return jsonify(_rows("EXEC dbo.usp_list_account_access_requests"))
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.post("/account-requests/<int:request_id>/review")
@require_roles(ROLE_ADMIN)
def review_account_request(request_id):
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return jsonify(error="Body must be a JSON object."), 400
    decision = payload.get("decision")
    if not isinstance(decision, str) or decision not in {"APPROVE", "REJECT"}:
        return jsonify(error="decision must be APPROVE or REJECT."), 400
    if decision == "REJECT":
        bootstrap = code_hash = role = None
        response_code = None
    else:
        role = payload.get("role_name")
        bootstrap = secrets.token_urlsafe(18)
        code = secrets.token_urlsafe(32)
        code_hash = hashlib.sha256(code.encode()).hexdigest()
        response_code = code
    try:
        rows = _rows("""{CALL dbo.usp_review_account_access_request (:request_id, :actor_user_id, :decision, :role_name, :bootstrap_hash, :code_hash)}""", {
            "request_id": request_id, "actor_user_id": g.current_user["user_id"], "decision": decision,
            "role_name": role, "bootstrap_hash": generate_password_hash(bootstrap) if bootstrap else None, "code_hash": code_hash,
        })
        db.session.commit()
        return (
            jsonify({
                "status": decision.lower(),
                "recovery_code": response_code,
                "user_id": rows[0].get("user_id") if rows else None,
            }),
            200,
            {"Cache-Control": "no-store"},
        )
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.get("/handover")
@require_roles(*_READ_ROLES)
def list_handover_notes():
    try:
        return jsonify(_rows("EXEC dbo.usp_list_handover_notes"))
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.post("/handover")
@require_roles(*_READ_ROLES)
def add_handover_note():
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return jsonify(error="Body must be a JSON object."), 400
    note = payload.get("note")
    if not isinstance(note, str) or not 1 <= len(note.strip()) <= 1000:
        return jsonify(error="note must be 1-1000 characters."), 400
    try:
        rows = _rows("{CALL dbo.usp_add_handover_note (:user_id, :username, :note)}", {
            "user_id": g.current_user["user_id"], "username": g.current_user["username"], "note": note.strip(),
        })
        db.session.commit()
        return jsonify(rows[0] if rows else {"status": "created"}), 201
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.get("/audit-logs")
@require_roles(ROLE_ADMIN)
def list_audit_logs():
    limit, offset, err = _parse_pagination()
    if err:
        return err
    target_entity = request.args.get("target_entity")
    if target_entity is not None:
        target_entity = target_entity.strip()
        if len(target_entity) > 100 or any(not (c.isupper() or c.isdigit() or c == "_") for c in target_entity):
            return jsonify({"error": "Invalid target_entity filter."}), 400
    try:
        return jsonify(_rows(
            "{CALL dbo.usp_list_audit_logs (:limit, :target_entity, :offset)}",
            {"limit": limit, "target_entity": target_entity or None, "offset": offset},
        ))
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.get("/notifications")
@require_roles(*_READ_ROLES)
def list_notifications():
    raw_limit = request.args.get("limit", "30")
    try:
        limit = max(1, min(100, int(raw_limit)))
    except ValueError:
        return jsonify({"error": "limit must be an integer."}), 400
    try:
        return jsonify(_rows(
            "{CALL dbo.usp_list_notifications (:user_id, :limit)}",
            {"user_id": g.current_user["user_id"], "limit": limit},
        ))
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.post("/notifications/read")
@require_roles(*_READ_ROLES)
def mark_notifications_read():
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict) or set(payload) - {"notification_id"}:
        return jsonify(error="Body must contain only notification_id, or be an empty object."), 400
    notification_id = payload.get("notification_id")
    if notification_id is not None and not _positive_int(notification_id):
        return jsonify({"error": "notification_id must be a positive integer."}), 400
    try:
        rows = _rows(
            "{CALL dbo.usp_mark_notification_read (:user_id, :notification_id)}",
            {"user_id": g.current_user["user_id"], "notification_id": notification_id},
        )
        db.session.commit()
        return jsonify(rows[0] if rows else {"unread_count": 0})
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.get("/reports/hierarchy")
@require_roles(*_READ_ROLES)
def hierarchical_report():
    group_by = request.args.get("group_by", "NODE").upper()
    if group_by not in {"SITE", "ROOM", "RACK", "NODE"}:
        return jsonify({"error": "group_by must be SITE, ROOM, RACK or NODE."}), 400
    raw_hours = request.args.get("hours", "24")
    try:
        hours = max(1, min(720, int(raw_hours)))
    except ValueError:
        return jsonify({"error": "hours must be an integer."}), 400
    try:
        return jsonify(_rows(
            "{CALL dbo.usp_get_hierarchical_report (:group_by, :hours)}",
            {"group_by": group_by, "hours": hours},
        ))
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.get("/collectors")
@require_roles(*_READ_ROLES)
def list_collectors():
    try:
        return jsonify(_rows("EXEC dbo.usp_list_collector_agents"))
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.post("/collectors")
@require_roles(*_OPERATOR_ROLES)
def manage_collector():
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return jsonify({"error": "Body must be a JSON object."}), 400
    agent_id = payload.get("id", payload.get("agent_id"))
    node_id = payload.get("node_id")
    agent_version = payload.get("agent_version", "1.0.0")
    status = payload.get("status", "ACTIVE")
    rotate_key = payload.get("rotate_key", False)
    if not isinstance(rotate_key, bool):
        return jsonify(error="rotate_key must be a boolean."), 400
    raw_key = payload.get("api_key")

    if agent_id is not None and not _positive_int(agent_id):
        return jsonify({"error": "agent_id must be a positive integer."}), 400
    if not _positive_int(node_id):
        return jsonify({"error": "node_id must be a positive integer."}), 400
    if not isinstance(agent_version, str) or not agent_version.strip() or len(agent_version.strip()) > 50:
        return jsonify({"error": "agent_version must be 1-50 characters."}), 400
    if not isinstance(status, str) or status not in {"ACTIVE", "INACTIVE", "ERROR"}:
        return jsonify({"error": "status must be ACTIVE, INACTIVE or ERROR."}), 400

    issued_key = None
    key_hash = None
    if agent_id is None or rotate_key or (isinstance(raw_key, str) and raw_key.strip()):
        issued_key = raw_key.strip() if isinstance(raw_key, str) and raw_key.strip() else f"arimms-{secrets.token_urlsafe(18)}"
        key_hash = hashlib.sha256(issued_key.encode("utf-8")).hexdigest()

    try:
        rows = _rows(
            "{CALL dbo.usp_manage_collector_agent (:agent_id, :node_id, :agent_version, :status, "
            ":api_key_hash, :actor_user_id)}",
            {
                "agent_id": agent_id,
                "node_id": node_id,
                "agent_version": agent_version.strip(),
                "status": status,
                "api_key_hash": key_hash,
                "actor_user_id": g.current_user["user_id"],
            },
        )
        db.session.commit()
        event_hub.publish("collector_updated", node_id=node_id)
        result = dict(rows[0]) if rows else {"node_id": node_id, "status": status}
        if issued_key is not None:
            result["api_key"] = issued_key
        return jsonify(result), 201 if agent_id is None else 200
    except DBAPIError as exc:
        return _procedure_error(exc)

