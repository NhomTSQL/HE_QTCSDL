import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class DatabaseStructureTests(unittest.TestCase):
    def test_canonical_scripts_exist(self):
        canonical_files = [
            "01_create_database.sql",
            "02_create_tables.sql",
            "03_seed_data.sql",
            "04_procedures_triggers_views.sql",
            "05_retention_policy.sql",
            "08_dev_node_api_key.sql",
            "09_auth_procedures.sql",
            "10_agent_job_heartbeat.sql",
            "12_backup_recovery_model.sql",
            "13_backup_jobs.sql",
            "14_backup_cleanup.sql",
            "16_alert_dedupe.sql",
            "17_dashboard_api_procedures.sql",
            "19_security_and_core_fixes.sql",
            "20_extended_features_procedures.sql",
            "22_scale_architecture.sql",
            "23_least_privilege_login.sql",
            "25_password_recovery.sql",
            "26_security_hardening.sql",
        ]
        for name in canonical_files:
            self.assertTrue((ROOT / "database" / "canonical" / name).is_file(), name)

    def test_verification_scripts_exist(self):
        verification_files = [
            ("tests", "06_verify_seed_data.sql"),
            ("tests", "07_test_normalized_schema.sql"),
            ("tests", "11_test_heartbeat_job.sql"),
            ("tests", "18_test_retention_batch.sql"),
            ("benchmarks", "21_performance_benchmark.sql"),
            ("benchmarks", "24_scale_benchmark_1m.sql"),
            ("operations", "00_reset.sql"),
            ("operations", "15_restore_disaster_recovery.sql"),
        ]
        for folder, name in verification_files:
            self.assertTrue((ROOT / "database" / "verification" / folder / name).is_file(), name)

    def test_legacy_archive_exists(self):
        self.assertTrue((ROOT / "database" / "legacy" / "01_create_database.sql").is_file())
        self.assertTrue((ROOT / "database" / "legacy" / "26_security_hardening.sql").is_file())


if __name__ == "__main__":
    unittest.main()
