"""Demo HQTCSDL-41: dang nhap 3 vai va goi API trai quyen (can Flask dang chay).
Mat khau lay tu bien moi truong AR_IMMS_DEV_PASSWORD, khong luu trong repo."""
import json
import os
import sys
import urllib.error
import urllib.request

BASE = os.environ.get("API_BASE", "http://localhost:5000")
PASSWORD = os.environ.get("AR_IMMS_DEV_PASSWORD")
USERS = ("admin", "operator", "technician")
ENDPOINTS = ("/auth/demo/admin", "/auth/demo/operations", "/auth/demo/field")


def call(method, path, body=None, token=None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(BASE + path, data=data, method=method)
    request.add_header("Content-Type", "application/json")
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(request) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, json.load(error)


def main():
    if not PASSWORD:
        sys.exit("Dat bien moi truong AR_IMMS_DEV_PASSWORD truoc")

    print(f"{'user':<12}{'role':<18}" + "".join(f"{p.rsplit('/', 1)[1]:<12}" for p in ENDPOINTS))
    for username in USERS:
        status, body = call("POST", "/auth/login", {"username": username, "password": PASSWORD})
        if status != 200:
            sys.exit(f"Dang nhap {username} that bai: {status}")
        token = body["access_token"]
        codes = [call("GET", path, token=token)[0] for path in ENDPOINTS]
        print(f"{username:<12}{body['user']['role']:<18}" + "".join(f"{c:<12}" for c in codes))

    print()
    print("Sai mat khau       ->", call("POST", "/auth/login", {"username": "admin", "password": "sai"})[0])
    print("Khong co token     ->", call("GET", "/auth/me")[0])
    print("Token khong hop le ->", call("GET", "/auth/me", token="khong.phai.token")[0])


if __name__ == "__main__":
    main()