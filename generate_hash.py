import bcrypt

accounts = [
    {"username": "admin", "password": "AdminPassword123!"},
    {"username": "operator", "password": "OperatorPassword123!"},
    {"username": "technician_levu", "password": "TechPassword123!"}
]

print("=" * 70)
print(f"{'USERNAME':<20} | {'RAW PASSWORD':<22} | {'HASHED PASSWORD'}")
print("=" * 70)

for acc in accounts:
    salt = bcrypt.gensalt(rounds=10)
    hashed_bytes = bcrypt.hashpw(acc["password"].encode('utf-8'), salt)
    hashed_str = hashed_bytes.decode('utf-8')
    print(f"{acc['username']:<20} | {acc['password']:<22} | {hashed_str}")

print("=" * 70)