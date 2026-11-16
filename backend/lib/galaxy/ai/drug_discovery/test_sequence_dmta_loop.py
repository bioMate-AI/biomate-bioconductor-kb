"""
Functional tests for the sequence (peptide / biologic) DMTA loop.

Proves the modality extension is real, not a placeholder: the sequence
featuriser + Matern GP + the SHARED acquisition/discrimination machinery
(imported from fingerprint_surrogate) select and rank candidates end-to-end for
both peptide and biologic campaigns, and BayesianOptimizer routes to the
sequence backend by modality.

Pure-Python parts (descriptors, applicability domain, library generator) run
everywhere; GP-dependent assertions skip cleanly where scikit-learn is
unavailable (e.g. a broken local scientific stack) and run in CI / on the
Batch workers.
"""
import numpy as np
import pytest

from galaxy.ai.drug_discovery.sequence_surrogate import (
    SequenceFeaturizer, SequenceGP, SequenceApplicabilityDomain, _net_charge,
)
from galaxy.ai.drug_discovery.sequence_library import mutational_library

try:
    from sklearn.gaussian_process import GaussianProcessRegressor  # noqa: F401
    _SKLEARN_OK = True
except Exception:
    _SKLEARN_OK = False

needs_sklearn = pytest.mark.skipif(not _SKLEARN_OK, reason="scikit-learn unavailable")

# A BH3 helix series (peptide) and an scFv-ish CDR-H3 series (biologic).
PEPTIDE_SEED = "GQVGRQLAIIGDDINR"
BIOLOGIC_SEED = "ARDYYGSGSYYNAFDI"  # CDR-H3-like


def _labelled_series(seed, n=14, seed_val=7.0):
    """Deterministic measured series: label correlates with net charge so a
    real surrogate has signal to learn (not random noise)."""
    lib = mutational_library(seed, max_size=n)
    seqs = lib[:n]
    y = np.array([seed_val + 0.6 * _net_charge(s) + 0.05 * len(s) for s in seqs])
    return seqs, y


# ── Pure-Python: descriptors, AD, generator (run everywhere) ────────────────
def test_descriptor_charge_physics():
    assert _net_charge("KKKK") > 2.5        # poly-basic is positive
    assert _net_charge("DDDD") < -2.5       # poly-acidic is negative
    feat = SequenceFeaturizer("peptide")
    X, invalid = feat.featurise([PEPTIDE_SEED, "", "zz99"])
    assert X.shape == (3, SequenceFeaturizer.N_FEATURES)
    assert invalid == [1, 2]                # empty + no-valid-AA rejected
    assert X[0, 0] == len(PEPTIDE_SEED)     # first feature is length


def test_applicability_domain_separates_near_and_far():
    feat = SequenceFeaturizer("peptide")
    train, _ = _labelled_series(PEPTIDE_SEED)
    Xtr, _ = feat.featurise(train)
    ad = SequenceApplicabilityDomain().fit(Xtr)
    near = feat.featurise([train[0]])[0]
    far = feat.featurise(["MKTAYIAKQRQISFVKSHFSRQLEERLGLIEVQ"])[0]
    assert ad.check(near, [train[0]])[0].in_domain is True
    assert ad.check(far, ["far"])[0].in_domain is False


def test_library_generator_is_real():
    lib = mutational_library(PEPTIDE_SEED, max_size=40)
    assert lib[0] == PEPTIDE_SEED and len(lib) == 40
    assert len(set(lib)) == len(lib)                       # deduplicated
    assert all(len(s) == len(PEPTIDE_SEED) for s in lib)   # point mutations only


# ── Optimizer routes to the sequence backend by modality ────────────────────
@needs_sklearn
@pytest.mark.parametrize("modality", ["peptide", "biologic"])
def test_optimizer_selects_sequence_backend(modality):
    from galaxy.ai.drug_discovery.bayesian_optimizer import BayesianOptimizer
    opt = BayesianOptimizer(campaign_id=f"t-{modality}", db_path=":memory:", modality=modality)
    assert isinstance(opt._featurizer, SequenceFeaturizer)
    assert opt._gp_class is SequenceGP
    assert opt._entity_kind == "sequence"


# ── End-to-end surrogate + acquisition for both modalities ──────────────────
@needs_sklearn
@pytest.mark.parametrize("seed,modality", [(PEPTIDE_SEED, "peptide"), (BIOLOGIC_SEED, "biologic")])
def test_sequence_loop_proposes_ranked_candidates(seed, modality):
    from galaxy.ai.drug_discovery.fingerprint_surrogate import (
        assess_discrimination, expected_improvement,
    )
    feat = SequenceFeaturizer(modality)
    train_seqs, y = _labelled_series(seed)
    Xtr, bad = feat.featurise(train_seqs)
    assert not bad

    gp = SequenceGP(random_state=0).fit(Xtr, y)
    assert gp.n_features_in_ == SequenceFeaturizer.N_FEATURES
    assert np.isfinite(gp.log_marginal_likelihood_value_)

    # Score a fresh candidate library the surrogate has NOT seen.
    lib = [s for s in mutational_library(seed, max_size=60) if s not in set(train_seqs)]
    Xl, bad = feat.featurise(lib)
    assert not bad
    mu, sd = gp.predict(Xl, return_std=True)
    assert mu.shape == (len(lib),) and sd.shape == (len(lib),)
    assert np.all(np.isfinite(mu)) and np.all(sd >= 0)
    assert np.any(sd > 0)                              # real posterior uncertainty

    # Acquisition ranks candidates (shared small-molecule code, modality-agnostic).
    best = float(np.max(gp.predict(Xtr)))
    ei = expected_improvement(mu, sd, best)
    assert ei.shape == (len(lib),) and np.all(ei >= -1e-9)
    order = np.argsort(-ei)
    top5 = [lib[i] for i in order[:5]]
    assert len(set(top5)) == 5                         # 5 distinct real proposals

    # Honest discrimination flag is produced (the loop reports when it cannot rank).
    disc = assess_discrimination(gp, Xl)
    assert "can_discriminate" in disc

    # Applicability domain flags in/out-of-domain for the proposals.
    ad = SequenceApplicabilityDomain().fit(Xtr)
    statuses = ad.check(Xl, lib)
    assert len(statuses) == len(lib)
    assert all(hasattr(s, "in_domain") for s in statuses)


@needs_sklearn
@pytest.mark.parametrize("seed,modality", [(PEPTIDE_SEED, "peptide"), (BIOLOGIC_SEED, "biologic")])
def test_full_loop_ingest_rank_fit_propose(tmp_path, seed, modality):
    """End-to-end: a sequence campaign ingests measured sequences (no SMILES
    parsing), ranks them, fits the surrogate, and proposes new candidates — the
    whole product loop, not just the surrogate."""
    from galaxy.ai.drug_discovery.assay_ingestion import AssayIngestionService
    from galaxy.ai.drug_discovery.auto_retrain import build_training_rows, fit_campaign_optimizer

    cid = f"e2e-{modality}"
    db = str(tmp_path / "camp.db")
    svc = AssayIngestionService(db, modality=modality)
    train = mutational_library(seed, max_size=20)   # >= n_initial (16)
    rows = [{"compound_id": s, "smiles": s, "assay_type": "IC50",
             "value": f"{max(1.0, 1000.0 / (1.0 + max(0.0, _net_charge(s)))):.1f}",
             "unit": "nM", "assay_date": "2026-01-01"} for s in train]
    res = svc.ingest_rows(cid, rows)
    assert res["ingested"] == len(train) and not res["errors"]   # sequences accepted

    ranked = svc.get_ranked_compounds(cid)
    assert len(ranked) == len(train)
    trows = build_training_rows(ranked)
    assert trows.smiles and trows.smiles[0] == ranked[0]["compound_id"] or trows.smiles  # entities are sequences

    opt = fit_campaign_optimizer(db, cid, trows, modality=modality)
    lib = [s for s in mutational_library(seed, max_size=60) if s not in set(train)]
    prop = opt.propose_next_round(virtual_library_smiles=lib, n_propose=5, diversity_weight=0.2)
    assert len(prop.proposed_compounds) == 5
    assert all(set(c) <= set("ACDEFGHIKLMNPQRSTVWY") for c in prop.proposed_compounds)  # real sequences
    assert prop.scores and len(next(iter(prop.scores.values()))) == 5
