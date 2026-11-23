import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]


class RepositoryStructureTests(unittest.TestCase):
    def test_backend_modules_are_grouped_by_responsibility(self):
        expected = (
            "backend/api/auth.py",
            "backend/api/dashboard.py",
            "backend/core/application.py",
            "backend/core/config.py",
            "backend/core/extensions.py",
            "backend/core/security.py",
            "backend/db/gateway.py",
            "backend/tools/load_test_ingest.py",
        )
        for relative_path in expected:
            self.assertTrue((ROOT / relative_path).is_file(), relative_path)

    def test_sql_scripts_are_grouped_without_renaming(self):
        expected = {
            "database/migrations/01_create_database.sql",
            "database/tests/06_verify_seed_data.sql",
            "database/benchmarks/21_performance_benchmark.sql",
            "database/operations/00_reset.sql",
        }
        self.assertTrue(all((ROOT / path).is_file() for path in expected))


if __name__ == "__main__":
    unittest.main()

