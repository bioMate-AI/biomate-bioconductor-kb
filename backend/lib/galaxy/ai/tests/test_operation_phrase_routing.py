"""
Operation-phrase routing: a between-group differential test must earn the operation bonus under
every surface form ("differential protein abundance", "differentially abundant proteins",
"differentially expressed genes"), not only the literal "differential expression".

Root cause reproduced (docs/20261110_COLDSTART_EXAMPLES_LIVE_AUDIT.md §4.2): "Quantify differential
protein abundance between my two groups." with a MaxQuant proteinGroups.txt routed to the
Chemoproteomics Pulldown enrichment-QC workflow, because no DE workflow matched the operation
phrase and the pulldown description shares the INPUT terms (MaxQuant, proteinGroups.txt).

The rows below are the real catalog texts (galaxy_ai_tools.db ids 10804 and 13106). The test needs
no database: it scores both rows with _calculate_score on identical search signals.

Run:
    cd backend && python -m pytest lib/galaxy/ai/tests/test_operation_phrase_routing.py -v
"""
import sys
from pathlib import Path

_AI_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(_AI_ROOT))
sys.path.insert(0, str(_AI_ROOT.parent.parent.parent))  # backend/lib/

import pytest

from unified_workflow_search import UnifiedWorkflowSearch, canonicalize_operation_phrases

QUERY = "Quantify differential protein abundance between my two groups."

PULLDOWN = dict(
    name="Chemoproteomics Pulldown",
    description=("proteomics/chemoproteomics_pulldown Chemoproteomics affinity enrichment (pulldown) QC. "
                 "Accepts a MaxQuant proteinGroups.txt (or equivalent CSV) from a bead-pulldown experiment "
                 "(ABPP, drug bead, BioID, etc.) and computes per-protein enrichment ratios (pulldown "
                 "intensity / input/control intensity)."),
    tools=[], tags=["proteomics", "biomni", "nextflow", "chemoproteomics_pulldown"],
    source="biomni_nextflow", workflow_domain="proteomics",
    input_kinds=frozenset({"protein_table"}), is_subworkflow=False, real_exec_status=None,
)
DEQMS_LFQ = dict(
    name="deqms_maxquant_lfq",
    description="Perform differential protein expression analysis using MaxQuant label-free quantification (LFQ) output.",
    tools=[], tags=["transcriptomics", "deqms", "maxquant", "lfq", "varianceboxplot"],
    source="bioconductor", workflow_domain="proteomics",
    input_kinds=frozenset({"protein_table"}), is_subworkflow=True, real_exec_status="fixture_failed",
)


@pytest.mark.parametrize("text", [
    "differential protein abundance",
    "differentially abundant proteins",
    "differentially expressed genes",
    "differential protein expression",
    "differential abundance",
])
def test_surface_forms_canonicalize_to_the_operation_phrase(text):
    assert "differential expression" in canonicalize_operation_phrases(text)


@pytest.mark.parametrize("text", [
    "differential localization of proteins",
    "differential splicing events",
    "an expression atlas",
])
def test_other_operations_are_untouched(text):
    assert canonicalize_operation_phrases(text) == text


def _score(search, row, fts_score):
    return search._calculate_score(
        QUERY, row["name"], row["description"], row["tools"], row["tags"], row["source"],
        row["workflow_domain"], fts_score, preferred_domains=["proteomics"], penalized_domains=[],
        input_types=None, input_kinds=row["input_kinds"], user_input_kinds=["protein_table"],
        is_subworkflow=row["is_subworkflow"], real_exec_status=row["real_exec_status"])


def test_de_request_ranks_the_de_workflow_above_the_pulldown(tmp_path):
    search = UnifiedWorkflowSearch(db_path=tmp_path / "empty.db")
    # bm25 of each row for the live request (query + classifier key_terms "MaxQuant",
    # "proteinGroups.txt", "LFQ intensity", "H vs L", ...) against the catalog FTS index: the pulldown
    # row matches the input-format terms slightly better, which is what made it win before.
    de, pulldown = _score(search, DEQMS_LFQ, -35.75), _score(search, PULLDOWN, -36.26)
    assert de > pulldown, (de, pulldown)
