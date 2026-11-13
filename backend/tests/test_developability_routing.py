"""Step 4 of the 2026-11-12 example-routing fix: a small-molecule "developability / rank these
candidates" request (SMILES library + receptor structure → {molecules, structure}) must NOT route
to the BCR-ABL1 CSV-assay ranker ("Assay Ingestion And Ranking", id 12814, input_kinds=[tabular]).

Three independent levers, all tested here deterministically (no DB / no FTS needed):
  (4a) _kinds_mismatch now treats the chemistry regime {molecules, structure} vs a table/reads/
       spectra-only workflow as a mismatch → step-8a penalty.
  (4b) developability / virtual-screening vocabulary was added so the correct workflows score.
  (4c) the blanket compound-RANKING boost is gated behind an actual assay table.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend" / "lib"))

from galaxy.ai.unified_workflow_search import UnifiedWorkflowSearch  # noqa: E402
from galaxy.ai.unified_workflow_search import _INPUT_KIND_MISMATCH_PENALTY as _PEN  # noqa: E402

INCIDENT_Q = "Rank these 500 candidates for developability and show me the top 20."


def _search(tmp_path):
    return UnifiedWorkflowSearch(db_path=tmp_path / "wf.db")


def _score(s, query, name, desc, wf_kinds, user_kinds):
    return s._calculate_score(query, name, desc, [], [], "drug_discovery", "drug_discovery", 0.0,
                              input_types=["input"], input_kinds=wf_kinds, user_input_kinds=user_kinds)


# ── 4a. chemistry-regime mismatch ────────────────────────────────────────────

def test_kinds_mismatch_chemistry_regime():
    mm = UnifiedWorkflowSearch._kinds_mismatch
    assert mm(frozenset({"molecules", "structure"}), frozenset({"tabular"})) is True
    assert mm(frozenset({"molecules"}), frozenset({"fastq"})) is True
    assert mm(frozenset({"tabular"}), frozenset({"molecules", "structure"})) is True
    # overlap → never a mismatch
    assert mm(frozenset({"molecules", "structure"}), frozenset({"molecules", "structure"})) is False
    assert mm(frozenset({"structure"}), frozenset({"structure"})) is False
    # mixed user shape (chemistry + a table) is NOT chem-only → conservative, no chem mismatch
    assert mm(frozenset({"molecules", "counts_matrix"}), frozenset({"tabular"})) is False


def test_chemistry_request_penalises_table_only_assay_ranker(tmp_path):
    s = _search(tmp_path)
    # The incident workflow (12814) is labelled {tabular}. A SMILES-library + receptor request
    # (→ {molecules, structure}) cannot feed it → full mismatch penalty.
    pen = (_score(s, INCIDENT_Q, "Assay Ingestion And Ranking", "parse csv assay data rank compounds", frozenset({"tabular"}), None)
           - _score(s, INCIDENT_Q, "Assay Ingestion And Ranking", "parse csv assay data rank compounds", frozenset({"tabular"}), ["molecules", "structure"]))
    assert pen == _PEN
    # A docking / VS workflow labelled {molecules, structure} is compatible → +3 overlap boost.
    boost = (_score(s, INCIDENT_Q, "Dock Ligands", "molecular docking of ligands against receptor", frozenset({"molecules", "structure"}), ["molecules", "structure"])
             - _score(s, INCIDENT_Q, "Dock Ligands", "molecular docking of ligands against receptor", frozenset({"molecules", "structure"}), None))
    assert boost == 3.0


def test_incident_assay_ranker_no_longer_outranks_the_chemistry_workflow(tmp_path):
    """Acceptance: with the user's {molecules, structure} shape known, the table-only assay ranker
    must score strictly BELOW a compatible chemistry workflow for the incident prompt."""
    s = _search(tmp_path)
    assay = _score(s, INCIDENT_Q, "Assay Ingestion And Ranking",
                   "ingest multi-assay compound data, parse csv assay data, composite score, rank compounds",
                   frozenset({"tabular"}), ["molecules", "structure"])
    chem = _score(s, INCIDENT_Q, "Small Molecule Developability",
                  "developability assessment and virtual screening of a smiles compound library",
                  frozenset({"molecules", "structure"}), ["molecules", "structure"])
    assert chem > assay, f"assay ranker ({assay:.1f}) must not beat the chemistry workflow ({chem:.1f})"


# ── 4c. ranking boost gated behind an actual assay table ──────────────────────

def test_ranking_verb_boost_requires_an_assay_table(tmp_path):
    s = _search(tmp_path)
    q = "rank compounds by composite score"  # contains the gated verb 'rank compounds'
    name, desc = "Ranker", "rank compounds composite"  # workflow text also contains it

    def sc(user_kinds):
        return s._calculate_score(q, name, desc, [], [], "drug_discovery", "drug_discovery", 0.0,
                                  input_types=["input"], input_kinds=None, user_input_kinds=user_kinds)

    # Chemistry request (no assay table) → the ranking verb is NOT boosted.
    base = sc(["molecules", "structure"])
    # The same request WITH an assay table (tabular) → +3.5 ranking boost applies.
    with_table = sc(["tabular"])
    assert with_table - base == 3.5


def test_ranking_boost_also_unlocked_by_assay_wording_in_the_query(tmp_path):
    s = _search(tmp_path)
    name, desc = "Ranker", "rank compounds composite"

    def sc(q):
        return s._calculate_score(q, name, desc, [], [], "drug_discovery", "drug_discovery", 0.0,
                                  input_types=["input"], input_kinds=None, user_input_kinds=None)

    assert sc("rank compounds from my assay data by IC50") - sc("rank compounds for me") == 3.5
