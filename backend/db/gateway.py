from sqlalchemy import text

from backend.core.extensions import db


def _execute(session, statement: str, params: dict | None = None):
    return session.execute(text(statement), params or {})


def execute_procedure(statement: str, params: dict | None = None):
    """Execute a stored procedure through the shared SQLAlchemy session."""
    return _execute(db.session, statement, params)


def rows(statement: str, params: dict | None = None) -> list[dict]:
    """Execute a read-only stored procedure call and return mapping rows."""
    return [dict(row) for row in execute_procedure(statement, params).mappings().all()]

