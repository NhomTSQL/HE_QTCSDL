import os
import unittest
from unittest.mock import patch

from backend.core.config import load_database_config
from backend.app import create_app


class AppConfigurationTests(unittest.TestCase):
    def test_load_database_config_requires_database_url(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(RuntimeError, "DATABASE_URL is required"):
                load_database_config()

    def test_load_database_config_returns_database_url_and_pool_options(self):
        database_url = "mssql+pyodbc://user:pass@localhost/db?driver=ODBC+Driver+18+for+SQL+Server"
        with patch.dict(os.environ, {"DATABASE_URL": database_url}, clear=True):
            config = load_database_config()

        self.assertEqual(config["SQLALCHEMY_DATABASE_URI"], database_url)
        self.assertEqual(config["SQLALCHEMY_ENGINE_OPTIONS"]["pool_size"], 15)
        self.assertEqual(config["SQLALCHEMY_ENGINE_OPTIONS"]["max_overflow"], 25)
        self.assertTrue(config["SQLALCHEMY_ENGINE_OPTIONS"]["pool_pre_ping"])

    def test_create_app_keeps_sql_server_pool_options(self):
        with patch.dict(
            os.environ,
            {"DATABASE_URL": "mssql+pyodbc://user:pass@localhost/db?driver=ODBC+Driver+18+for+SQL+Server"},
            clear=True,
        ), patch("backend.core.application.sync_dev_passwords"), patch("backend.core.application.install_security"):
            app = create_app()

        self.assertEqual(app.config["SQLALCHEMY_ENGINE_OPTIONS"]["pool_size"], 15)


if __name__ == "__main__":
    unittest.main()

