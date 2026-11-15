import datetime
import os
import unittest

import jwt

from app import create_app

# Mat khau dev da dat bang scripts/set_dev_passwords.py (dat qua bien moi truong, khong luu trong repo)
DEV_PASSWORD = os.environ.get("AR_IMMS_DEV_PASSWORD")

ROLES = {"admin": "ADMINISTRATOR", "operator": "SYSTEM_OPERATOR", "technician": "FIELD_TECHNICIAN"}
# endpoint -> cac user duoc phep (200); user con lai bi 403
ALLOWED = {
    "/auth/demo/admin": {"admin"},
    "/auth/demo/operations": {"admin", "operator"},
    "/auth/demo/field": {"admin", "technician"},
}


@unittest.skipUnless(DEV_PASSWORD, "Dat bien moi truong AR_IMMS_DEV_PASSWORD de chay test dang nhap")
class AuthApiTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = create_app()
        cls.client = cls.app.test_client()
        cls.tokens = {}
        for username in ROLES:
            resp = cls.client.post("/auth/login", json={"username": username, "password": DEV_PASSWORD})
            assert resp.status_code == 200, f"Dang nhap {username} that bai: {resp.status_code}"
            cls.tokens[username] = resp.get_json()["access_token"]

    @staticmethod
    def _bearer(token):
        return {"Authorization": f"Bearer {token}"}

    def test_login_returns_correct_role_for_three_users(self):
        for username, role in ROLES.items():
            resp = self.client.post("/auth/login", json={"username": username, "password": DEV_PASSWORD})
            self.assertEqual(resp.status_code, 200)
            self.assertEqual(resp.get_json()["user"]["role"], role)

    def test_wrong_password_rejected(self):
        resp = self.client.post("/auth/login", json={"username": "admin", "password": "sai-mat-khau"})
        self.assertEqual(resp.status_code, 401)

    def test_unknown_user_rejected(self):
        resp = self.client.post("/auth/login", json={"username": "khong-ton-tai", "password": DEV_PASSWORD})
        self.assertEqual(resp.status_code, 401)

    def test_bad_login_body_rejected(self):
        self.assertEqual(self.client.post("/auth/login", json={"username": "admin"}).status_code, 400)

    def test_role_matrix_403_and_200(self):
        for path, allowed in ALLOWED.items():
            for username in ROLES:
                with self.subTest(path=path, user=username):
                    resp = self.client.get(path, headers=self._bearer(self.tokens[username]))
                    self.assertEqual(resp.status_code, 200 if username in allowed else 403)

    def test_no_token_rejected(self):
        self.assertEqual(self.client.get("/auth/me").status_code, 401)

    def test_garbage_token_rejected(self):
        self.assertEqual(self.client.get("/auth/me", headers=self._bearer("khong.phai.token")).status_code, 401)

    def test_expired_token_rejected(self):
        past = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=5)
        token = jwt.encode(
            {"sub": "1", "username": "admin", "role": "ADMINISTRATOR", "exp": past},
            self.app.config["JWT_SECRET_KEY"],
            algorithm="HS256",
        )
        self.assertEqual(self.client.get("/auth/me", headers=self._bearer(token)).status_code, 401)


if __name__ == "__main__":
    unittest.main()