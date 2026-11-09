#!/usr/bin/env python3
"""Exercise actual Docker RUN install commands with a failing package manager.

These checks do not replace full image builds or native runtime qualification.
"""
import ast
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
FOLDER = ROOT / "backend/docker/workflow-tools"


def commands(text):
    # These Dockerfiles use ordinary shell-form RUN instructions.
    normalized = re.sub(r"\\\n", " ", text)
    return [line[4:] for line in normalized.splitlines() if line.startswith("RUN ")]


def with_failed_pip(command):
    return subprocess.run(["/bin/sh", "-c", "pip() { return 73; };\n" + command],
                          capture_output=True, text=True, timeout=5)


class WorkflowImageBuildGates(unittest.TestCase):
    def test_every_real_pip_install_propagates_failure(self):
        for filename in ("Dockerfile", "Dockerfile.onprem"):
            installs = [cmd for cmd in commands((FOLDER / filename).read_text()) if "pip install" in cmd]
            self.assertGreaterEqual(len(installs), 8)
            for command in installs:
                with self.subTest(file=filename, command=command):
                    self.assertEqual(with_failed_pip(command).returncode, 73)

    def test_previous_swallowed_failure_is_detectable(self):
        # Regression mutation: the old shell clause really returns success.
        result = with_failed_pip('pip install missing-package || echo "WARNING: degraded"')
        self.assertEqual(result.returncode, 0)
        self.assertIn("WARNING", result.stdout)
        actual = [cmd for cmd in commands((FOLDER / "Dockerfile.onprem").read_text())
                  if "descriptastorus" in cmd]
        self.assertEqual(len(actual), 1)
        self.assertNotEqual(with_failed_pip(actual[0]).returncode, result.returncode)
        self.assertRegex(actual[0], r"\bsix\b")

    def test_onprem_has_git_and_native_arm_build_dependencies(self):
        text = (FOLDER / "Dockerfile.onprem").read_text()
        apt = [cmd for cmd in commands(text) if "apt-get install" in cmd]
        self.assertTrue(any(re.search(r"\bgit\b", cmd) for cmd in apt))
        self.assertTrue(any('"$TARGETARCH" = "arm64"' in cmd
                            and "build-essential" in cmd and "libboost-all-dev" in cmd for cmd in apt))
        self.assertIn("ARG TARGETARCH", text)
        self.assertIn("FROM python:3.11-slim-bookworm", text)

    def test_smoke_and_publication_do_not_only_check_process_existence(self):
        smoke = (FOLDER / "smoke.py").read_text()
        ast.parse(smoke)
        for term in ("calculate_physicochemical_properties", "physicochemical_properties.csv",
                     'properties["Molecular Weight"]', 'invalid.startswith("ERROR:")', "math.isfinite"):
            self.assertIn(term, smoke)
        workflow = (ROOT / ".github/workflows/build-workflow-tools-onprem-image.yml").read_text()
        self.assertIn("id: publish", workflow)
        self.assertIn('if [[ "${{ steps.publish.outcome }}" == "success" ]]', workflow)
        self.assertIn("ARM64 still requires native qualification", workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
