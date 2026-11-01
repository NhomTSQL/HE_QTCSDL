# ============================================================================
# AR-IMMS: Hướng dẫn kết nối SQL Server cho Backend Flask
# ============================================================================
#
# THAY ĐỔI SO VỚI SOURCE GỐC (PostgreSQL Supabase):
#   - Database:      PostgreSQL → SQL Server
#   - Driver:        psycopg2  → pyodbc (hoặc pymssql)
#   - SQLAlchemy URI: postgresql://... → mssql+pyodbc://...
#
# ============================================================================

# === 1. CÀI ĐẶT SQL SERVER ===
#
# Chạy SQL Server bằng Docker trên Windows (24GB RAM đủ dùng):
#
#   docker run -d --name ar-imms-sqlserver \
#     -e "ACCEPT_EULA=Y" \
#     -e "MSSQL_SA_PASSWORD=YOUR_STRONG_PASSWORD" \
#     -e "MSSQL_PID=Developer" \
#     -p 1433:1433 \
#     mcr.microsoft.com/mssql/server:2022-latest
#
# Hoặc cài SQL Server Express trực tiếp trên Windows.

# === 2. CẤU HÌNH .env ===
#
# Thay đổi file .env từ PostgreSQL sang SQL Server:

# --- CŨ (PostgreSQL Supabase) ---
# POSTGRES_DATABASE_URL=postgresql://postgres:password@host:6543/postgres

# --- MỚI (SQL Server) ---
# Hình thức 1: Docker SQL Server (khuyến nghị)
SQLSERVER_HOST=localhost
SQLSERVER_PORT=1433
SQLSERVER_DATABASE=AR_IMMS
SQLSERVER_USER=sa
SQLSERVER_PASSWORD=YOUR_STRONG_PASSWORD

# Connection string cho SQLAlchemy (pyodbc)
DATABASE_URI=mssql+pyodbc://sa:YOUR_STRONG_PASSWORD@localhost:1433/AR_IMMS?driver=ODBC+Driver+17+for+SQL+Server&TrustServerCertificate=yes

# Hình thức 2: SQL Server Express local (Windows Authentication)
# DATABASE_URI=mssql+pyodbc://./AR_IMMS?driver=ODBC+Driver+17+for+SQL+Server&Trusted_Connection=yes

# === 3. THAY ĐỔI requirements.txt ===
#
# Xóa:  psycopg2-binary>=2.9.0
# Thêm: pyodbc>=5.0.0
#
# File requirements.txt mới:
#   Flask>=2.3.0
#   Flask-Cors>=4.0.0
#   Flask-SQLAlchemy>=3.0.0
#   Flask-SocketIO>=5.3.0
#   simple-websocket>=1.0.0
#   SQLAlchemy>=2.0.0
#   marshmallow>=3.20.0
#   PyJWT>=2.8.0
#   python-dotenv>=1.0.0
#   apispec>=6.3.0
#   apispec-webframeworks>=0.5.2
#   flask-swagger-ui>=4.11.1
#   werkzeug>=3.0.0
#   pyodbc>=5.0.0

# === 4. THAY ĐỔI core/config.py ===
#
# Thay dòng SQLALCHEMY_DATABASE_URI:
#
#   CŨ:
#     SQLALCHEMY_DATABASE_URI = os.environ.get("DATABASE_URI")
#         or os.environ.get("POSTGRES_DATABASE_URL")
#         or f"sqlite:///{DEFAULT_DB_PATH}"
#
#   MỚI:
#     SQLALCHEMY_DATABASE_URI = os.environ.get("DATABASE_URI")
#         or "mssql+pyodbc://sa:YOUR_STRONG_PASSWORD@localhost:1433/AR_IMMS"
#            "?driver=ODBC+Driver+17+for+SQL+Server&TrustServerCertificate=yes"

# === 5. CÀI ODBC DRIVER ===
#
# Windows: Tải và cài Microsoft ODBC Driver 17 for SQL Server
# https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server
#
# Kiểm tra đã cài:
#   python -c "import pyodbc; print(pyodbc.drivers())"
#   → Phải thấy: ['ODBC Driver 17 for SQL Server']

# === 6. CHẠY SCRIPT TẠO DATABASE ===
#
# Thứ tự chạy trong SQL Server Management Studio (SSMS) hoặc Azure Data Studio:
#   1. database/01_create_database.sql
#   2. database/02_create_tables.sql
#   3. database/03_seed_data.sql
#   4. database/04_procedures_triggers_views.sql
#   5. database/05_retention_policy.sql

# === 7. LƯU Ý KHÁC BIỆT SQL Server vs PostgreSQL ===
#
# | Tính năng            | PostgreSQL           | SQL Server                   |
# |----------------------|----------------------|------------------------------|
# | Auto-increment       | SERIAL               | IDENTITY(1,1)                |
# | Boolean              | BOOLEAN              | BIT                          |
# | Text dài             | TEXT                  | NVARCHAR(MAX)                |
# | Unicode string       | VARCHAR              | NVARCHAR (luôn dùng N'...')  |
# | JSON column          | JSONB (native)       | NVARCHAR(MAX) + JSON funcs   |
# | Datetime             | TIMESTAMP            | DATETIME2                    |
# | Now() UTC            | NOW() AT TIME ZONE   | SYSUTCDATETIME()             |
# | Cascade delete       | CASCADE              | CASCADE (giống)              |
# | String concat        | ||                   | + hoặc CONCAT()              |
# | Limit                | LIMIT N              | TOP N hoặc OFFSET...FETCH    |
