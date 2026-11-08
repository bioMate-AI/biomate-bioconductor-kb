import json
from pathlib import Path
import subprocess
import sys
import unittest
from pmc_filter import article_provenance


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

    def test_recovers_labeled_ids_from_legacy_bulk_header(self):
        result = article_provenance({"text": "JOURNAL INFORMATION === ARTICLE INFORMATION === "
                                  "PMCID: PMC123456 PMID: 987654 Article version: 1 Abstract Body"})
        self.assertEqual(result["pmcid"], "PMC123456")
        self.assertEqual(result["pmid"], "987654")
        self.assertEqual(result["source_family"], "PMC123456")
        self.assertEqual(article_provenance({"text": "Abstract References PMCID: PMC111"}), {})
