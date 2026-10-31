"""Campaign learning loop: observed assay scores drive the surrogate, and
rounds are allocated monotonically from one ledger (bo_proposals)."""
import sqlite3

import pytest

pytest.importorskip("numpy")
pytest.importorskip("sklearn")

from galaxy.ai.drug_discovery import auto_retrain as ar
from galaxy.ai.drug_discovery.auto_retrain import (
    CAMPAIGN_OBJECTIVE, RANKED_SCORE_KEY, CampaignDataError, build_training_rows,
    fit_campaign_optimizer, list_auto_proposals, persist_round, refit_and_propose,
    save_virtual_library,
)
from galaxy.ai.drug_discovery.assay_ingestion import COVERAGE_COMPLETE, COVERAGE_STATUS_KEY

LIBRARY = ["CCCC", "CCCO", "CCCN", "CCCl"]


@pytest.fixture(autouse=True)
def _isolated_audit(tmp_path, monkeypatch):
    monkeypatch.setenv("BIOMATE_COMPLIANCE_DB_DIR", str(tmp_path / "audit"))


def _csv(path, rows):
    header = "compound_id,smiles,assay_type,value,unit,assay_date,operator\n"
    path.write_text(header + "".join(",".join(r) + "\n" for r in rows))
    return str(path)


def _ingest(db, tmp_path, name, rows):
    from galaxy.ai.drug_discovery.assay_ingestion import AssayIngestionService
    return AssayIngestionService(db).ingest("camp", _csv(tmp_path / name, rows))


POTENCY = [("A", "CCO", "IC50", "1", "nM", "2026-10-01", "="),
           ("B", "CCN", "IC50", "10", "nM", "2026-10-01", "="),
           ("C", "CCC", "IC50", "100", "nM", "2026-10-01", "=")]
SAFETY = [("A", "CCO", "hERG", "1", "uM", "2026-10-02", "="),
          ("B", "CCN", "hERG", "50", "uM", "2026-10-02", "="),
          ("C", "CCC", "hERG", "25", "uM", "2026-10-02", "=")]


# --- score binding ----------------------------------------------------------

def test_ranked_compounds_expose_the_bound_score_key(tmp_path):
    """Contract with AssayIngestionService.get_ranked_compounds()."""
    from galaxy.ai.drug_discovery.assay_ingestion import AssayIngestionService
    db = str(tmp_path / "c.db")
    _ingest(db, tmp_path, "p.csv", POTENCY)
    ranked = AssayIngestionService(db).get_ranked_compounds("camp")
    assert ranked and all(RANKED_SCORE_KEY in r for r in ranked)
    rows = build_training_rows(ranked)
    assert rows.labels == [r[RANKED_SCORE_KEY] for r in ranked]
    assert len(set(rows.labels)) > 1


def _row(cid, smiles=None, score=None, coverage=COVERAGE_COMPLETE, **extra):
    r = {"compound_id": cid, COVERAGE_STATUS_KEY: coverage, **extra}
    if smiles is not None:
        r["smiles"] = smiles
    if score is not None:
        r[RANKED_SCORE_KEY] = score
    return r


def test_score_key_contract_is_owned_by_assay_ingestion():
    from galaxy.ai.drug_discovery import assay_ingestion
    assert ar.RANKED_SCORE_KEY is assay_ingestion.RANKED_SCORE_KEY


def test_missing_and_nonfinite_scores_are_skipped_and_reported():
    ranked = [
        _row("A", "CCO", 0.9),
        _row("B", "CCN", 0.1),
        _row("C", "CCC"),                                                      # no score
        _row("D", "CCCl", float("nan")),
        _row("E", score=0.5),                                                  # no SMILES
        _row("F", "CCBr", composite_score=0.7),                                # wrong key
    ]
    rows = build_training_rows(ranked)
    assert rows.compound_ids == ["A", "B"] and rows.labels == [0.9, 0.1]
    reasons = {s["compound_id"]: s["reason"] for s in rows.skipped}
    assert reasons == {"C": f"missing_{RANKED_SCORE_KEY}", "D": f"non_finite_{RANKED_SCORE_KEY}",
                       "E": "missing_smiles", "F": f"missing_{RANKED_SCORE_KEY}"}
    report = rows.report(len(ranked))
    assert report["n_used"] == 2 and report["n_ranked"] == 6 and report["warnings"]


def test_incomplete_or_unknown_coverage_never_becomes_a_label():
    ranked = [
        _row("A", "CCO", 0.9),
        _row("B", "CCN", 0.1),
        _row("D", "CCCl", 0.95, coverage="incomplete",
             measured_objectives=["potency"], missing_objectives=["safety"]),
        _row("E", "CCBr", 0.7, coverage=None),                                 # no coverage field
    ]
    rows = build_training_rows(ranked)
    assert rows.compound_ids == ["A", "B"]
    skipped = {s["compound_id"]: s for s in rows.skipped}
    assert skipped["D"] == {"compound_id": "D", "reason": f"{COVERAGE_STATUS_KEY}_incomplete",
                            "missing_objectives": ["safety"]}
    assert skipped["E"]["reason"] == f"{COVERAGE_STATUS_KEY}_missing"


def test_refit_excludes_partially_evaluated_compound(tmp_path):
    """D has potency only after A–C have potency + safety: its partial score
    must be listed as skipped, not used as a training label."""
    pytest.importorskip("rdkit")
    db = str(tmp_path / "c.db")
    _ingest(db, tmp_path, "p.csv", POTENCY)
    _ingest(db, tmp_path, "s.csv", SAFETY)
    _ingest(db, tmp_path, "d.csv", [("D", "CCCl", "IC50", "0.5", "nM", "2026-10-03", "=")])
    save_virtual_library(db, "camp", LIBRARY, n_propose=2)
    p = refit_and_propose(db, "camp", triggered_by="manual")
    report = p.training_report
    assert report["n_used"] == 3 and report["n_ranked"] == 4
    assert report["skipped"] == [{"compound_id": "D",
                                  "reason": f"{COVERAGE_STATUS_KEY}_incomplete",
                                  "missing_objectives": ["safety"]}]


def test_too_few_scored_compounds_is_an_explicit_error():
    with pytest.raises(CampaignDataError, match="usable"):
        build_training_rows([_row("A", "CCO", 0.4), _row("B", "CCN")])


def test_constant_labels_are_flagged():
    rows = build_training_rows([_row(c, s, 0.5) for c, s in (("A", "CCO"), ("B", "CCN"))])
    assert any(w.startswith("constant_labels") for w in rows.warnings)


def test_refit_raises_when_no_compound_is_scorable(tmp_path):
    db = str(tmp_path / "c.db")
    _ingest(db, tmp_path, "p.csv", [("A", "", "IC50", "1", "nM", "2026-10-01", "="),
                                    ("B", "", "IC50", "5", "nM", "2026-10-01", "=")])
    save_virtual_library(db, "camp", LIBRARY, n_propose=2)
    with pytest.raises(CampaignDataError):
        refit_and_propose(db, "camp", triggered_by="test")
    assert list_auto_proposals(db, "camp") == []


# --- public campaign path: labels + rounds ----------------------------------

def test_refit_learns_new_assay_batch_with_increasing_rounds(tmp_path):
    pytest.importorskip("rdkit")
    db = str(tmp_path / "c.db")
    _ingest(db, tmp_path, "p.csv", POTENCY)
    save_virtual_library(db, "camp", LIBRARY, n_propose=2)
    before = refit_and_propose(db, "camp", triggered_by="manual")
    _ingest(db, tmp_path, "s.csv", SAFETY)
    after = refit_and_propose(db, "camp", triggered_by="manual")

    assert before.training_report["n_used"] == 3 and not before.training_report["skipped"]
    b, a = before.scores[CAMPAIGN_OBJECTIVE], after.scores[CAMPAIGN_OBJECTIVE]
    assert any(v > 0 for v in b), "observed labels must not collapse to a constant"
    assert b != a, "a new assay batch must change surrogate predictions"
    assert (before.round_number, after.round_number) == (1, 2)

    with sqlite3.connect(db) as conn:
        bo = conn.execute("SELECT round_number FROM bo_proposals WHERE campaign_id='camp' "
                          "ORDER BY id").fetchall()
        auto = conn.execute("SELECT round_number, training_report_json FROM auto_proposals "
                            "WHERE campaign_id='camp' ORDER BY id").fetchall()
    assert [r[0] for r in bo] == [1, 2] == [r[0] for r in auto]
    reloaded = list_auto_proposals(db, "camp")
    assert reloaded[0].training_report["n_used"] == 3


def test_concurrent_optimizers_cannot_persist_the_same_round(tmp_path):
    """Two refits fitted at the same ledger state (background loop vs manual
    trigger) both compute round 1; allocation at commit keeps them distinct."""
    pytest.importorskip("rdkit")
    db = str(tmp_path / "c.db")
    rows = build_training_rows([_row("A", "CCO", 0.9), _row("B", "CCN", 0.2),
                                _row("C", "CCC", 0.5)])
    opt1 = fit_campaign_optimizer(db, "camp", rows, n_initial=2)
    opt2 = fit_campaign_optimizer(db, "camp", rows, n_initial=2)
    p1 = opt1.propose_next_round(LIBRARY, n_propose=2)
    p2 = opt2.propose_next_round(LIBRARY, n_propose=2)
    assert p1.round_number == p2.round_number == 1
    a1 = persist_round(db, opt1, p1, "auto_retrain")
    a2 = persist_round(db, opt2, p2, "manual")
    assert (a1.round_number, a2.round_number) == (1, 2)
    assert opt1.latest_round() == 2


def test_legacy_duplicate_rounds_do_not_cause_reuse(tmp_path):
    """auto_proposals rows written before the ledger fix (both round 1, no
    bo_proposals rows) must not be followed by another round 1."""
    pytest.importorskip("rdkit")
    db = str(tmp_path / "c.db")
    from galaxy.ai.drug_discovery.bayesian_optimizer import BayesianOptimizer
    BayesianOptimizer("camp", db)          # creates bo_proposals
    ar._init_tables(db)
    with sqlite3.connect(db) as conn:
        for ts in ("2026-01-01T00:00:00", "2026-01-02T00:00:00"):
            conn.execute("INSERT INTO auto_proposals (campaign_id, round_number, "
                         "proposed_smiles_json, scores_json, triggered_by, created_at) "
                         "VALUES ('camp', 1, '[]', '{}', 'manual', ?)", (ts,))
    _ingest(db, tmp_path, "p.csv", POTENCY)
    save_virtual_library(db, "camp", LIBRARY, n_propose=2)
    assert refit_and_propose(db, "camp", triggered_by="manual").round_number == 2


def test_format_proposal_reads_objective_keyed_scores():
    pytest.importorskip("fastapi")
    from galaxy.ai.drug_discovery.api_router import _format_proposal
    p = ar.AutoProposal(id=1, campaign_id="camp", round_number=3,
                        proposed_smiles=["CCCC", "CCCO"],
                        scores={CAMPAIGN_OBJECTIVE: [0.8, 0.3]},
                        confidence_intervals={CAMPAIGN_OBJECTIVE: [[0.6, 0.9], [0.1, 0.5]]},
                        ad_statuses=["in_domain", "out_of_domain"], triggered_by="manual",
                        created_at="t", training_report={"n_used": 3})
    shaped = _format_proposal(p)
    assert [i["score"] for i in shaped["items"]] == [0.8, 0.3]
    assert [(i["ci_lo"], i["ci_hi"]) for i in shaped["items"]] == [(0.6, 0.9), (0.1, 0.5)]
    assert shaped["round"] == 3 and shaped["training_report"] == {"n_used": 3}


# --- surrogate discrimination evidence is persisted with the round ----------

def test_refit_persists_discrimination_flag_and_stds(tmp_path):
    """Three compounds cannot rank the library: the persisted round must say
    so and keep per-compound posterior stds, also after reload."""
    pytest.importorskip("rdkit")
    db = str(tmp_path / "c.db")
    _ingest(db, tmp_path, "p.csv", POTENCY)
    _ingest(db, tmp_path, "s.csv", SAFETY)
    save_virtual_library(db, "camp", LIBRARY, n_propose=2)
    p = refit_and_propose(db, "camp", triggered_by="manual")
    assert p.can_discriminate is False
    assert p.surrogate_report["can_discriminate"] is False
    assert p.surrogate_report["n_train"] == 3
    stds = p.gp_stds[CAMPAIGN_OBJECTIVE]
    assert len(stds) == len(p.proposed_smiles) == 2 and all(s > 0 for s in stds)
    assert len(set(p.scores[CAMPAIGN_OBJECTIVE])) == 2, "scores must not collapse to one value"

    reloaded = list_auto_proposals(db, "camp")[0]
    assert reloaded.can_discriminate is False
    assert reloaded.gp_stds == p.gp_stds
    assert reloaded.surrogate_report == p.surrogate_report


def test_fewer_usable_candidates_than_requested_is_reported(tmp_path):
    pytest.importorskip("rdkit")
    db = str(tmp_path / "c.db")
    _ingest(db, tmp_path, "p.csv", POTENCY)
    # CCO is already measured and OCCC duplicates CCCO: one usable candidate.
    save_virtual_library(db, "camp", ["CCCO", "OCCC", "CCO"], n_propose=3)
    p = refit_and_propose(db, "camp", triggered_by="manual")
    rep = p.surrogate_report
    assert p.proposed_smiles == ["CCCO"]
    assert (rep["n_requested"], rep["n_proposed"]) == (3, 1)
    assert any(w.startswith("fewer_than_requested") for w in rep["warnings"])
    assert {e["reason"] for e in rep["excluded_candidates"]} == {"duplicate_structure",
                                                                 "already_measured"}


def test_legacy_auto_proposals_table_is_migrated(tmp_path):
    db = str(tmp_path / "legacy.db")
    with sqlite3.connect(db) as conn:
        conn.execute("""CREATE TABLE auto_proposals (
            id INTEGER PRIMARY KEY AUTOINCREMENT, campaign_id TEXT NOT NULL,
            round_number INTEGER NOT NULL, proposed_smiles_json TEXT NOT NULL,
            scores_json TEXT NOT NULL, ci_json TEXT NOT NULL DEFAULT '{}',
            ad_statuses_json TEXT NOT NULL DEFAULT '[]',
            triggered_by TEXT NOT NULL DEFAULT 'auto_retrain', created_at TEXT NOT NULL)""")
        conn.execute("INSERT INTO auto_proposals (campaign_id, round_number, proposed_smiles_json, "
                     "scores_json, created_at) VALUES ('camp', 1, '[\"CCCC\"]', '{}', 't')")
    old = list_auto_proposals(db, "camp")[0]
    assert (old.gp_stds, old.surrogate_report, old.can_discriminate) == ({}, {}, None)
    assert old.training_report == {}


def test_format_proposal_exposes_std_and_ranking_flag():
    pytest.importorskip("fastapi")
    from galaxy.ai.drug_discovery.api_router import _format_proposal
    rep = {"can_discriminate": False, "n_train": 3}
    p = ar.AutoProposal(id=1, campaign_id="camp", round_number=2,
                        proposed_smiles=["CCCN", "CCCl"],
                        scores={CAMPAIGN_OBJECTIVE: [0.498, 0.331]},
                        confidence_intervals={CAMPAIGN_OBJECTIVE: [[-0.29, 1.28], [-0.48, 1.15]]},
                        ad_statuses=["in_domain", "in_domain"], triggered_by="manual",
                        created_at="t", gp_stds={CAMPAIGN_OBJECTIVE: [0.40, 0.42]},
                        surrogate_report=rep, can_discriminate=False)
    shaped = _format_proposal(p)
    assert shaped["can_discriminate"] is False and shaped["surrogate_report"] == rep
    assert [i["std"] for i in shaped["items"]] == [0.40, 0.42]
    legacy = ar.AutoProposal(id=2, campaign_id="camp", round_number=1, proposed_smiles=["CCCC"],
                             scores={CAMPAIGN_OBJECTIVE: [0.5]}, confidence_intervals={},
                             ad_statuses=[], triggered_by="manual", created_at="t")
    shaped = _format_proposal(legacy)
    assert shaped["can_discriminate"] is None and shaped["items"][0]["std"] is None
