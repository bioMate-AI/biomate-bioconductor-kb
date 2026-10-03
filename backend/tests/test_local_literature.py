import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import sys
import types

spec = importlib.util.spec_from_file_location("local_literature", Path(__file__).parents[1] / "lib/galaxy/ai/local_literature.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class LiteratureTests(unittest.TestCase):
    def test_identified_index_search_preserves_citations_and_excludes_anonymous_text(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "literature.sqlite"
            rows = [{"pmcid": "PMC123", "pmid": "456", "text": "RNA normalization and batch effects. " * 200,
                     "licence": "by", "year": 2022},
                    {"pmcid": "PMC124", "text": "Pharmacology and absorption."},
                    {"text": "Unidentified RNA normalization text."}]
            report = module.build(io.StringIO("\n".join(map(json.dumps, rows + [rows[0]]))), path)
            self.assertEqual(report["documents"], 2)
            self.assertEqual(report["missing_identity"], 1)
            self.assertEqual(report["duplicate_articles"], 1)
            before = path.read_bytes()
            result = module.search(path, 'RNA normalization"; DROP TABLE documents; --')
            self.assertEqual(result[0]["pmcid"], "PMC123")
            self.assertEqual(len(result), 1)
            self.assertEqual(result[0]["url"], "https://pmc.ncbi.nlm.nih.gov/articles/PMC123/")
            self.assertEqual(before, path.read_bytes())
            resolved = module.resolve(path, "https://www.ebi.ac.uk/europepmc/webservices/rest/search?query=RNA")
            self.assertEqual(resolved["resultList"]["result"][0]["evidence_kind"], "local_fulltext_excerpt")
            with self.assertRaises(FileExistsError):
                module.build(io.StringIO(""), path)

    def test_empty_or_anonymous_index_is_not_ready(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "literature.sqlite"
            with self.assertRaisesRegex(ValueError, "no identified"):
                module.build(io.StringIO('{"text":"anonymous"}'), path)
            self.assertFalse(path.with_suffix(".sqlite.manifest.json").exists())

    def test_federated_offline_literature_uses_local_citation_without_network(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "literature.sqlite"
            module.build(io.StringIO(json.dumps({"pmcid": "PMC123", "text": "RNA normalization."})), path)
            package = types.ModuleType("literature_fixture")
            package.__path__ = [str(Path(spec.origin).parent)]
            fq_spec = importlib.util.spec_from_file_location(
                "literature_fixture.federated_query", Path(spec.origin).with_name("federated_query.py"))
            fq = importlib.util.module_from_spec(fq_spec)
            with patch.dict(sys.modules, {"literature_fixture": package,
                                          "literature_fixture.local_literature": module}), \
                 patch.dict("os.environ", {"BIOMATE_OFFLINE_MODE": "1", "BIOMATE_LITERATURE_SQLITE": str(path)}), \
                 patch("urllib.request.urlopen", side_effect=AssertionError("network forbidden")):
                fq_spec.loader.exec_module(fq)
                result = fq._fetch_europepmc("RNA")["results"][0]
                self.assertEqual(result["pmcid"], "PMC123")
                self.assertEqual(result["evidence_kind"], "local_fulltext_excerpt")
                self.assertIn("PMC123", result["full_text_url"])
