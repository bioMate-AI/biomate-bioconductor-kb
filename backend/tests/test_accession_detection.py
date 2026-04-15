"""
Unit tests for public-database accession detection in nextflow_executor.py

Tests the _classify_accession / _is_public_accession functions and the
_validate_input_paths accession-skip logic without standing up Galaxy.
"""
import importlib.util
import re
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import MagicMock

# ── Load nextflow_executor.py with a unique module name to avoid clashing ──
# with mocked galaxy.* packages.
_NF_EXEC_PATH = (
    Path(__file__).parents[1]
    / "lib/galaxy/webapps/galaxy/api/nextflow_executor.py"
)

# Build stub modules only in sys.modules under fake names so we can still
# use importlib to load the real file.
def _make_stub(name: str) -> types.ModuleType:
    m = types.ModuleType(name)
    m.__spec__ = None
    return m

for _sname in [
    "galaxy", "galaxy.managers", "galaxy.managers.context",
    "galaxy.webapps", "galaxy.webapps.galaxy",
    "a2wsgi", "a2wsgi.wsgi", "dotenv",
]:
    sys.modules.setdefault(_sname, _make_stub(_sname))

# galaxy.managers.context needs ProvidesUserContext attribute
_ctx_stub = sys.modules["galaxy.managers.context"]
if not hasattr(_ctx_stub, "ProvidesUserContext"):
    _ctx_stub.ProvidesUserContext = object

# Stub pydantic.BaseModel (used as a base class)
_pydantic_stub = _make_stub("pydantic")
_pydantic_stub.BaseModel = object
sys.modules["pydantic"] = _pydantic_stub

# Stub fastapi with an HTTPException that is a real Exception subclass
class _FakeHTTPException(Exception):
    def __init__(self, status_code=None, detail=None):
        self.status_code = status_code
        self.detail = detail

_fastapi_stub = _make_stub("fastapi")
_fastapi_stub.HTTPException = _FakeHTTPException
_fastapi_stub.responses = _make_stub("fastapi.responses")
_fastapi_stub.responses.HTMLResponse = MagicMock()
sys.modules["fastapi"] = _fastapi_stub
sys.modules["fastapi.responses"] = _fastapi_stub.responses

# Stub galaxy.webapps.galaxy.api — must be a module (not MagicMock) so
# the `from galaxy.webapps.galaxy.api import Router, DependsOnTrans` import works
_gwa_api_stub = _make_stub("galaxy.webapps.galaxy.api")
_gwa_api_stub.Router = MagicMock(return_value=MagicMock(
    post=MagicMock(return_value=lambda f: f),
    get=MagicMock(return_value=lambda f: f),
))
_gwa_api_stub.DependsOnTrans = None
sys.modules["galaxy.webapps.galaxy.api"] = _gwa_api_stub

# Now load the executor module under a private name
_spec = importlib.util.spec_from_file_location("_nf_executor_under_test", _NF_EXEC_PATH)
_nf_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_nf_mod)  # type: ignore[union-attr]

_classify_accession = _nf_mod._classify_accession
_is_public_accession = _nf_mod._is_public_accession
_ACCESSION_REGISTRY = _nf_mod._ACCESSION_REGISTRY
_validate_input_paths = _nf_mod._validate_input_paths
_FakeHTTPException_ref = _FakeHTTPException


class TestAccessionClassification(unittest.TestCase):
    """Verify _classify_accession correctly identifies all accession types."""

    # ── Sequencing / raw reads ─────────────────────────────────────────────
    def test_sra_srr(self):
        info = _classify_accession("SRR628582")
        self.assertIsNotNone(info)
        self.assertEqual(info["handler"], "sequencing")
        self.assertEqual(info["label"], "SRA run")

    def test_sra_err(self):
        info = _classify_accession("ERR1234567")
        self.assertIsNotNone(info)
        self.assertEqual(info["handler"], "sequencing")

    def test_sra_drr(self):
        info = _classify_accession("DRR123456")
        self.assertIsNotNone(info)
        self.assertEqual(info["handler"], "sequencing")

    def test_ena_erp(self):
        info = _classify_accession("ERP123456")
        self.assertIsNotNone(info)
        self.assertEqual(info["handler"], "sequencing")

    def test_sra_srp(self):
        info = _classify_accession("SRP123456")
        self.assertIsNotNone(info)
        self.assertEqual(info["handler"], "sequencing")

    def test_bioproject_prjna(self):
        info = _classify_accession("PRJNA12345")
        self.assertIsNotNone(info)
        self.assertEqual(info["handler"], "sequencing")

    def test_bioproject_prjeb(self):
        info = _classify_accession("PRJEB12345")
        self.assertIsNotNone(info)
        self.assertEqual(info["handler"], "sequencing")

    def test_geo_series(self):
        info = _classify_accession("GSE12345")
        self.assertIsNotNone(info)
        self.assertEqual(info["handler"], "sequencing")

    def test_geo_sample(self):
        info = _classify_accession("GSM123456")
        self.assertIsNotNone(info)
        self.assertEqual(info["handler"], "sequencing")

    def test_arrayexpress_emtab(self):
        info = _classify_accession("E-MTAB-1234")
        self.assertIsNotNone(info)
        self.assertEqual(info["handler"], "sequencing")

    def test_arrayexpress_eatac(self):
        info = _classify_accession("E-GEOD-5678")
        self.assertIsNotNone(info)
        self.assertEqual(info["handler"], "sequencing")

    # ── Structure ──────────────────────────────────────────────────────────
    def test_pdb(self):
        for acc in ["4ZQK", "1ABC", "7NHX", "2ACE"]:
            with self.subTest(acc=acc):
                info = _classify_accession(acc)
                self.assertIsNotNone(info, f"Expected PDB match for {acc}")
                self.assertEqual(info["handler"], "structure")

    def test_emdb(self):
        info = _classify_accession("EMD-1234")
        self.assertIsNotNone(info)
        self.assertEqual(info["handler"], "structure")
        info2 = _classify_accession("EMD-12345")
        self.assertIsNotNone(info2)

    # ── Protein sequences ──────────────────────────────────────────────────
    def test_uniprot_reviewed(self):
        for acc in ["P12345", "Q9NR61", "O95644"]:
            with self.subTest(acc=acc):
                info = _classify_accession(acc)
                self.assertIsNotNone(info, f"Expected UniProt match for {acc}")
                self.assertEqual(info["handler"], "protein_seq")

    def test_refseq_protein_np(self):
        info = _classify_accession("NP_012345")
        self.assertIsNotNone(info)
        self.assertEqual(info["handler"], "protein_seq")

    def test_refseq_protein_xp(self):
        info = _classify_accession("XP_012345")
        self.assertIsNotNone(info)
        self.assertEqual(info["handler"], "protein_seq")

    def test_ensembl_protein(self):
        info = _classify_accession("ENSP00000269305")
        self.assertIsNotNone(info)
        self.assertEqual(info["handler"], "protein_seq")

    # ── Genomic references ─────────────────────────────────────────────────
    def test_refseq_nucleotide(self):
        info = _classify_accession("NC_000001")
        self.assertIsNotNone(info)
        self.assertEqual(info["handler"], "genomic_ref")

    def test_ensembl_gene(self):
        info = _classify_accession("ENSG00000141510")
        self.assertIsNotNone(info)
        self.assertEqual(info["handler"], "genomic_ref")

    def test_ensembl_transcript(self):
        info = _classify_accession("ENST00000269305")
        self.assertIsNotNone(info)
        self.assertEqual(info["handler"], "genomic_ref")

    # ── Proteomics ────────────────────────────────────────────────────────
    def test_pride_pxd(self):
        info = _classify_accession("PXD001234")
        self.assertIsNotNone(info)
        self.assertEqual(info["handler"], "proteomics")

    def test_massive_msv(self):
        info = _classify_accession("MSV000079033")
        self.assertIsNotNone(info)
        self.assertEqual(info["handler"], "proteomics")

    # ── Chemical / small molecules ────────────────────────────────────────
    def test_chembl(self):
        info = _classify_accession("CHEMBL25")
        self.assertIsNotNone(info)
        self.assertEqual(info["handler"], "chemical")

    def test_pubchem_cid(self):
        info = _classify_accession("CID2244")
        self.assertIsNotNone(info)
        self.assertEqual(info["handler"], "chemical")

    # ── Variant / annotation ──────────────────────────────────────────────
    def test_dbsnp_rs(self):
        info = _classify_accession("rs1234567")
        self.assertIsNotNone(info)
        self.assertEqual(info["handler"], "annotation")

    def test_clinvar_vcv(self):
        info = _classify_accession("VCV000012345")
        self.assertIsNotNone(info)
        self.assertEqual(info["handler"], "annotation")

    def test_clinvar_rcv(self):
        info = _classify_accession("RCV000012345")
        self.assertIsNotNone(info)
        self.assertEqual(info["handler"], "annotation")

    # ── Negative cases: should NOT match ──────────────────────────────────
    def test_local_path_not_matched(self):
        for val in ["/data/sample.fastq", "./reads/", "/home/user/input.bam"]:
            with self.subTest(val=val):
                self.assertIsNone(_classify_accession(val), f"Should not match path: {val}")

    def test_s3_url_not_matched(self):
        self.assertIsNone(_classify_accession("s3://my-bucket/input.fastq"))

    def test_http_url_not_matched(self):
        self.assertIsNone(_classify_accession("https://example.com/file.fasta"))

    def test_short_string_not_matched(self):
        for val in ["SRR", "AB", "rs"]:
            with self.subTest(val=val):
                self.assertIsNone(_classify_accession(val), f"Too short, should not match: {val}")

    def test_common_param_values_not_matched(self):
        for val in ["true", "false", "null", "none", "output", "docker", "1000"]:
            with self.subTest(val=val):
                self.assertIsNone(_classify_accession(val), f"Param value should not match: {val}")

    def test_gene_symbol_not_matched(self):
        # Short gene symbols like BRCA1, TP53 should not match
        for val in ["BRCA1", "TP53", "KRAS"]:
            with self.subTest(val=val):
                self.assertIsNone(_classify_accession(val), f"Gene symbol should not match: {val}")

    def test_none_not_matched(self):
        self.assertIsNone(_classify_accession(None))  # type: ignore[arg-type]

    def test_accession_normalised_uppercase(self):
        info = _classify_accession("srr628582")
        self.assertIsNotNone(info)
        self.assertEqual(info["accession"], "SRR628582")

    # ── _is_public_accession convenience wrapper ──────────────────────────
    def test_is_public_accession_true(self):
        self.assertTrue(_is_public_accession("SRR628582"))
        self.assertTrue(_is_public_accession("4ZQK"))
        self.assertTrue(_is_public_accession("P12345"))

    def test_is_public_accession_false(self):
        self.assertFalse(_is_public_accession("/path/to/file"))
        self.assertFalse(_is_public_accession("hello"))


class TestValidateInputPathsAccessionSkip(unittest.TestCase):
    """
    _validate_input_paths must silently skip recognised accession values
    instead of raising 422 for missing local files.
    """

    def test_sra_accession_skipped(self):
        """SRR accession in 'reads' param must not raise 422."""
        # Should not raise
        _validate_input_paths({"reads": "SRR628582", "outdir": "/tmp/out"})

    def test_pdb_accession_skipped(self):
        _validate_input_paths({"input": "4ZQK", "outdir": "/tmp/out"})

    def test_uniprot_accession_skipped(self):
        _validate_input_paths({"fasta": "P12345", "outdir": "/tmp/out"})

    def test_missing_local_path_still_raises(self):
        """A non-accession local path that doesn't exist must still raise 422."""
        with self.assertRaises(_FakeHTTPException_ref):
            _validate_input_paths({"reads": "/nonexistent/file.fastq"})


if __name__ == "__main__":
    unittest.main(verbosity=2)
