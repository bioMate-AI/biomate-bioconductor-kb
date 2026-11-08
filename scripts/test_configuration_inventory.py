#!/usr/bin/env python3
"""Extractor checks; these do not claim application deployment was tested."""
import unittest
from audit_onprem_configuration import extract


class InventoryTests(unittest.TestCase):
    def test_multiline_reads_and_source_lines(self):
        text = 'os.environ.get(\n "NXF_K8S_GPU_RESOURCE", "ignored-value")\nprocess.env["LLM_API_KEY"]\n'
        found = extract(text)
        self.assertIn(("NXF_K8S_GPU_RESOURCE", 1, "python-read"), found)
        self.assertIn(("LLM_API_KEY", 3, "node-read"), found)
        self.assertNotIn("ignored-value", str(found))

    def test_destructuring_and_build_time(self):
        text = 'const {\n JWT_SECRET: secret,\n SESSION_SECRET = "not-output"\n} = process.env;\nconst x = import.meta.env.VITE_ONPREM;'
        names = {x[0] for x in extract(text)}
        self.assertEqual(names, {"JWT_SECRET", "SESSION_SECRET", "VITE_ONPREM"})

    def test_comments_and_escaped_compose(self):
        text = '# process.env.DO_NOT_INCLUDE\n// os.getenv("ALSO_NOT")\n${HOST_INPUT:-default} $${CONTAINER_LOCAL}\nSystem.getenv("BIOMATE_ADMET_CONTAINER")'
        found = extract(text)
        self.assertEqual({x[0] for x in found}, {"HOST_INPUT", "BIOMATE_ADMET_CONTAINER"})


if __name__ == "__main__":
    unittest.main()
