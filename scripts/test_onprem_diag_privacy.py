#!/usr/bin/env python3
"""Privacy unit/CLI contract tests with synthetic commands; not live Docker E2E."""
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
import unittest

from onprem_diag_privacy import env_summary, inspect_summary

SCRIPTS = Path(__file__).resolve().parent
CANARY = "SYNTHETIC_PRIVATE_VALUE_MUST_NOT_LEAK"


class DiagnosticPrivacyTests(unittest.TestCase):
    def test_inspect_projects_only_allowlisted_metadata(self):
        data = [{"Id": "a" * 64, "RestartCount": 3, "Config": {"Env": ["DATABASE_URL=" + CANARY], "Labels": {"patient": CANARY}, "Cmd": [CANARY]},
                 "Mounts": [{"Source": CANARY}], "State": {"Status": "running", "ExitCode": 0,
                 "Error": CANARY, "Health": {"Status": "unhealthy", "Log": [{"Output": CANARY, "ExitCode": 7}]}}}]
        output = inspect_summary(data)
        self.assertNotIn(CANARY, json.dumps(output))
        self.assertEqual(output[0]["health_exit_codes"], [7])
        self.assertEqual(output[0]["restart_count"], 3)

    def test_arbitrary_status_fields_cannot_export_values(self):
        output = inspect_summary([{"Id": CANARY, "RestartCount": CANARY,
                                   "State": {"Status": CANARY, "ExitCode": CANARY, "Health": {"Status": CANARY}}}])
        self.assertNotIn(CANARY, json.dumps(output))

    def test_environment_is_names_and_presence_only(self):
        text = "# " + CANARY + "\nEMAIL_PASS=" + CANARY + "\nDATABASE_URL=" + CANARY + "\nCUSTOM_SETTING=" + CANARY + "\nEMPTY=\nexport JWT_SECRET=" + CANARY + "\nmalformed " + CANARY
        output = env_summary(text)
        self.assertNotIn(CANARY, output)
        self.assertEqual(output.splitlines(), ["EMAIL_PASS=set", "DATABASE_URL=set", "CUSTOM_SETTING=set", "EMPTY=empty", "JWT_SECRET=set"])

    def test_malformed_payload_fails_without_echoing_input(self):
        result = subprocess.run(["python3", str(SCRIPTS / "onprem_diag_privacy.py"), "inspect"], input=CANARY, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(CANARY, result.stdout + result.stderr)

    def test_sensitive_mode_requires_explicit_authorization(self):
        result = subprocess.run(["bash", str(SCRIPTS / "diag-onprem.sh"), "--include-sensitive"], text=True, capture_output=True)
        self.assertEqual(result.returncode, 2)

    def test_default_cli_bundle_excludes_raw_payloads(self):
        # Real shell script + real JSON projection, with synthetic Docker/curl
        # fixtures. This proves the CLI privacy contract, not a live deployment.
        with tempfile.TemporaryDirectory(prefix="biomate-diag-fixture-") as fixture:
            directory = Path(fixture)
            (directory / ".env").write_text("DATABASE_URL=" + CANARY + "\nEMAIL_PASS=" + CANARY + "\n# " + CANARY + "\n")
            docker = directory / "docker"
            payload = json.dumps([{"Id": "a" * 64, "Config": {"Env": ["DATABASE_URL=" + CANARY]}, "State": {"Status": "running", "Health": {"Status": "unhealthy", "Log": [{"Output": CANARY, "ExitCode": 1}]}}}])
            docker.write_text("#!/bin/sh\ncase \"$1\" in\ninspect)\n if [ \"$2\" = --format ]; then\n  case \"$3\" in *Health.Status*) echo unhealthy;; *State.Status*) echo running;; *RestartCount*) echo 0;; *Config.Image*) echo biomate/frontend:test;; *) echo fixture;; esac\n else\n  printf '%s\\n' '" + payload + "'\n fi;;\nlogs) echo '" + CANARY + "';;\n*) echo fixture;;\nesac\n")
            curl = directory / "curl"
            curl.write_text("#!/bin/sh\nfor arg in \"$@\"; do if [ \"$arg\" = -w ]; then printf 200; exit 0; fi; done\nfor arg in \"$@\"; do if [ \"$arg\" = -o ]; then exit 0; fi; done\necho '" + CANARY + "'\n")
            for path in (docker, curl):
                path.chmod(0o700)
            env = dict(os.environ, PATH=str(directory) + os.pathsep + os.environ["PATH"])
            result = subprocess.run(["bash", str(SCRIPTS / "diag-onprem.sh"), "--no-pack"], cwd=directory, env=env, text=True, capture_output=True, timeout=45)
            match = re.search(r"诊断目录: (/tmp/biomate-diag-[^\s]+)", result.stdout)
            self.assertIsNotNone(match, result.stderr)
            output = Path(match[1])
            self.assertEqual(output.parent, Path("/tmp"))
            try:
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn(CANARY, result.stdout + result.stderr)
                self.assertFalse(Path(str(output) + ".tar.gz").exists())
                self.assertFalse((output / "logs").exists())
                self.assertFalse((output / "recent-runs.txt").exists())
                self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o700)
                for path in output.rglob("*"):
                    if path.is_file():
                        self.assertNotIn(CANARY, path.read_text(), str(path))
            finally:
                # Only this test's validated newly-created diagnostic directory.
                shutil.rmtree(output)


if __name__ == "__main__":
    unittest.main()
