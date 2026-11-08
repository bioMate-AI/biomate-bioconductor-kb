import importlib.util
from contextlib import closing
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch
import sys
import types
from urllib.parse import quote

spec = importlib.util.spec_from_file_location(
    "local_compound_resolver", Path(__file__).parents[1] / "lib/galaxy/ai/local_compound_resolver.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class LocalCompoundTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / "chembl.db"
        with closing(sqlite3.connect(self.path)) as db:
            db.executescript("""
                CREATE TABLE molecule_dictionary(molregno,chembl_id,pref_name);
                CREATE TABLE compound_structures(molregno,canonical_smiles);
                CREATE TABLE molecule_properties(molregno,full_molformula,full_mwt);
                CREATE TABLE molecule_synonyms(molregno,synonyms);
                INSERT INTO molecule_dictionary VALUES(1,'CHEMBL_TEST','Synthetic compound');
                INSERT INTO compound_structures VALUES(1,'CC');
                INSERT INTO molecule_properties VALUES(1,'C2H6',30.07);
                INSERT INTO molecule_synonyms VALUES(1,'Test alias');
            """)

    def lookup(self, term):
        return module.resolve(self.path, "https://www.ebi.ac.uk/chembl/api/data/molecule/search?q=" + quote(term))

    def test_id_name_synonym_and_structure(self):
        for query in ("chembl_test", "Synthetic compound", "test alias"):
            self.assertEqual(self.lookup(query)["molecules"][0]["molecule_structures"]["canonical_smiles"], "CC")

    def test_unknown_and_sql_input_are_not_matches(self):
        before = self.path.read_bytes()
        for query in ("Synthetic", "' OR 1=1 --"):
            self.assertEqual(self.lookup(query), {"molecules": []})
        self.assertEqual(before, self.path.read_bytes())

    def test_missing_mirror_does_not_create_database(self):
        self.path.unlink()
        with self.assertRaises(sqlite3.OperationalError):
            self.lookup("test alias")
        self.assertFalse(self.path.exists())

    def test_unsupported_host_or_post_not_handled(self):
        self.assertIsNone(module.resolve(self.path, "https://example.com/chembl/api/data/molecule/search?q=test"))
        self.assertIsNone(module.resolve(self.path, "https://www.ebi.ac.uk/chembl/api/data/molecule/search?q=test", {}))

    def test_offline_federated_seam_never_opens_network(self):
        # Load the real seam without importing Galaxy's unrelated server dependencies.
        package = types.ModuleType("resolver_fixture")
        package.__path__ = [str(Path(spec.origin).parent)]
        fq_spec = importlib.util.spec_from_file_location(
            "resolver_fixture.federated_query", Path(spec.origin).with_name("federated_query.py"))
        fq = importlib.util.module_from_spec(fq_spec)
        with patch.dict(sys.modules, {"resolver_fixture": package,
                                    "resolver_fixture.local_compound_resolver": module}), \
             patch.dict("os.environ", {"BIOMATE_OFFLINE_MODE": "1", "BIOMATE_CHEMBL_SQLITE": str(self.path)}), \
             patch("urllib.request.urlopen", side_effect=AssertionError("network forbidden")):
            fq_spec.loader.exec_module(fq)
            self.assertEqual(fq._fetch_chembl("test alias")["results"][0]["smiles"], "CC")
            self.assertIsNone(fq._get("https://unsupported.example/query"))
            self.assertIsNone(fq._post_json("https://unsupported.example/query", {}))
            self.path.unlink()
            with self.assertLogs(fq.log, level="WARNING"):
                self.assertEqual(fq._fetch_chembl("test alias")["results"], [])
