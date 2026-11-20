import base64
import datetime
import functools
import hashlib
import hmac
import json
import os
import re
import secrets
import struct
import time
import uuid

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
_RECOVERY_CODE = re.compile(r"[A-Za-z0-9_-]{43}")


def _jwt_secret():
    return current_app.config.get("JWT_SECRET_KEY")


def _mfa_key():
    value = current_app.config.get("MFA_ENCRYPTION_KEY")
    if not isinstance(value, str) or not value:
        raise ValueError("MFA_ENCRYPTION_KEY must be a URL-safe base64 32-byte key")
    try:
        key = base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))
    except Exception as exc:
        raise ValueError("MFA_ENCRYPTION_KEY must be a URL-safe base64 32-byte key") from exc
    if len(key) != 32:
        raise ValueError("MFA_ENCRYPTION_KEY must encode 32 bytes")
    return key


def _encrypt_mfa(user_id, secret):
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    nonce = secrets.token_bytes(12)
    encrypted = AESGCM(_mfa_key()).encrypt(nonce, secret, f"ar-imms-mfa:{user_id}".encode())
    return nonce + encrypted


def _decrypt_mfa(user_id, encrypted):
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    return AESGCM(_mfa_key()).decrypt(encrypted[:12], encrypted[12:], f"ar-imms-mfa:{user_id}".encode())


def _totp(secret, counter=None):
    counter = int(time.time() // 30) if counter is None else counter
    digest = hmac.new(secret, struct.pack(">Q", counter), hashlib.sha1).digest()
    offset = digest[-1] & 15
    return str((struct.unpack(">I", digest[offset:offset + 4])[0] & 0x7fffffff) % 1_000_000).zfill(6)


def _check_totp(secret, value):
    if not isinstance(value, str) or not re.fullmatch(r"\d{6}", value):
        return False
    counter = int(time.time() // 30)
    return any(hmac.compare_digest(_totp(secret, counter + delta), value) for delta in (-1, 0, 1))


def _consume_mfa_backup_code(user_id, code):
    if not isinstance(code, str) or not 8 <= len(code) <= 40:
        return False
    try:
        result = db.session.execute(text("{CALL dbo.usp_use_mfa_backup_code (:user_id, :code_hash)}"), {
            "user_id": user_id, "code_hash": hashlib.sha256(code.encode()).hexdigest(),
        }).mappings().first()
        db.session.commit()
        return bool(result and result["used"])
    except DBAPIError:
        db.session.rollback()
        return False


def _issue_token(user) -> str:
    now = datetime.datetime.now(datetime.timezone.utc)
    jti = str(uuid.uuid4())
    expires = now + datetime.timedelta(minutes=JWT_EXPIRES_MINUTES)
    claims = {
        "sub": str(user["user_id"]),
        "username": user["username"],
        "role": user["role_name"],
        "iat": now,
        "jti": jti,
        "security_version": int(user.get("security_version", 1)),
        "exp": expires,
    }
    token = jwt.encode(claims, _jwt_secret(), algorithm=JWT_ALGORITHM)
    try:
        db.session.execute(text("{CALL dbo.usp_create_auth_session (:jti, :user_id, :expires_at)}"), {
            "jti": jti, "user_id": user["user_id"], "expires_at": expires.replace(tzinfo=None),
        })
        db.session.commit()
    except DBAPIError:
        db.session.rollback()
        raise
    return token


def validate_session_token(token):
    """Require both a signed token and a live account/session; fail closed."""
    claims = jwt.decode(token, _jwt_secret(), algorithms=[JWT_ALGORITHM],
                        options={"require": ["exp", "sub", "jti", "security_version"]})
    try:
        if not isinstance(claims["sub"], str) or not claims["sub"].isdigit():
            raise ValueError()
        user_id = int(claims["sub"])
        if user_id <= 0 or str(uuid.UUID(claims["jti"])) != claims["jti"]:
            raise ValueError()
        if type(claims["security_version"]) is not int or claims["security_version"] < 1:
            raise ValueError()
    except (ValueError, TypeError, AttributeError):
        raise jwt.InvalidTokenError("Invalid session claims")
    session = db.session.execute(text("{CALL dbo.usp_validate_auth_session (:jti, :user_id, :security_version)}"), {
        "jti": claims["jti"], "user_id": user_id, "security_version": claims["security_version"],
    }).mappings().first()
    if not session or session.get("role_name") not in {ROLE_ADMIN, ROLE_OPERATOR, ROLE_TECHNICIAN}:
        raise jwt.InvalidTokenError("Session revoked or authorization migration required")
    return {"user_id": user_id, "username": session["username"], "role": session["role_name"],
            "jti": claims["jti"]}, claims


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
                principal, claims = validate_session_token(token.strip())
            except jwt.ExpiredSignatureError:
                return jsonify({"error": "Token het han"}), 401
            except jwt.InvalidTokenError:
                return jsonify({"error": "Token khong hop le"}), 401

            except DBAPIError:
                db.session.rollback()
                return jsonify({"error": "Authentication service unavailable; apply migrations 25 and 26."}), 503

            if allowed_roles and principal["role"] not in allowed_roles:
                return jsonify({"error": "Khong du quyen"}), 403

            g.current_user = principal
            return view(*args, **kwargs)

        return wrapper

    return decorator


@auth_bp.post("/users/<int:user_id>/recovery-code")
@require_roles(ROLE_ADMIN)
def issue_recovery_code(user_id):
    code = secrets.token_urlsafe(32)
    try:
        db.session.execute(text("""
            EXEC dbo.usp_issue_password_recovery
                @user_id = :user_id, @actor_user_id = :actor_user_id, @code_hash = :code_hash
        """), {"user_id": user_id, "actor_user_id": g.current_user["user_id"],
                "code_hash": hashlib.sha256(code.encode()).hexdigest()})
        db.session.commit()
    except DBAPIError as exc:
        db.session.rollback()
        if "(51100)" in str(exc.orig):
            return jsonify(error="forbidden"), 403
        if "(51101)" in str(exc.orig):
            return jsonify(error="inactive_account"), 404
        return jsonify(error="recovery_unavailable"), 503
    return jsonify(code=code, expires_in=900), 201, {"Cache-Control": "no-store"}


@auth_bp.post("/reset-password")
def reset_password():
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return jsonify(error="invalid_recovery_code"), 400
    code, password = payload.get("code"), payload.get("password")
    if not isinstance(code, str) or not _RECOVERY_CODE.fullmatch(code):
        return jsonify(error="invalid_recovery_code"), 400
    if not isinstance(password, str) or not 12 <= len(password) <= 128:
        return jsonify(error="invalid_password"), 400
    try:
        db.session.execute(text("""
            EXEC dbo.usp_redeem_password_recovery
                @code_hash = :code_hash, @password_hash = :password_hash
        """), {"code_hash": hashlib.sha256(code.encode()).hexdigest(),
                "password_hash": generate_password_hash(password)})
        db.session.commit()
    except DBAPIError as exc:
        db.session.rollback()
        if "(51102)" in str(exc.orig):
            return jsonify(error="invalid_recovery_code"), 400
        return jsonify(error="recovery_unavailable"), 503
    return jsonify(status="password_reset"), 200


@auth_bp.post("/mfa/setup")
@require_roles(ROLE_ADMIN)
def begin_mfa_setup():
    secret = secrets.token_bytes(20)
    try:
        encrypted = _encrypt_mfa(g.current_user["user_id"], secret)
        db.session.execute(text("{CALL dbo.usp_begin_mfa_setup (:user_id, :encrypted_secret)}"), {
            "user_id": g.current_user["user_id"], "encrypted_secret": encrypted,
        })
        db.session.commit()
    except (DBAPIError, ValueError, ImportError):
        db.session.rollback()
        return jsonify(error="mfa_setup_unavailable"), 503
    encoded = base64.b32encode(secret).decode().rstrip("=")
    return jsonify(secret=encoded, issuer="AR-IMMS", account=g.current_user["username"]), 201, {"Cache-Control": "no-store"}


@auth_bp.post("/mfa/enable")
@require_roles(ROLE_ADMIN)
def enable_mfa():
    payload = request.get_json(silent=True) or {}
    code = payload.get("code")
    try:
        row = db.session.execute(
            text("{CALL dbo.usp_get_own_mfa_state (:user_id)}"),
            {"user_id": g.current_user["user_id"]},
        ).mappings().first()
        if not row or not row["mfa_setup_secret_encrypted"]:
            return jsonify(error="mfa_setup_required"), 409
        secret = _decrypt_mfa(g.current_user["user_id"], row["mfa_setup_secret_encrypted"])
        if not _check_totp(secret, code):
            return jsonify(error="invalid_mfa_code"), 400
        codes = [secrets.token_hex(6).upper() for _ in range(10)]
        db.session.execute(
            text("{CALL dbo.usp_enable_mfa (:user_id, :backup_hashes)}"),
            {
                "user_id": g.current_user["user_id"],
                "backup_hashes": json.dumps([hashlib.sha256(item.encode()).hexdigest() for item in codes]),
            },
        )
        db.session.commit()
    except (DBAPIError, ValueError, ImportError):
        db.session.rollback()
        return jsonify(error="mfa_enable_unavailable"), 503
    return jsonify(status="mfa_enabled", backup_codes=codes), 200, {"Cache-Control": "no-store"}


@auth_bp.post("/mfa/disable")
@require_roles(ROLE_ADMIN)
def disable_mfa():
    payload = request.get_json(silent=True) or {}
    code = payload.get("code")
    try:
        row = db.session.execute(
            text("{CALL dbo.usp_get_own_mfa_state (:user_id)}"),
            {"user_id": g.current_user["user_id"]},
        ).mappings().first()
        if not row or not row["mfa_enabled"]:
            return jsonify(error="mfa_not_enabled"), 409
        valid = _check_totp(_decrypt_mfa(g.current_user["user_id"], row["mfa_secret_encrypted"]), code)
        if not valid:
            valid = _consume_mfa_backup_code(g.current_user["user_id"], code)
        if not valid:
            return jsonify(error="invalid_mfa_code"), 400
        db.session.execute(text("{CALL dbo.usp_disable_mfa (:user_id)}"), {"user_id": g.current_user["user_id"]})
        db.session.commit()
    except (DBAPIError, ValueError, ImportError):
        db.session.rollback()
        return jsonify(error="mfa_disable_unavailable"), 503
    return jsonify(status="mfa_disabled"), 200


@auth_bp.post("/request-access")
def request_access():
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return jsonify(error="invalid_request"), 400
    username = payload.get("username")
    email = payload.get("email")
    full_name = payload.get("full_name")
    requested_role = payload.get("requested_role", ROLE_TECHNICIAN)
    note = payload.get("note", "")
    secret = _jwt_secret()
    if not secret:
        return jsonify(error="request_unavailable"), 503
    if (not isinstance(username, str) or not 1 <= len(username.strip()) <= 50
            or not isinstance(email, str) or "@" not in email or len(email.strip()) > 100
            or not isinstance(full_name, str) or not 1 <= len(full_name.strip()) <= 100
            or not isinstance(note, str) or len(note) > 500
            or not isinstance(requested_role, str) or requested_role not in {ROLE_TECHNICIAN, ROLE_OPERATOR}):
        return jsonify(error="invalid_request"), 400
    source_ip_hash = hashlib.sha256((secret + (request.remote_addr or "unknown")).encode()).hexdigest()
    try:
        db.session.execute(
            text("""
                EXEC dbo.usp_request_account_access
                    @username=:username, @email=:email, @full_name=:full_name,
                    @requested_role=:requested_role, @note=:note, @source_ip_hash=:source_ip_hash
            """),
            {
                "username": username.strip(),
                "email": email.strip(),
                "full_name": full_name.strip(),
                "requested_role": requested_role,
                "note": note.strip(),
                "source_ip_hash": source_ip_hash,
            },
        )
        db.session.commit()
    except DBAPIError as exc:
        db.session.rollback()
        if "5111" in str(exc.orig):
            return jsonify(error="request_already_exists"), 409
        return jsonify(error="request_unavailable"), 503
    return jsonify(status="request_submitted"), 201


@auth_bp.post("/change-password")
@require_roles()
def change_password():
    payload = request.get_json(silent=True)
    current = payload.get("current_password") if isinstance(payload, dict) else None
    new = payload.get("new_password") if isinstance(payload, dict) else None
    if not isinstance(current, str) or not isinstance(new, str) or not 12 <= len(new) <= 128:
        return jsonify(error="invalid_password"), 400
    try:
        user = db.session.execute(text("{CALL dbo.usp_authenticate_user (:username)}"),
                                  {"username": g.current_user["username"]}).mappings().first()
        if not user or not check_password_hash(user["password_hash"], current):
            return jsonify(error="current_password_incorrect"), 400
        db.session.execute(text("{CALL dbo.usp_change_own_password (:user_id, :new_password_hash)}"),
                           {"user_id": user["user_id"], "new_password_hash": generate_password_hash(new)})
        db.session.commit()
    except DBAPIError:
        db.session.rollback()
        return jsonify(error="password_change_unavailable"), 503
    return jsonify(status="password_changed"), 200


@auth_bp.get("/sessions")
@require_roles()
def list_sessions():
    rows = db.session.execute(text("{CALL dbo.usp_list_auth_sessions (:user_id)}"),
                              {"user_id": g.current_user["user_id"]}).mappings().all()
    return jsonify([{"current": row["jti"].strip() == g.current_user["jti"],
                     "issued_at": row["issued_at"], "expires_at": row["expires_at"]} for row in rows]), 200


@auth_bp.post("/sessions/revoke-others")
@require_roles()
def revoke_other_sessions():
    db.session.execute(text("{CALL dbo.usp_revoke_other_auth_sessions (:user_id, :current_jti)}"),
                       {"user_id": g.current_user["user_id"], "current_jti": g.current_user["jti"]})
    db.session.commit()
    return jsonify(status="sessions_revoked"), 200


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
    otp = payload.get("otp")
    if not (isinstance(username, str) and 1 <= len(username) <= 50
            and isinstance(password, str) and 1 <= len(password) <= 128):
        return jsonify({"error": "Can 2 truong: username (str), password (str)"}), 400

    try:
        user = db.session.execute(
            text("{CALL dbo.usp_authenticate_user (:username)}"),
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

    if user.get("mfa_enabled"):
        if not isinstance(otp, str):
            return jsonify(error="mfa_required"), 401
        try:
            secret = _decrypt_mfa(user["user_id"], user["mfa_secret_encrypted"])
            valid = _check_totp(secret, otp)
            if not valid:
                valid = _consume_mfa_backup_code(user["user_id"], otp)
        except (ValueError, ImportError):
            return jsonify(error="mfa_unavailable"), 503
        if not valid:
            return jsonify(error="invalid_mfa_code"), 401

    try:
        access_token = _issue_token(user)
    except DBAPIError:
        db.session.rollback()
        return jsonify(error="Loi may chu"), 503
    return jsonify({
        "access_token": access_token,
        "token_type": "Bearer",
        "expires_in": JWT_EXPIRES_MINUTES * 60,
        "user": {"id": user["user_id"], "username": user["username"],
                 "full_name": user["full_name"], "role": user["role_name"]},
    }), 200


@auth_bp.post("/logout")
@require_roles()
def logout():
    try:
        db.session.execute(
            text("{CALL dbo.usp_revoke_auth_session (:jti, :user_id)}"),
            {"jti": g.current_user["jti"], "user_id": g.current_user["user_id"]},
        )
        db.session.commit()
    except DBAPIError:
        db.session.rollback()
        return jsonify(error="logout_unavailable"), 503
    return jsonify(status="logged_out"), 200


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


_DEV_DEMO_USERS = ("admin", "operator", "technician")
_DEV_PASSWORD_PLACEHOLDER = "replace-with-local-dev-password"


def sync_dev_passwords(app) -> None:
    """Dong bo mat khau dev tu bien moi truong AR_IMMS_DEV_PASSWORD cho 3 user mau."""
    if (
        os.environ.get("FLASK_ENV", "").strip().lower() == "production"
        or os.environ.get("AR_IMMS_ENV", "").strip().lower() == "production"
    ):
        return
    dev_password = (os.environ.get("AR_IMMS_DEV_PASSWORD") or "").strip()
    if not dev_password or dev_password == _DEV_PASSWORD_PLACEHOLDER or len(dev_password) < 8:
        return
    with app.app_context():
        try:
            changed = False
            for username in _DEV_DEMO_USERS:
                row = db.session.execute(
                    text("{CALL dbo.usp_authenticate_user (:username)}"),
                    {"username": username},
                ).mappings().first()
                if not row:
                    continue
                try:
                    matches = check_password_hash(row["password_hash"], dev_password)
                except ValueError:
                    matches = False
                if not matches:
                    db.session.execute(
                        text("{CALL dbo.usp_set_user_password_hash (:u, :h)}"),
                        {"u": username, "h": generate_password_hash(dev_password)},
                    )
                    changed = True
            if changed:
                db.session.commit()
            else:
                db.session.rollback()
        except DBAPIError:
            db.session.rollback()
            app.logger.warning("Skipping dev password sync: database unavailable or schema not ready")
