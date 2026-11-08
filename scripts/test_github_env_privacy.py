#!/usr/bin/env python3
"""Synthetic CLI tests: no real credentials or GitHub writes."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class GithubEnvironmentPrivacyTests(unittest.TestCase):
    def test_public_url_credentials_and_ambiguous_query_stay_private(self):
        with tempfile.TemporaryDirectory(prefix="biomate-url-contract-") as temp:
            root = Path(temp)
            (root / "scripts").mkdir()
            (root / "deploy").mkdir()
            shutil.copyfile(Path(__file__).with_name("setup_github_env.sh"), root / "scripts/setup_github_env.sh")
            (root / "deploy/biomate.env.manifest").write_text("APP_URL\n")
            for value, expected in (
                ("https://example.test", "variable"),
                ("HTTPS://example.test?API_KEY=PRIVATE_CANARY", "secret"),
                ("https://example.test?%61pi_key=PRIVATE_CANARY", "secret"),
                ("https://example.test#access_token=PRIVATE_CANARY", "secret"),
                ("https://example.test?arbitrary=PRIVATE_CANARY", "secret"),
                ("https://user:PRIVATE_CANARY@example.test", "secret"),
            ):
                with self.subTest(value=value.split("PRIVATE_CANARY")[0]):
                    source = root / "fixture.env"
                    source.write_text("APP_URL=" + value + "\n")
                    result = subprocess.run(["bash", str(root / "scripts/setup_github_env.sh"),
                                             str(source), "--dry-run"], capture_output=True, text=True, timeout=10)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn("WOULD set " + expected, result.stdout)
                    self.assertNotIn("PRIVATE_CANARY", result.stdout + result.stderr)

    def test_secret_by_default_and_values_only_on_stdin(self):
        with tempfile.TemporaryDirectory(prefix="biomate-env-contract-") as temp:
            root = Path(temp)
            (root / "scripts").mkdir()
            (root / "deploy").mkdir()
            shutil.copyfile(Path(__file__).with_name("setup_github_env.sh"), root / "scripts/setup_github_env.sh")
            names = ["GOOGLE_API_KEY", "LLM_API_KEY", "CRYOSPARC_LICENSE", "UNREVIEWED_SETTING", "DATABASE_URL", "AWS_REGION", "APP_URL", "EMPTY"]
            (root / "deploy/biomate.env.manifest").write_text("\n".join(names) + "\n")
            canary = "SYNTHETIC_PRIVATE_VALUE_DO_NOT_PUBLISH"
            values = {name: canary for name in names}
            values.update(AWS_REGION="us-west-2", APP_URL="https://user:" + canary + "@internal.example", EMPTY="")
            source = root / "fixture.env"
            source.write_text("\n".join(name + "=" + value for name, value in values.items()) + "\n")
            fake = root / "gh"
            fake.write_text("#!/usr/bin/env python3\nimport json,os,sys\nif sys.argv[1:]==['auth','status']: sys.exit(0)\ndata=sys.stdin.read()\nwith open(os.environ['FIXTURE_CALLS'],'a') as out: out.write(json.dumps({'args':sys.argv[1:],'stdin_matches':data==os.environ['FIXTURE_EXPECTED_'+sys.argv[3]]})+'\\n')\n")
            fake.chmod(0o700)
            calls = root / "calls.jsonl"
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ["PATH"], FIXTURE_CALLS=str(calls))
            env.update({"FIXTURE_EXPECTED_" + key: value for key, value in values.items()})
            command = ["bash", str(root / "scripts/setup_github_env.sh"), str(source), "--repo", "fixture/repo"]
            result = subprocess.run(command, env=env, text=True, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn(canary, result.stdout + result.stderr + calls.read_text())
            records = [json.loads(line) for line in calls.read_text().splitlines()]
            self.assertEqual(len(records), len(names) - 1)
            for record in records:
                args = record["args"]
                self.assertTrue(record["stdin_matches"])
                self.assertNotIn("--body", args)
                self.assertEqual(args[0], "variable" if args[2] == "AWS_REGION" else "secret")
                self.assertEqual(args[-2:], ["--repo", "fixture/repo"])
            calls.unlink()
            preview = subprocess.run(command + ["--dry-run"], env=env, text=True, capture_output=True, timeout=10)
            self.assertEqual(preview.returncode, 0, preview.stderr)
            self.assertFalse(calls.exists(), "dry run must not call GitHub")
            self.assertNotIn(canary, preview.stdout + preview.stderr)


if __name__ == "__main__":
    unittest.main()
