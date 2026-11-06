import json
import unittest
from unittest.mock import patch
from execution_grader import content_ok, terminal_ok


class ExecutionGraderTests(unittest.TestCase):
    def test_completed_without_execution_receipt_is_not_success(self):
        self.assertFalse(terminal_ok({'execution': {'status': 'completed'}})[0])
        for receipt in [{'returncode': 0}, {'status': 'succeeded'}]:
            self.assertTrue(terminal_ok({'execution': {'status': 'completed', 'nextflowStatus': receipt}})[0])

    def test_complete_large_json_is_checked(self):
        payload = json.dumps({'items': ['x' * 5000]}).encode()
        with patch('execution_grader.subprocess.check_output', return_value=payload):
            self.assertTrue(content_ok({'name': 'result.json', 's3_uri': 's3://fixture/result'})[0])
        with patch('execution_grader.subprocess.check_output', return_value=payload + b' invalid tail'):
            self.assertFalse(content_ok({'name': 'result.json', 's3_uri': 's3://fixture/result'})[0])
