"""Dat mat khau DEV cho 3 user mau (admin, operator, technician).
Mat khau nhap luc chay, KHONG luu vao repo. Chi dung cho moi truong dev.
Chay lai sau moi lan 00_reset + seed (seed lam mat hash)."""
import getpass
import os
import sys

from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from werkzeug.security import generate_password_hash

DEV_USERS = ("admin", "operator", "technician")


def main() -> None:
    load_dotenv()
    database_url = os.environ.get("DATABASE_URL")
    if not database_url:
        sys.exit("Thieu DATABASE_URL trong .env")

    password = getpass.getpass("Mat khau dev (it nhat 8 ky tu): ")
    if len(password) < 8:
        sys.exit("Mat khau qua ngan")
    if password != getpass.getpass("Nhap lai: "):
        sys.exit("Hai lan nhap khong khop")

    engine = create_engine(database_url)
    with engine.begin() as connection:
        for username in DEV_USERS:
            connection.execute(
                text("EXEC dbo.usp_set_user_password_hash @username = :u, @password_hash = :h"),
                {"u": username, "h": generate_password_hash(password)},
            )
            print(f"Da dat mat khau cho {username}")


if __name__ == "__main__":
    main()