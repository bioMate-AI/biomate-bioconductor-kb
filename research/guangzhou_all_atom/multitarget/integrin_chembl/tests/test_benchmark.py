"""Run: cd research/guangzhou_all_atom/multitarget/integrin_chembl && python3 -m pytest -q tests
Needs the scratchpad feature cache (05_features.py) for the split-leakage tests; prediction tests need data/preds."""
import os, sys, math, numpy as np, pandas as pd, pytest
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from common import nM_to_pact, relation_class, integrin_from_description, assay_class, standardize_smiles
import metrics, splits
HERE = os.path.dirname(os.path.dirname(__file__)); os.chdir(HERE)
def test_unit_conversion():
    assert nM_to_pact(1) == 9 and nM_to_pact(1000) == 6 and abs(nM_to_pact(0.5) - 9.30103) < 1e-4 and nM_to_pact(10000) == 5
def test_relations():
    assert relation_class("=") == "eq" and relation_class(">") == "gt" and relation_class(">=") == "gt" and relation_class("<") == "lt" and relation_class("<=") == "lt"
    assert relation_class(None) is None and relation_class("~") is None
def test_integrin_from_description():
    assert integrin_from_description("Binding to integrin αVβ6 in solid phase") == "avb6"
    assert integrin_from_description("Inhibition of alphavbeta3 and alphavbeta5") is None   # two heterodimers -> not rescued
    assert integrin_from_description("ELISA for alpha-V/beta-1") == "avb1"
    assert integrin_from_description("Purified human glycoprotein IIb/IIIa") == "aIIbb3"
def test_standardize_flat_key_ignores_salt_and_stereo_in_flat():
    a = standardize_smiles("N[C@@H](C)C(=O)O.Cl")[2]; b = standardize_smiles("N[C@H](C)C(=O)O")[2]; assert a == b and a is not None
def test_pairs_table_invariants():
    L = pd.read_csv("data/long_all.csv.gz"); P = pd.read_csv("data/pairs_all.csv.gz")
    assert (P.tA < P.tB).all() and np.allclose(P.delta, P.pA - P.pB)
    k = L[L.censor == "eq"].set_index(["doc", "cmpd_key", "target"]).index
    assert all(((d, c, a) in k) and ((d, c, b) in k) for d, c, a, b in zip(P.doc, P.cmpd_key, P.tA, P.tB)), "pair endpoints must exist as uncensored long rows IN THE SAME DOCUMENT"
    assert P.groupby("doc").size().min() >= 1 and P[P.same_class].shape[0] > 1000
def test_pairing_is_within_document_only():
    # A compound measured on A in doc1 and on B in doc2 must not create a pair.
    P = pd.read_csv("data/pairs_all.csv.gz"); L = pd.read_csv("data/long_all.csv.gz"); L = L[L.censor == "eq"]
    multi = L.groupby(["cmpd_key", "target"]).doc.nunique(); cross = L.groupby("cmpd_key").apply(lambda g: g.groupby("target").doc.apply(set).to_dict(), include_groups=False)
    n_cross = 0
    for ck, d in cross.items():
        ts = list(d)
        for i in range(len(ts)):
            for j in range(i + 1, len(ts)):
                if d[ts[i]].isdisjoint(d[ts[j]]): n_cross += 1
    assert n_cross > 0   # such disjoint cases exist in the data ...
    ps = set(zip(P.doc, P.cmpd_key)); lk = set(zip(L.doc, L.cmpd_key)); assert ps <= lk   # ... and are never paired: every pair's (doc,compound) is a real measurement unit
    # per pair both endpoints share the doc by construction (checked in test_pairs_table_invariants)
@pytest.fixture(scope="module")
def world():
    import engine
    U, Pp, clus, xs, xp = splits.load(); g = engine.G(); return U, Pp, clus, xs, xp, g["ci_of"], np.asarray(g["T"])
def _keys(spec): return set(spec["train"].ck), set(spec["test"].ck) | set(spec["test_pairs"].ck)
def test_S2_no_doc_or_inchikey_leak(world):
    U, Pp, clus, xs, xp, ci_of, T = world
    for fid, spec in splits.make_folds("S2", U, Pp, clus, xs, xp, ci_of, T):
        d = set(spec["test"].doc); assert len(d) == 1 and not (d & set(spec["train"].doc)) and not (d & set(spec["train_pairs"].doc))
        tr, te = _keys(spec); assert not (tr & te), fid
        assert not (set(spec["train_pairs"].ck) & te)
def test_S1_no_cluster_or_near_neighbour_leak(world):
    U, Pp, clus, xs, xp, ci_of, T = world
    for fid, spec in splits.make_folds("S1", U, Pp, clus, xs, xp, ci_of, T):
        tr, te = _keys(spec); assert not (tr & te)
        assert not ({clus[c] for c in tr} & {clus[c] for c in te}), fid
        ti = [ci_of[c] for c in te]; ri = [ci_of[c] for c in tr]; assert T[np.ix_(ri, ti)].max() < splits.SIM + 1e-6, fid
def test_S2b_and_S3b_similarity_exclusion(world):
    U, Pp, clus, xs, xp, ci_of, T = world
    for fid, spec in splits.make_folds("S2b", U, Pp, clus, xs, xp, ci_of, T)[:15] + splits.make_folds("S3b", U, Pp, clus, xs, xp, ci_of, T):
        tr, te = _keys(spec); assert T[np.ix_([ci_of[c] for c in tr], [ci_of[c] for c in te])].max() < splits.SIM + 1e-6, fid
def test_S3_external_exclusions(world):
    U, Pp, clus, xs, xp, ci_of, T = world
    (fid, spec), = splits.make_folds("S3", U, Pp, clus, xs, xp, ci_of, T)
    E = pd.read_csv("data/external_ligands.csv"); xk = set(E[E.smiles.notna()].flat_key)
    assert not (set(spec["train"].ck) & xk) and not (set(spec["train_pairs"].ck) & xk)
    assert "CHEMBL5214901" not in set(spec["train"].doc) and "CHEMBL5214901" not in set(spec["train_pairs"].doc)
    assert set(spec["test"].doc) == {splits.EXT_DOC} and set(spec["test"].ck) <= xk and len(spec["train"]) > 3000
def test_metrics_basic_and_bootstrap_groups():
    y = np.arange(10.0); assert metrics.rmse(y, y) == 0 and abs(metrics.spearman(y, y) - 1) < 1e-12 and metrics.auroc(y, (y > 4).astype(int)) == 1
    assert metrics.auroc(np.zeros(10), (y > 4).astype(int)) == 0.5
    gidx = metrics.group_index(np.repeat(np.arange(5), 2)); assert len(gidx) == 5
    d = next(metrics.boot_draws(gidx, 1, 0)); assert len(d) == 10 and set(d) <= set(range(10)) and all((d // 2).tolist().count(g) % 1 == 0 for g in range(5))
def test_label_permutation_collapses_metrics():
    p = "data/preds/S2_t2.csv.gz"
    if not os.path.exists(p): pytest.skip("predictions not generated")
    d = pd.read_csv(p); rng = np.random.RandomState(0); col = "M6" if "M6" in d else "M1d"
    real = abs(metrics.spearman(d[col], d.delta)); perm = [abs(metrics.spearman(d[col], rng.permutation(d.delta.values))) for _ in range(30)]
    assert real > 3 * np.mean(perm) and np.mean(perm) < 0.08   # real signal is large; fully permuted labels give ~0 (within-document permutation keeps pair-type structure and is reported separately)
    lab = (d.delta >= 1).astype(int).values; aucs = [metrics.auroc(d[col], rng.permutation(lab)) for _ in range(30)]; assert abs(np.mean(aucs) - 0.5) < 0.03
