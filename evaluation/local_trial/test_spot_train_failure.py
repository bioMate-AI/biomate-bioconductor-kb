"""Prove a failed CPT cannot be reported as a successful merge/SFT pipeline."""
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import unittest


class TrainingFailureTests(unittest.TestCase):
    def test_cpt_failure_stops_merge_sft_and_final_publication(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "models/base_small").mkdir(parents=True)
            commands = {
                "aws": 'echo "$*" >> "$CALLS"; if [ "$1 $2" = "s3 ls" ]; then exit 1; fi; exit 0',
                "nvidia-smi": 'echo "GPU 0: mock"',
                "python3": 'echo "$*" >> "$CALLS"; exit 42',
                "curl": 'exit 1',
            }
            bindir = root / "bin"
            bindir.mkdir()
            for name, body in commands.items():
                path = bindir / name
                path.write_text("#!/bin/bash\n" + body + "\n")
                path.chmod(0o755)
            env = dict(os.environ, PATH=f"{bindir}:/usr/bin:/bin", SCRATCH=str(root),
                       CALLS=str(root / "calls"), TRAIN_LOG=str(root / "train.log"),
                       MODEL_SIZE="small", STAGE="full", TAG="_failuretest",
                       FETCH_REPLAY="0", MIX_LITERATURE="0", FORCE_NGPU="1")
            with (root / "stdout").open("w") as output:
                proc = subprocess.Popen(["bash", str(Path(__file__).with_name("spot_train.sh"))],
                                        env=env, stdout=output, stderr=output, start_new_session=True)
                try:
                    self.assertEqual(proc.wait(timeout=15), 42, (root / "stdout").read_text())
                finally:
                    try:
                        os.killpg(proc.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
            calls = (root / "calls").read_text()
            self.assertIn("midtrain_run.py", calls)
            self.assertNotIn("merge_lora.py", calls)
            self.assertNotIn("train_qlora_pilot.py", calls)
            self.assertNotIn("SPOT_full", (root / "stdout").read_text())
            self.assertNotIn("full_failuretest_adapter", calls)
