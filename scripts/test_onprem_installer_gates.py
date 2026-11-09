#!/usr/bin/env python3
"""Execute actual installer functions/required-image block with fake clients.

Never sources/runs the installer top level, installs software or changes hosts.
"""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(os.environ.get("BIOMATE_INSTALLER_TEST_SOURCE", str(ROOT / "install.sh"))).read_text()


def function(name):
    match = re.search(r"^" + re.escape(name) + r"\(\) \{\n.*?^\}\n", SOURCE, re.M | re.S)
    if not match:
        raise AssertionError("missing installer function: " + name)
    return match.group(0)


class InstallerGateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="biomate-installer-fixture-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = dict(os.environ, PATH=str(self.root) + os.pathsep + os.environ["PATH"],
                        FIXTURE_CALLS=str(self.root / "calls"), FIXTURE_STATE="true healthy",
                        FIXTURE_CURL_EXIT="0", FIXTURE_BODY='{"valid":true}', FIXTURE_ARCH="amd64",
                        FIXTURE_MISSING_IMAGE="0")
        self.client("docker", '''#!/usr/bin/env python3
import os,sys
with open(os.environ['FIXTURE_CALLS'],'a') as out: out.write(' '.join(sys.argv[1:])+'\\n')
if sys.argv[1]=='pull': sys.exit(1)
if os.environ['FIXTURE_MISSING_IMAGE']=='1': sys.exit(1)
args=' '.join(sys.argv)
if '.Architecture' in args: print(os.environ['FIXTURE_ARCH'])
elif '.State.Running' in args: print(os.environ['FIXTURE_STATE'])
elif '.State.Health.Status' in args:
 state=os.environ['FIXTURE_STATE'].split()[-1]
 if state in ('none','missing'): sys.exit(1)
 print(state)
else: print('{}')
''')
        self.client("curl", '''#!/usr/bin/env python3
import os,sys
print(os.environ['FIXTURE_BODY'])
sys.exit(int(os.environ['FIXTURE_CURL_EXIT']))
''')

    def client(self, name, text):
        path = self.root / name
        path.write_text(text)
        path.chmod(0o700)

    def run_code(self, code):
        prelude = "info(){ :; }; warn(){ :; }; ok(){ printf 'READY\\n'; }; error(){ printf 'FAILED\\n' >&2; }; die(){ error; exit 1; }; HOST_ARCH_NORM=amd64;\n"
        result = subprocess.run(["bash", "-euo", "pipefail", "-c", prelude + code],
                                env=self.env, capture_output=True, text=True, timeout=5)
        self.assertNotIn("PRIVATE_CANARY", result.stdout + result.stderr)
        return result

    def health(self):
        return self.run_code(function("_wait_healthy") + "\n_wait_healthy fixture-container 0\n")

    def test_only_running_and_healthy_passes(self):
        self.assertEqual(self.health().returncode, 0)
        for state in ("false healthy", "true none", "true unhealthy", "true starting", "missing", "healthy"):
            with self.subTest(state=state):
                self.env["FIXTURE_STATE"] = state
                result = self.health()
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("READY", result.stdout)
        self.assertNotIn("logs", (self.root / "calls").read_text())

    def test_missing_container_does_not_pass_an_existence_fallback(self):
        self.env["FIXTURE_MISSING_IMAGE"] = "1"
        self.assertNotEqual(self.health().returncode, 0)

    def test_failed_endpoint_propagates_failure(self):
        self.env["FIXTURE_CURL_EXIT"] = "22"
        result = self.run_code(function("_check_endpoint") + '\n_check_endpoint fixture http://localhost/health\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("READY", result.stdout)

    def test_license_requires_real_boolean_true_not_http_200(self):
        for body, expected in (('{"valid":true}', 0), ('{"valid":false}', 1),
                               ('{"valid":"true"}', 1), ('{"valid":1}', 1),
                               ('{}', 1), ('PRIVATE_CANARY', 1)):
            with self.subTest(expected=expected):
                self.env["FIXTURE_BODY"] = body
                result = self.run_code(function("_check_license") + '\n_check_license http://localhost/license\n')
                self.assertEqual(result.returncode, expected)

    def test_image_architecture_must_match_native_host(self):
        code = function("_check_image_architecture") + '\n_check_image_architecture fixture-image\n'
        self.assertEqual(self.run_code(code).returncode, 0)
        for architecture in ("arm64", "", "unknown"):
            with self.subTest(architecture=architecture):
                self.env["FIXTURE_ARCH"] = architecture
                self.assertNotEqual(self.run_code(code).returncode, 0)

    def test_required_workflow_image_failure_is_fatal(self):
        start = SOURCE.index('_WORKFLOW_REMOTE=')
        end = SOURCE.index('# 4. 创建 Nextflow 工作目录', start)
        self.env["FIXTURE_MISSING_IMAGE"] = "1"
        self.assertNotEqual(self.run_code(SOURCE[start:end]).returncode, 0)

    def test_no_automatic_privileged_binfmt_or_blanket_deployment_success(self):
        self.assertFalse("--privileged tonistiigi/binfmt" in SOURCE, "installer must not alter host binfmt automatically")
        self.assertFalse("BioMate 已成功部署！" in SOURCE, "basic checks are not full deployment acceptance")
        self.assertIn("这不是完整验收", SOURCE)
        self.assertIn("umask 077", SOURCE)
        self.assertIn('mktemp -d "${TMPDIR:-/tmp}/biomate-install.XXXXXX"', SOURCE)


if __name__ == "__main__":
    unittest.main(verbosity=2)
