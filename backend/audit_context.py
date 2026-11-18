"""Truyen nguoi dung hien tai vao SESSION_CONTEXT cua SQL Server de trigger audit ghi dung nguoi.

Moi transaction bat dau thi dat lai user/ip cho ket noi dang dung (NULL neu khong co nguoi dang nhap),
nen ket noi tai su dung trong pool khong bao gio giu nguoi cu. Chi goi stored procedure."""
from flask import g, has_request_context, request
from sqlalchemy import event
from sqlalchemy.orm import Session


@event.listens_for(Session, "after_begin")
def _set_audit_context(session, transaction, connection):
    user_id = username = ip_address = None
    if has_request_context():
        ip_address = request.remote_addr
        user = g.get("current_user")
        if user:
            user_id = user["user_id"]
            username = user["username"]
    connection.exec_driver_sql(
        "EXEC dbo.usp_set_audit_context ?, ?, ?", (user_id, username, ip_address)
    )