import datetime
import functools

import jwt
from flask import Blueprint, current_app, g, jsonify, request
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError
from werkzeug.security import check_password_hash, generate_password_hash

from extensions import db

JWT_ALGORITHM = "HS256"
JWT_EXPIRES_MINUTES = 60

ROLE_ADMIN = "ADMINISTRATOR"
ROLE_OPERATOR = "SYSTEM_OPERATOR"
ROLE_TECHNICIAN = "FIELD_TECHNICIAN"

# Hash gia de thoi gian xu ly khi username khong ton tai gan bang khi ton tai
_DUMMY_HASH = generate_password_hash("not-a-real-password")

auth_bp = Blueprint("auth", __name__, url_prefix="/auth")


def _jwt_secret():
    return current_app.config.get("JWT_SECRET_KEY")


def _issue_token(user) -> str:
    now = datetime.datetime.now(datetime.timezone.utc)
    claims = {
        "sub": str(user["user_id"]),
        "username": user["username"],
        "role": user["role_name"],
        "iat": now,
        "exp": now + datetime.timedelta(minutes=JWT_EXPIRES_MINUTES),
    }
    return jwt.encode(claims, _jwt_secret(), algorithm=JWT_ALGORITHM)


def require_roles(*allowed_roles):
    """Decorator: bat buoc Bearer token hop le; neu co allowed_roles thi vai phai nam trong do.
    401 = thieu/sai/het han token, 403 = dung token nhung khong du quyen."""

    def decorator(view):
        @functools.wraps(view)
        def wrapper(*args, **kwargs):
            secret = _jwt_secret()
            if not secret:
                current_app.logger.error("JWT_SECRET_KEY chua duoc cau hinh")
                return jsonify({"error": "Loi may chu"}), 500

            scheme, _, token = request.headers.get("Authorization", "").partition(" ")
            if scheme.lower() != "bearer" or not token.strip():
                return jsonify({"error": "Thieu token"}), 401
            try:
                claims = jwt.decode(
                    token.strip(),
                    secret,
                    algorithms=[JWT_ALGORITHM],
                    options={"require": ["exp", "sub"]},
                )
            except jwt.ExpiredSignatureError:
                return jsonify({"error": "Token het han"}), 401
            except jwt.InvalidTokenError:
                return jsonify({"error": "Token khong hop le"}), 401

            if allowed_roles and claims.get("role") not in allowed_roles:
                return jsonify({"error": "Khong du quyen"}), 403

            g.current_user = {
                "user_id": int(claims["sub"]),
                "username": claims.get("username"),
                "role": claims.get("role"),
            }
            return view(*args, **kwargs)

        return wrapper

    return decorator


@auth_bp.post("/login")
def login():
    if not _jwt_secret():
        current_app.logger.error("JWT_SECRET_KEY chua duoc cau hinh")
        return jsonify({"error": "Loi may chu"}), 500

    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return jsonify({"error": "Body phai la JSON object"}), 400
    username = payload.get("username")
    password = payload.get("password")
    if not (isinstance(username, str) and username and isinstance(password, str) and password):
        return jsonify({"error": "Can 2 truong: username (str), password (str)"}), 400

    try:
        user = db.session.execute(
            text("EXEC dbo.usp_authenticate_user @username = :username"),
            {"username": username},
        ).mappings().first()
    except DBAPIError:
        db.session.rollback()
        current_app.logger.exception("usp_authenticate_user failed")
        return jsonify({"error": "Loi may chu"}), 500

    stored_hash = user["password_hash"] if user else _DUMMY_HASH
    try:
        password_ok = check_password_hash(stored_hash, password)
    except ValueError:
        password_ok = False

    # Cung mot cau tra loi cho "khong co user" va "sai mat khau"
    if user is None or not password_ok:
        return jsonify({"error": "Sai ten dang nhap hoac mat khau"}), 401

    return jsonify({
        "access_token": _issue_token(user),
        "token_type": "Bearer",
        "expires_in": JWT_EXPIRES_MINUTES * 60,
        "user": {"id": user["user_id"], "username": user["username"],
                 "full_name": user["full_name"], "role": user["role_name"]},
    }), 200


@auth_bp.get("/me")
@require_roles()
def me():
    return jsonify(g.current_user), 200


# --- Endpoint demo de kiem thu phan quyen (cac ticket API sau dung lai require_roles) ---
@auth_bp.get("/demo/admin")
@require_roles(ROLE_ADMIN)
def demo_admin():
    return jsonify({"ok": True, "area": "admin", "user": g.current_user["username"]}), 200


@auth_bp.get("/demo/operations")
@require_roles(ROLE_ADMIN, ROLE_OPERATOR)
def demo_operations():
    return jsonify({"ok": True, "area": "operations", "user": g.current_user["username"]}), 200


@auth_bp.get("/demo/field")
@require_roles(ROLE_ADMIN, ROLE_TECHNICIAN)
def demo_field():
    return jsonify({"ok": True, "area": "field", "user": g.current_user["username"]}), 200