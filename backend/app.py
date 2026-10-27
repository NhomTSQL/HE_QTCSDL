import os

from dotenv import load_dotenv
from flask import Flask, jsonify
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy import text
from sqlalchemy.engine import make_url


db = SQLAlchemy()


load_dotenv()


def create_app() -> Flask:
    app = Flask(__name__)
    database_url = os.environ.get("DATABASE_URL")
    if not database_url:
        raise RuntimeError("DATABASE_URL is required; configure SQL Server in .env")

    url = make_url(database_url)
    app.config["SQLALCHEMY_DATABASE_URI"] = url.render_as_string(hide_password=False)
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {"pool_pre_ping": True}
    db.init_app(app)

    @app.get("/health")
    def health_check():
        try:
            with db.engine.connect() as connection:
                connection.execute(text("SELECT 1"))
        except Exception:
            app.logger.exception("SQL Server health check failed")
            return jsonify({"status": "unhealthy", "database": "unavailable"}), 503
        return jsonify({"status": "healthy", "database": "connected"}), 200

    return app


if __name__ == "__main__":
    create_app().run(host="0.0.0.0", port=int(os.environ.get("PORT", "5000")), debug=True)
