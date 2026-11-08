"""Surrogate behind campaign proposals: shared fingerprint features, a
Tanimoto kernel that cannot collapse to the prior mean, uncertainty-aware
acquisition, and an explicit flag when the data cannot rank candidates."""
import json
import sqlite3
import warnings

import pytest

np = pytest.importorskip("numpy")
pytest.importorskip("sklearn")
pytest.importorskip("rdkit")

from rdkit import Chem, DataStructs
from rdkit.Chem import rdFingerprintGenerator
from sklearn.exceptions import ConvergenceWarning

from galaxy.ai.drug_discovery.bayesian_optimizer import BayesianOptimizer, CampaignDataset
from galaxy.ai.drug_discovery.fingerprint_surrogate import (
    MorganFeaturizer, TanimotoGP, TanimotoKernel, assess_discrimination,
    expected_hypervolume_improvement, expected_improvement,
)

# SYSUCC Case 3 fixture: composite scores of A/B/C after the potency batch
# and after the safety batch (docs/qa/sysucc-usecases).
FIXTURE_TRAIN = ["CCO", "CCN", "CCC"]
FIXTURE_LABELS = {"initial": [1.0, 0.9090909090909091, 0.0],
                  "safety": [0.2, 0.9545454545454546, 0.24489795918367346]}
FIXTURE_LIBRARY = ["CCCC", "CCCO", "CCCN", "CCCl"]

ACIDS = ["CC(=O)O", "CCC(=O)O", "CCCC(=O)O", "CCCCC(=O)O", "OC(=O)c1ccccc1",
         "OC(=O)c1ccc(C)cc1", "OC(=O)c1ccc(Cl)cc1", "OC(=O)CCc1ccccc1",
         "OC(=O)C1CCCCC1", "OC(=O)c1ccncc1"]
NON_ACIDS = ["CCCC", "CCCCC", "CCCCCC", "c1ccccc1", "Cc1ccccc1", "Clc1ccccc1",
             "CCc1ccccc1", "C1CCCCC1", "c1ccncc1", "CC(C)C"]


def _fit(tmp_path, smiles, objectives, directions=None, campaign="c", n_initial=2):
    opt = BayesianOptimizer(campaign, str(tmp_path / "bo.db"), n_initial=n_initial)
    opt.fit(CampaignDataset(
        compound_ids=[f"X{i}" for i in range(len(smiles))], smiles_list=smiles,
        features=opt.featurise(smiles),
        objectives={k: np.asarray(v, dtype=float) for k, v in objectives.items()},
        objective_directions=directions or {k: "maximize" for k in objectives},
    ))
    return opt


# --- kernel / featuriser ------------------------------------------------------

def test_tanimoto_kernel_matches_rdkit_and_is_psd():
    smiles = FIXTURE_TRAIN + FIXTURE_LIBRARY + ACIDS[:4]
    X, invalid = MorganFeaturizer().featurise(smiles)
    assert invalid == []
    K = TanimotoKernel()(X)
    gen = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048)
    fps = [gen.GetFingerprint(Chem.MolFromSmiles(s)) for s in smiles]
    ref = np.array([DataStructs.BulkTanimotoSimilarity(f, fps) for f in fps])
    assert np.allclose(K, ref)
    assert np.linalg.eigvalsh(K).min() > -1e-10


def test_featuriser_reports_unparsable_smiles():
    X, invalid = MorganFeaturizer().featurise(["CCO", "not-a-smiles", ""])
    assert invalid == [1, 2] and X[0].sum() > 0 and not X[1:].any()


# --- the reported defect: identical scores on the campaign fixture -----------

@pytest.mark.parametrize("stage", ["initial", "safety"])
def test_fixture_predictions_differ_without_length_scale_collapse(tmp_path, stage):
    with warnings.catch_warnings():
        warnings.simplefilter("error", ConvergenceWarning)
        opt = _fit(tmp_path, FIXTURE_TRAIN, {"composite_score": FIXTURE_LABELS[stage]})
    gp = opt._gp_models["composite_score"]
    mu, sd = gp.predict(opt.featurise(FIXTURE_LIBRARY), return_std=True)
    prior_mean = float(np.mean(FIXTURE_LABELS[stage]))
    assert np.ptp(mu) > 0.01, f"predictions collapsed to one value: {mu}"
    assert not np.allclose(mu, prior_mean, atol=1e-3)
    assert np.all(sd > 0)


def test_fixture_follows_nearest_measured_analogue(tmp_path):
    """After the safety batch B (CCN) is best: its analogue CCCN must outrank
    CCCO, the analogue of the now-poor A (CCO)."""
    opt = _fit(tmp_path, FIXTURE_TRAIN, {"composite_score": FIXTURE_LABELS["safety"]})
    mu = dict(zip(FIXTURE_LIBRARY, opt._gp_models["composite_score"].predict(
        opt.featurise(FIXTURE_LIBRARY))))
    assert mu["CCCN"] > mu["CCCO"]


def test_three_compounds_are_flagged_as_unable_to_discriminate(tmp_path):
    opt = _fit(tmp_path, FIXTURE_TRAIN, {"composite_score": FIXTURE_LABELS["safety"]})
    p = opt.propose_next_round(FIXTURE_LIBRARY, n_propose=2)
    rep = p.surrogate_report
    assert p.can_discriminate is False and rep["can_discriminate"] is False
    disc = rep["objectives"]["composite_score"]["discrimination"]
    assert disc["max_pairwise_order_probability"] < disc["threshold"]
    assert any(w.startswith("small_training_set") for w in rep["warnings"])
    assert any("cannot_discriminate" in w for w in rep["warnings"])
    assert len(p.gp_stds["composite_score"]) == 2 and all(s > 0 for s in p.gp_stds["composite_score"])
    for (lo, hi), mu in zip(p.confidence_intervals["composite_score"], p.scores["composite_score"]):
        assert lo < mu < hi


def test_structure_activity_signal_is_discriminated(tmp_path):
    labels = [1.0] * len(ACIDS) + [0.0] * len(NON_ACIDS)
    opt = _fit(tmp_path, ACIDS + NON_ACIDS, {"act": labels}, n_initial=5)
    lib = ["OC(=O)CCCCCC", "OC(=O)c1ccc(F)cc1", "CCCCCCC", "Fc1ccccc1"]
    p = opt.propose_next_round(lib, n_propose=4, diversity_weight=0.0)
    s = dict(zip(p.proposed_compounds, p.scores["act"]))
    assert p.can_discriminate is True
    assert min(s["OC(=O)CCCCCC"], s["OC(=O)c1ccc(F)cc1"]) > max(s["CCCCCCC"], s["Fc1ccccc1"])
    assert set(p.proposed_compounds[:2]) == {"OC(=O)CCCCCC", "OC(=O)c1ccc(F)cc1"}


def test_constant_labels_cannot_discriminate(tmp_path):
    opt = _fit(tmp_path, FIXTURE_TRAIN, {"s": [0.5, 0.5, 0.5]})
    p = opt.propose_next_round(FIXTURE_LIBRARY, n_propose=2)
    assert p.can_discriminate is False
    assert p.surrogate_report["objectives"]["s"]["discrimination"]["reason"].startswith(
        "all training labels are identical")


# --- no fabricated differences ----------------------------------------------

def test_fingerprint_identical_candidates_get_identical_scores(tmp_path):
    """Enantiomers share a (non-chiral) fingerprint: the surrogate has no
    information to separate them and must not report a difference."""
    opt = _fit(tmp_path, ACIDS[:6], {"a": [0.1, 0.4, 0.9, 0.3, 0.7, 0.2]})
    lib = ["C[C@H](N)C(=O)O", "C[C@@H](N)C(=O)O"]
    p = opt.propose_next_round(lib, n_propose=2, diversity_weight=0.0)
    (s1, s2), (u1, u2) = p.scores["a"], p.gp_stds["a"]
    a1, a2 = p.acquisition_values
    assert s1 == s2 and u1 == u2 and a1 == a2
    X = opt.featurise(lib)
    assert assess_discrimination(opt._gp_models["a"], X)["max_pairwise_order_probability"] == 0.5


def test_ehvi_uses_common_random_numbers():
    rng = np.random.RandomState(0)
    mu = np.array([[0.5, 0.5], [0.5, 0.5], [0.9, 0.9]])
    sd = np.array([[0.2, 0.2], [0.2, 0.2], [0.2, 0.2]])
    ehvi = expected_hypervolume_improvement(mu, sd, np.array([[1.0, 0.0], [0.0, 1.0]]),
                                            np.zeros(2), rng)
    assert ehvi[0] == ehvi[1] and ehvi[2] > ehvi[0] > 0


def test_expected_improvement_rewards_uncertainty_at_equal_mean():
    ei = expected_improvement(np.array([0.5, 0.5]), np.array([0.05, 0.4]), best=1.0)
    assert ei[1] > ei[0] > 0


# --- shared feature space -----------------------------------------------------

def test_fit_rejects_features_from_another_featuriser(tmp_path):
    opt = BayesianOptimizer("c", str(tmp_path / "bo.db"), n_initial=2)
    ds = CampaignDataset(["A", "B", "C"], FIXTURE_TRAIN, np.random.rand(3, 256),
                         {"y": np.array([0.1, 0.5, 0.9])}, {"y": "maximize"})
    with pytest.raises(ValueError, match="share one feature space"):
        opt.fit(ds)


def test_fit_rejects_unparsable_training_smiles(tmp_path):
    opt = BayesianOptimizer("c", str(tmp_path / "bo.db"), n_initial=2)
    smiles = ["CCO", "xx", "CCC"]
    ds = CampaignDataset(["A", "B", "C"], smiles, opt.featurise(smiles),
                         {"y": np.array([0.1, 0.5, 0.9])}, {"y": "maximize"})
    with pytest.raises(ValueError, match="cannot featurise"):
        opt.fit(ds)


def test_predict_rejects_wrong_dimension():
    X, _ = MorganFeaturizer().featurise(FIXTURE_TRAIN)
    gp = TanimotoGP(random_state=0).fit(X, np.array([0.0, 0.5, 1.0]))
    with pytest.raises(ValueError, match="dimension mismatch"):
        gp.predict(np.random.rand(2, 256))


# --- candidate pool -----------------------------------------------------------

def test_candidate_screening_reports_exclusions(tmp_path):
    opt = _fit(tmp_path, FIXTURE_TRAIN, {"y": FIXTURE_LABELS["initial"]})
    lib = ["CCCO", "OCCC", "OCC", "bad(", "CCCN"]
    p = opt.propose_next_round(lib, n_propose=5)
    assert sorted(p.proposed_compounds) == ["CCCN", "CCCO"]
    reasons = {e["smiles"]: e["reason"] for e in p.surrogate_report["excluded_candidates"]}
    assert reasons == {"OCCC": "duplicate_structure", "OCC": "already_measured",
                       "bad(": "invalid_smiles"}


def test_batch_prefers_diverse_structures(tmp_path):
    labels = [1.0] * len(ACIDS) + [0.0] * len(NON_ACIDS)
    opt = _fit(tmp_path, ACIDS + NON_ACIDS, {"act": labels}, n_initial=5)
    lib = ["OC(=O)CCCCCC", "OC(=O)CCCCCCC", "OC(=O)c1ccc(F)cc1"]
    greedy = opt.propose_next_round(lib, n_propose=2, diversity_weight=0.0)
    diverse = opt.propose_next_round(lib, n_propose=2, diversity_weight=0.8)
    assert diverse.diversity_score >= greedy.diversity_score
    assert "OC(=O)c1ccc(F)cc1" in diverse.proposed_compounds


# --- persistence / reproducibility -------------------------------------------

def test_surrogate_report_round_trips(tmp_path):
    opt = _fit(tmp_path, FIXTURE_TRAIN, {"composite_score": FIXTURE_LABELS["initial"]})
    p = opt.propose_next_round(FIXTURE_LIBRARY, n_propose=2)
    opt.save_proposal(p)
    loaded = opt.load_proposals("c")[-1]
    assert loaded.can_discriminate is p.can_discriminate is False
    assert loaded.surrogate_report == json.loads(json.dumps(p.surrogate_report))


def test_legacy_bo_proposals_table_is_migrated(tmp_path):
    db = str(tmp_path / "legacy.db")
    with sqlite3.connect(db) as conn:
        conn.execute("""CREATE TABLE bo_proposals (
            id INTEGER PRIMARY KEY AUTOINCREMENT, campaign_id TEXT NOT NULL,
            round_number INTEGER NOT NULL, proposed_smiles TEXT NOT NULL,
            scores_json TEXT NOT NULL, acquisition_values_json TEXT NOT NULL,
            pareto_front_smiles_json TEXT NOT NULL, diversity_score REAL NOT NULL,
            timestamp TEXT NOT NULL)""")
        conn.execute("INSERT INTO bo_proposals (campaign_id, round_number, proposed_smiles, "
                     "scores_json, acquisition_values_json, pareto_front_smiles_json, "
                     "diversity_score, timestamp) VALUES ('c', 1, '[]', '{}', '[]', '[]', 0, 't')")
    opt = BayesianOptimizer("c", db)
    old = opt.load_proposals("c")
    assert len(old) == 1 and old[0].surrogate_report == {} and old[0].can_discriminate is None


def test_proposals_are_reproducible(tmp_path):
    a = _fit(tmp_path, FIXTURE_TRAIN, {"y": FIXTURE_LABELS["safety"]}, campaign="same")
    b = _fit(tmp_path, FIXTURE_TRAIN, {"y": FIXTURE_LABELS["safety"]}, campaign="same")
    pa, pb = a.propose_next_round(FIXTURE_LIBRARY, 2), b.propose_next_round(FIXTURE_LIBRARY, 2)
    assert a._seed == b._seed
    assert pa.proposed_compounds == pb.proposed_compounds and pa.scores == pb.scores
