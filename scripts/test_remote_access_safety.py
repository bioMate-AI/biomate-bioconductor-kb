#!/usr/bin/env python3
"""Real shell entry point with synthetic clients; never opens a tunnel."""
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("remote-access.sh")


class RemoteAccessSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="biomate-remote-fixture-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.secret = self.root / "credential"
        self.secret.write_text("PRIVATE_CANARY")
        self.secret.chmod(0o600)
        self.env = dict(os.environ, XDG_STATE_HOME=str(self.root / "state"),
                        PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        FIXTURE_CALLS=str(self.root / "calls"), FIXTURE_STARTED=str(self.root / "started"),
                        FIXTURE_ARGS=str(self.root / "args"),
                        FIXTURE_INITIAL="NeedsLogin", FIXTURE_AFTER="Running", FIXTURE_UP_FAIL="0",
                        FIXTURE_DOCKER_EXISTS="0")
        self.state = self.root / "state/biomate-remote-access"
        self.client("sleep", "#!/bin/sh\nexit 0\n")
        self.client("sudo", '#!/bin/sh\nexec "$@"\n')
        self.client("tailscale", '''#!/usr/bin/env python3
import json,os,pathlib,sys
op=sys.argv[1]
with open(os.environ['FIXTURE_CALLS'],'a') as out: out.write(op+'\\n')
with open(os.environ['FIXTURE_ARGS'],'a') as out: out.write(json.dumps(sys.argv[1:])+'\\n')
if op=='status':
 state=os.environ['FIXTURE_AFTER'] if pathlib.Path(os.environ['FIXTURE_STARTED']).exists() else os.environ['FIXTURE_INITIAL']
 print(json.dumps({'BackendState':state,'Self':{'ID':'node-fixture'}}))
elif op=='up':
 if os.environ['FIXTURE_UP_FAIL']=='1': sys.exit(23)
 pathlib.Path(os.environ['FIXTURE_STARTED']).touch()
elif op=='ip': print('100.64.0.1')
''')
        self.client("docker", '''#!/usr/bin/env python3
import os,sys
with open(os.environ['FIXTURE_CALLS'],'a') as out: out.write('docker:'+sys.argv[1]+'\\n')
sys.exit(0 if os.environ['FIXTURE_DOCKER_EXISTS']=='1' else 1)
''')

    def client(self, name, text):
        path = self.bin / name
        path.write_text(text)
        path.chmod(0o700)

    def run_cli(self, *args):
        result = subprocess.run(["bash", str(SCRIPT), *args], env=self.env,
                                capture_output=True, text=True, timeout=10)
        self.assertNotIn("PRIVATE_CANARY", result.stdout + result.stderr)
        return result

    def calls(self):
        path = self.root / "calls"
        return path.read_text().splitlines() if path.exists() else []

    def test_stop_without_owned_session_leaves_host_clients_untouched(self):
        self.assertEqual(self.run_cli("stop").returncode, 0)
        self.assertEqual(self.calls(), [])
        self.assertEqual(stat.S_IMODE(self.state.stat().st_mode), 0o700)

    def test_failed_up_never_prints_or_records_success(self):
        self.env["FIXTURE_UP_FAIL"] = "1"
        result = self.run_cli("tailscale", "--key-file", str(self.secret))
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("接入成功", result.stdout)
        self.assertFalse((self.state / "state").exists())
        self.assertEqual(stat.S_IMODE((self.state / "tailscale.log").stat().st_mode), 0o600)

    def test_existing_running_host_session_is_not_taken_over(self):
        self.env["FIXTURE_INITIAL"] = "Running"
        result = self.run_cli("tailscale", "--key-file", str(self.secret))
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("up", self.calls())
        self.assertNotIn("down", self.calls())

    def test_up_zero_without_running_node_remains_pending_not_success(self):
        self.env["FIXTURE_AFTER"] = "NeedsLogin"
        result = self.run_cli("tailscale", "--key-file", str(self.secret))
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("接入成功", result.stdout)
        self.assertEqual((self.state / "state").read_text().strip(), "tailscale_pending")

    def test_confirmed_node_gets_private_ownership_record(self):
        result = self.run_cli("tailscale", "--key-file", str(self.secret))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.state / "state").read_text().strip(), "tailscale")
        self.assertEqual((self.state / "tailscale-node-id").read_text().strip(), "node-fixture")
        self.assertEqual(stat.S_IMODE((self.state / "tailscale-node-id").stat().st_mode), 0o600)
        args = (self.root / "args").read_text()
        self.assertNotIn("PRIVATE_CANARY", args)
        self.assertIn("--auth-key=file:", args)
        self.assertEqual(list(self.state.glob("credential.*")), [])

    def test_mismatched_node_is_not_disconnected(self):
        self.state.mkdir(parents=True, mode=0o700)
        (self.state / "state").write_text("tailscale\n")
        (self.state / "tailscale-node-id").write_text("different-node\n")
        self.assertNotEqual(self.run_cli("stop").returncode, 0)
        self.assertNotIn("down", self.calls())
        self.assertTrue((self.state / "state").exists())

    def test_symlink_state_is_rejected(self):
        self.state.parent.mkdir(parents=True)
        self.state.symlink_to(self.bin, target_is_directory=True)
        self.assertNotEqual(self.run_cli("status").returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_cloudflare_does_not_delete_preexisting_named_container(self):
        self.env["FIXTURE_DOCKER_EXISTS"] = "1"
        self.assertNotEqual(self.run_cli("cloudflare", "--token-file", str(self.secret)).returncode, 0)
        self.assertEqual(self.calls(), ["docker:inspect"])

    def test_unqualified_quick_ssh_does_not_launch_any_container(self):
        self.assertNotEqual(self.run_cli("cloudflare", "--quick").returncode, 0)
        self.assertEqual(self.calls(), ["docker:inspect"])

    def test_unknown_flags_fail_before_client_calls(self):
        for mode in ("tailscale", "frp", "cloudflare"):
            with self.subTest(mode=mode):
                self.assertNotEqual(self.run_cli(mode, "--typo").returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_insecure_or_symlink_secret_source_is_rejected(self):
        self.secret.chmod(0o644)
        self.assertNotEqual(self.run_cli("tailscale", "--key-file", str(self.secret)).returncode, 0)
        self.assertNotIn("up", self.calls())
        self.secret.chmod(0o600)
        linked = self.root / "linked-secret"
        linked.symlink_to(self.secret)
        self.assertNotEqual(self.run_cli("tailscale", "--key-file", str(linked)).returncode, 0)
        self.assertNotIn("up", self.calls())
        self.assertEqual(list(self.state.glob("credential.*")), [])

    def test_plaintext_credential_options_are_rejected_without_echo(self):
        for mode, option in (("tailscale", "--key"), ("frp", "--token"), ("cloudflare", "--token")):
            with self.subTest(mode=mode):
                self.assertNotEqual(self.run_cli(mode, option, "PRIVATE_CANARY").returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_cloudflare_requires_immutable_qualified_image(self):
        result = self.run_cli("cloudflare", "--token-file", str(self.secret),
                              "--image", "cloudflare/cloudflared:latest")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), ["docker:inspect"])
        self.assertFalse((self.state / "cloudflare.token").exists())

    def test_cloudflare_uses_private_file_and_does_not_claim_access_validation(self):
        self.client("docker", '''#!/usr/bin/env python3
import json,os,sys
with open(os.environ['FIXTURE_ARGS'],'a') as out: out.write(json.dumps(sys.argv[1:])+'\\n')
if sys.argv[1]=='inspect': sys.exit(1)
if sys.argv[1]=='ps': print('biomate-cloudflared')
''')
        result = self.run_cli("cloudflare", "--token-file", str(self.secret),
                              "--image", "cloudflare/cloudflared@sha256:" + "a" * 64)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("尚不代表 SSH 或 Access 验证通过", result.stdout)
        args = (self.root / "args").read_text()
        self.assertNotIn("PRIVATE_CANARY", args)
        self.assertIn('"--token-file", "/run/biomate-support-token"', args)
        self.assertIn('"--pull", "never"', args)
        self.assertEqual((self.state / "cloudflare.token").read_text(), "PRIVATE_CANARY")
        self.assertEqual(stat.S_IMODE((self.state / "cloudflare.token").stat().st_mode), 0o600)

    def test_unrelated_pid_record_is_not_killed(self):
        self.state.mkdir(parents=True, mode=0o700)
        (self.state / "state").write_text("frp\n")
        (self.state / "frpc.pid").write_text("1\n")
        self.client("ps", "#!/bin/sh\nprintf '%s\\n' unrelated-service\n")
        self.assertNotEqual(self.run_cli("stop").returncode, 0)
        self.assertTrue((self.state / "frpc.pid").exists())

    def test_new_connection_cannot_replace_recorded_session(self):
        self.state.mkdir(parents=True, mode=0o700)
        (self.state / "state").write_text("frp\n")
        self.assertNotEqual(self.run_cli("tailscale", "--key-file", str(self.secret)).returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_existing_operation_lock_blocks_all_client_changes(self):
        self.state.mkdir(parents=True, mode=0o700)
        (self.state / "operation.lock").mkdir(mode=0o700)
        self.assertNotEqual(self.run_cli("stop").returncode, 0)
        self.assertEqual(self.calls(), [])
        self.assertTrue((self.state / "operation.lock").is_dir())

    def test_matching_owned_node_can_stop_and_releases_lock(self):
        self.state.mkdir(parents=True, mode=0o700)
        (self.state / "state").write_text("tailscale\n")
        (self.state / "tailscale-node-id").write_text("node-fixture\n")
        self.assertEqual(self.run_cli("stop").returncode, 0)
        self.assertIn("down", self.calls())
        self.assertFalse((self.state / "state").exists())
        self.assertFalse((self.state / "tailscale-node-id").exists())
        self.assertFalse((self.state / "operation.lock").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
