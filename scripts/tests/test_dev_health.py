import importlib.util
import pathlib
import unittest

path = pathlib.Path(__file__).resolve().parents[1] / 'check_dev_health.py'
spec = importlib.util.spec_from_file_location('dev_health', path)
health = importlib.util.module_from_spec(spec)
spec.loader.exec_module(health)


class HealthChecks(unittest.TestCase):
    def test_rejects_successful_html_fallback(self):
        self.assertFalse(health.validate_health_response('/api/galaxy/version', 200, 'text/html', '<html>BioMate</html>'))

    def test_requires_actual_service_signals(self):
        for endpoint, body in [('/healthz', '{"ok":true}'), ('/api/biomate/health', '{"status":"ok","assistantReady":true}'), ('/api/galaxy/version', '{"version_major":"25.1"}')]:
            self.assertTrue(health.validate_health_response(endpoint, 200, 'application/json', body))
        self.assertFalse(health.validate_health_response('/api/biomate/health', 200, 'application/json', '{"status":"ok","assistantReady":false}'))
        self.assertFalse(health.validate_health_response('/api/galaxy/version', 200, 'application/json', '{"error":"unavailable"}'))


if __name__ == '__main__':
    unittest.main()
