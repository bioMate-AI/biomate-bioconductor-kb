import json
from pathlib import Path
import subprocess
import sys
import unittest


class PMCProvenanceTests(unittest.TestCase):
    def filter(self, metadata):
        row = {"text": "publication date: 2022 Subjects: review\n"
                       "https://creativecommons.org/licenses/by/4.0/\nAbstract " + "Concept background. " * 120,
               **metadata}
        result = subprocess.run([sys.executable, str(Path(__file__).with_name("pmc_filter.py"))],
                                input=json.dumps(row) + "\n", capture_output=True, text=True, check=True)
        return json.loads(result.stdout)

    def test_preserves_article_identity_and_family(self):
        metadata = {"pmcid": "PMC123", "source_uri": "s3://example/PMC123.txt",
                    "source_family": "PMC123", "source_sha256": "example-digest"}
        result = self.filter(metadata)
        for key, value in metadata.items():
            self.assertEqual(result[key], value)
        self.assertEqual(result["provenance_status"], "identified")

    def test_legacy_corpus_does_not_get_invented_citation(self):
        result = self.filter({})
        self.assertEqual(result["provenance_status"], "missing_upstream_identifier")
        self.assertNotIn("pmcid", result)
