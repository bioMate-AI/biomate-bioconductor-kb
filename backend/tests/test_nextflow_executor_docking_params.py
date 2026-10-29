"""
Guard: the docking param-provisioning CLASS stays closed end-to-end.

Query that must work: "dock imatinib against PDB 1IEP, box center [15,34,46],
box size 25, Vina". Three root causes (verified live 2026-10-29, run 24b2968d):

1. Receptor staged to HOST, not S3. A bare PDB id ("1IEP") classified as a
   `structure` accession was host-prefetched to a Galaxy-local path and that path
   substituted into the AWS Batch command — invisible to the Batch container.
   Fix: on Batch, when the workflow self-fetches the id (docking_autodock_vina has
   fetch_pdb()/files.rcsb.org + an s3 cp branch), SKIP the host prefetch and pass
   the bare id through so the .nf fetch fires (mirrors native-SRA pass-through).

2. Box params not bracketed. Extractor emits box_center='15,34,46' / box_size='25';
   the .nf needs a JSON 3-vector. Fix: _coerce_box_vector normalizes CSV/scalar →
   vector (scalar box_size → cube [v,v,v]); valid JSON arrays pass through.

3. Drug NAME not SMILES. Extractor emits smiles_list='imatinib'; RDKit rejects it.
   Fix: reuse the existing PubChem resolver (galaxy.ai.federated_query.
   resolve_chemical_name) at the executor boundary; unresolved names raise 422
   rather than silently docking garbage.

No heavy imports (fastapi/galaxy unavailable in plain CI) — this reads the executor
source + the docking .nf and AST-extracts the pure box helper to exercise its logic.
"""
import ast
import re
from pathlib import Path

BACKEND = Path(__file__).resolve().parents[1]
EXECUTOR = BACKEND / "lib/galaxy/webapps/galaxy/api/nextflow_executor.py"
DOCKING_NF = (
    BACKEND
    / "biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/docking_autodock_vina/main.nf"
)
FEDERATED = BACKEND / "lib/galaxy/ai/federated_query.py"

_STRUCTURE_SIGNALS = r"files\.rcsb\.org|fetch_pdb|rcsb\.org/download|emdb/structures"


# ── Fix 1: receptor host-prefetch skip on Batch ───────────────────────────────

def test_structure_native_helper_defined():
    src = EXECUTOR.read_text()
    assert "def _workflow_fetches_structure_natively(" in src, "structure self-fetch helper missing"


def test_detection_skips_host_prefetch_for_batch_structure():
    src = EXECUTOR.read_text()
    assert '_workflow_fetches_structure_natively(str(nf_path))' in src, \
        "detection must call the structure self-fetch helper"
    # Must be gated on Batch (host path is only invisible on Batch) and on handler==structure.
    assert re.search(r'info\["handler"\]\s*==\s*"structure"', src), "skip must be scoped to structure handler"
    assert "skipping host prefetch" in src, "detection must skip host prefetch for self-fetching workflows"


def test_docking_nf_actually_self_fetches():
    # Functional check: the helper's signals must match the real docking workflow,
    # else the skip never fires and the receptor regresses to a dead host path on Batch.
    assert DOCKING_NF.is_file(), "docking workflow missing or relocated — update this test; never silently pass"
    assert re.search(_STRUCTURE_SIGNALS, DOCKING_NF.read_text(), re.IGNORECASE), \
        "docking .nf no longer matches structure self-fetch signals — update the helper regex"


def test_embedded_fetch_uses_canonical_rcsb_url_and_real_receptor_param(monkeypatch):
    """Exercise the real embedded helper; only the external RCSB download is replaced."""
    import urllib.request
    source = DOCKING_NF.read_text()
    assert "export PARAM_RECEPTOR_PDB='${params.receptor_pdb_file}'" in source
    embedded = source.split("python3 << 'PYEOF'", 1)[1].split("\nPYEOF", 1)[0]
    tree = ast.parse(embedded)
    helper = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'fetch_pdb')
    calls = []
    monkeypatch.setattr(urllib.request, 'urlretrieve', lambda url, dest: calls.append((url, dest)))
    scope = {}
    exec(compile(ast.Module(body=[helper], type_ignores=[]), '<docking fetch_pdb>', 'exec'), scope)
    scope['fetch_pdb']('1iep', '/tmp/test-receptor.pdb')
    assert calls == [('https://files.rcsb.org/download/1IEP.pdb', '/tmp/test-receptor.pdb')]


# ── Fix 2: box vector coercion (logic) ────────────────────────────────────────

def _load_coerce_box_vector():
    """AST-extract _coerce_box_vector from the executor and exec it in isolation
    (the full module can't import without fastapi/galaxy)."""
    tree = ast.parse(EXECUTOR.read_text())
    fn_src = None
    for node in tree.body:
        if isinstance(node, ast.FunctionDef) and node.name == "_coerce_box_vector":
            fn_src = ast.get_source_segment(EXECUTOR.read_text(), node)
            break
    assert fn_src, "_coerce_box_vector not found in executor source"
    from typing import Any, Optional
    ns = {"re": re, "Any": Any, "Optional": Optional}
    exec(fn_src, ns)
    return ns["_coerce_box_vector"]


def test_box_vector_coercion_logic():
    coerce = _load_coerce_box_vector()
    # CSV string → vector
    assert coerce("15,34,46", fill_scalar=False) == [15.0, 34.0, 46.0]
    # whitespace string → vector
    assert coerce("15 34 46", fill_scalar=False) == [15.0, 34.0, 46.0]
    # scalar box_size → cube
    assert coerce("25", fill_scalar=True) == [25.0, 25.0, 25.0]
    assert coerce(25, fill_scalar=True) == [25.0, 25.0, 25.0]
    # already-valid JSON array passes through (normalized to floats)
    assert coerce("[15, 34, 46]", fill_scalar=False) == [15.0, 34.0, 46.0]
    assert coerce([15, 34, 46], fill_scalar=False) == [15.0, 34.0, 46.0]
    # garbage / non-numeric → None (left untouched by caller)
    assert coerce("not-a-box", fill_scalar=False) is None
    assert coerce("", fill_scalar=True) is None
    assert coerce(True, fill_scalar=True) is None  # bool is not a box


def test_normalize_docking_wires_box_and_smiles():
    src = EXECUTOR.read_text()
    assert "def _normalize_docking_params(" in src
    assert "_normalize_docking_params(params)" in src, "chokepoint must call the normalizer"
    assert "def _resolve_smiles_list_param(" in src


# ── Fix 3: name→SMILES resolver is REUSED, not rebuilt ────────────────────────

def test_reuses_existing_pubchem_resolver():
    src = EXECUTOR.read_text()
    assert "from galaxy.ai.federated_query import" in src, "must import the shared resolver"
    assert "resolve_chemical_name" in src, "must reuse resolve_chemical_name"
    # The resolver it reuses must actually exist.
    fed = FEDERATED.read_text()
    assert "def resolve_chemical_name(" in fed, "shared PubChem resolver missing in federated_query"


def test_unresolved_name_surfaces_422_not_silent():
    src = EXECUTOR.read_text()
    # Unresolved compound names must raise (422), never pass a bare name to RDKit.
    assert "Unresolved compound name(s) in smiles_list" in src
