import os

from sqlalchemy.engine import make_url


def load_database_config() -> dict:
    """Build SQL Server connection settings without opening a database connection."""
    database_url = os.environ.get("DATABASE_URL")
    if not database_url:
        raise RuntimeError("DATABASE_URL is required; configure SQL Server in .env")

    url = make_url(database_url)
    return {
        "SQLALCHEMY_DATABASE_URI": url.render_as_string(hide_password=False),
        "SQLALCHEMY_TRACK_MODIFICATIONS": False,
        "SQLALCHEMY_ENGINE_OPTIONS": {
            "pool_pre_ping": True,
            "pool_size": 15,
            "max_overflow": 25,
            "pool_recycle": 1800,
        },
    }

