#!/usr/bin/env python3
"""Real Compose/template wiring checks; not scheduler execution qualification."""
from pathlib import Path
import re
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]


class OnpremConfigurationContractTests(unittest.TestCase):
    def test_documented_cluster_settings_are_injected_into_backend(self):
        template = (ROOT / ".env.onprem.example").read_text()
        names = set(re.findall(r"(?m)^\s*(?:#\s*)?((?:SLURM|NXF_K8S)_[A-Z_]+)=", template))
        self.assertGreaterEqual(len(names), 10, "fixture must contain actual documented cluster settings")
        compose = yaml.safe_load((ROOT / "docker-compose.onprem.yml").read_text())
        backend = compose["services"]["biomate-engine"]["environment"]
        for name in names:
            self.assertIn(name, backend, name)
            self.assertTrue(backend[name].startswith("${" + name + ":-"), name)

    def test_google_filter_is_runtime_wired_and_documented(self):
        compose = yaml.safe_load((ROOT / "docker-compose.onprem.yml").read_text())
        self.assertEqual(compose["services"]["frontend"]["environment"]["DISABLE_GOOGLE_FONTS"], "${DISABLE_GOOGLE_FONTS:-true}")
        self.assertIn("DISABLE_GOOGLE_FONTS=true", (ROOT / ".env.onprem.example").read_text())


if __name__ == "__main__":
    unittest.main()
