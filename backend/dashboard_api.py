"""Dashboard REST endpoints backed only by SQL Server stored procedures."""
from flask import Blueprint, g, jsonify, request
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError

from auth import ROLE_ADMIN, ROLE_OPERATOR, ROLE_TECHNICIAN, require_roles
from extensions import db

api_bp = Blueprint("dashboard_api", __name__, url_prefix="/api")
_READ_ROLES = (ROLE_ADMIN, ROLE_OPERATOR, ROLE_TECHNICIAN)
_OPERATOR_ROLES = (ROLE_ADMIN, ROLE_OPERATOR)


def _rows(statement, params=None):
    return [dict(row) for row in db.session.execute(text(statement), params or {}).mappings().all()]


def _procedure_error(exc):
    db.session.rollback()
    message = str(exc.orig)
    codes = {
        "51060": (404, "Alert not found."),
        "51061": (409, "Alert is not open."),
        "51062": (404, "Node not found."),
        "51063": (400, "Invalid priority."),
        "51064": (404, "Alert not found."),
        "51065": (404, "Ticket not found."),
        "51066": (409, "Invalid ticket status transition."),
        "51067": (400, "Invalid ticket status."),
    }
    for code, (status, detail) in codes.items():
        if code in message:
            return jsonify({"error": detail}), status
    return jsonify({"error": "Database operation failed."}), 503


@api_bp.get("/nodes")
@require_roles(*_READ_ROLES)
def list_nodes():
    try:
        return jsonify(_rows("EXEC dbo.usp_list_nodes_latest"))
    except DBAPIError:
        db.session.rollback()
        return jsonify({"error": "Failed to list nodes."}), 503


@api_bp.get("/alerts")
@require_roles(*_READ_ROLES)
def list_alerts():
    statuses = request.args.get("status", "OPEN,ACKNOWLEDGED")
    if len(statuses) > 200 or any(not (c.isupper() or c.isdigit() or c in "_, ") for c in statuses):
        return jsonify({"error": "Invalid status filter."}), 400
    try:
        return jsonify(_rows("{CALL dbo.usp_list_alerts (:statuses)}", {"statuses": statuses}))
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
        return jsonify(rows[0] if rows else {"id": alert_id, "status": "ACKNOWLEDGED"})
    except DBAPIError as exc:
        return _procedure_error(exc)


@api_bp.get("/tickets")
@require_roles(*_READ_ROLES)
def list_tickets():
    statuses = request.args.get("status")
    if statuses is not None and (len(statuses) > 200 or any(not (c.isupper() or c.isdigit() or c in "_, ") for c in statuses)):
        return jsonify({"error": "Invalid status filter."}), 400
    try:
        return jsonify(_rows("{CALL dbo.usp_list_tickets (:statuses)}", {"statuses": statuses}))
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
    if isinstance(node_id, bool) or not isinstance(node_id, int) or node_id <= 0:
        return jsonify({"error": "node_id must be a positive integer."}), 400
    if not isinstance(title, str) or not title.strip() or len(title) > 200:
        return jsonify({"error": "title must be 1-200 characters."}), 400
    if not isinstance(description, str):
        return jsonify({"error": "description must be a string."}), 400
    if not isinstance(priority, str) or priority not in {"LOW", "MEDIUM", "HIGH", "URGENT", "CRITICAL"}:
        return jsonify({"error": "Invalid priority."}), 400
    if alert_id is not None and (isinstance(alert_id, bool) or not isinstance(alert_id, int) or alert_id <= 0):
        return jsonify({"error": "alert_id must be a positive integer."}), 400
    try:
        rows = _rows(
            "{CALL dbo.usp_create_ticket (:node_id, :title, :description, :priority, "
            ":user_id, :alert_id)}",
            {"node_id": node_id, "title": title.strip(), "description": description,
             "priority": priority, "user_id": g.current_user["user_id"], "alert_id": alert_id},
        )
        db.session.commit()
        return jsonify({"id": rows[0]["id"], "status": "OPEN"}), 201
    except DBAPIError as exc:
        return _procedure_error(exc)


TICKET_STATUSES = {"OPEN", "IN_PROGRESS", "PENDING_CLOSURE", "CLOSED"}


@api_bp.patch("/tickets/<int:ticket_id>/status")
@require_roles(*_OPERATOR_ROLES)
def update_ticket_status(ticket_id):
    payload = request.get_json(silent=True)
    status = payload.get("status") if isinstance(payload, dict) else None
    if not isinstance(status, str) or status not in TICKET_STATUSES:
        return jsonify({"error": "status must be OPEN, IN_PROGRESS, PENDING_CLOSURE or CLOSED."}), 400
    try:
        rows = _rows(
            "{CALL dbo.usp_update_ticket_status (:ticket_id, :status)}",
            {"ticket_id": ticket_id, "status": status},
        )
        db.session.commit()
        return jsonify(rows[0] if rows else {"id": ticket_id, "status": status})
    except DBAPIError as exc:
        return _procedure_error(exc)
