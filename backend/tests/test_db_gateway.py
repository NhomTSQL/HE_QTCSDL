import unittest
from unittest.mock import Mock, patch

from backend.db.gateway import execute_procedure, rows


class DatabaseGatewayTests(unittest.TestCase):
    def test_execute_procedure_uses_shared_session_and_preserves_params(self):
        result = Mock()
        with patch("backend.db.gateway.db.session.execute", return_value=result) as execute:
            actual = execute_procedure("EXEC dbo.usp_example @id = :id", {"id": 7})

        self.assertIs(actual, result)
        self.assertEqual(str(execute.call_args.args[0]), "EXEC dbo.usp_example @id = :id")
        self.assertEqual(execute.call_args.args[1], {"id": 7})

    def test_rows_returns_mapping_rows_as_plain_dicts(self):
        mapping_result = Mock()
        mapping_result.mappings.return_value.all.return_value = [{"id": 7}]
        with patch("backend.db.gateway.execute_procedure", return_value=mapping_result):
            actual = rows("EXEC dbo.usp_list_example")

        self.assertEqual(actual, [{"id": 7}])
        self.assertIs(type(actual[0]), dict)


if __name__ == "__main__":
    unittest.main()

