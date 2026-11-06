import os, itertools
import numpy as np, pandas as pd, pytest
import common, models as M
import build_table as B

RAW_OK = os.path.exists(f"{common.RAW}/PCA2/med_score_filtered.csv")


def synth(seed=0, doms=("363", "366", "385"), n=300):
    """Synthetic domain x peptide table with a planted peptide-intrinsic effect (hydrophobic good) + noise."""
    rng = np.random.default_rng(seed); rows = []
    bb = "SGRFWFSDWL"
    peps = []
    while len(peps) < n:
        s = list(bb); s[3] = rng.choice(list(common.AAS)); s[6] = rng.choice(list(common.AAS)); s = "".join(s)
        if s not in peps: peps.append(s)
    for d in doms:
        for p in peps:
            sc = 0.5 * sum(common.KD[a] for a in p) / len(p) + rng.normal(0, 0.1)
            rows.append(dict(dataset="PCA2", domain=d, family="363", aa_seq=p, backbone=bb, score=sc,
                             pwm=sc + rng.normal(0, 0.3), cognate=d == "363"))
    return pd.DataFrame(rows)


# ---------------- table builder
def test_wt_reconstruction():
    r = pd.Series(dict(aa_seq="SGRAWFWDWL", pos1=4, pos2=7, max1="F", max2="S", pos=np.nan, max=np.nan))
    assert B.wt_of(r) == "SGRFWFSDWL"
    r = pd.Series(dict(aa_seq="AGRFWFSDWL", pos1=np.nan, pos2=np.nan, max1=np.nan, max2=np.nan, max="S", pos=1))
    assert B.wt_of(r) == "SGRFWFSDWL"


@pytest.mark.skipif(not RAW_OK, reason="raw Landry data not downloaded")
def test_table_counts_and_unique_keys():
    t, bb = B.build_all()
    assert not t.duplicated(["dataset", "domain", "aa_seq"]).any()
    p2 = t[t.dataset == "PCA2"]
    assert sorted(p2.domain.unique()) == ["363", "366", "385"]          # exactly 3 PCA2 PPI domains
    assert t.domain.nunique() == 7                                       # union of PCA1+PCA2
    assert t.score.notna().all() and not t.aa_seq.str.contains(r"\*").any()
    assert p2.groupby("domain").size().min() > 1500
    assert (p2.groupby("aa_seq").domain.nunique() == 3).sum() > 1500     # shared peptides -> promiscuity null defined
    assert set(p2.family) == {"363", "366", "385"}
    assert (t.n_mut.dropna() <= 2).all()


# ---------------- splitter
def test_splitter_no_domain_leakage_all_options():
    t = synth(doms=("152", "246", "363", "366", "385"))
    ident = {a: {b: 0.2 for b in common.DOMAINS} for a in common.DOMAINS}
    ident["363"]["366"] = 0.5
    for d in t.domain.unique():
        tr, te = M.lodo_split(t, d)
        assert d not in set(tr.domain) and set(te.domain) == {d}
        assert len(tr) + len(te) == len(t)
        tr, te = M.lodo_split(t, d, max_identity=0.3, ident=ident)
        assert d not in set(tr.domain)
        if d == "363": assert "366" not in set(tr.domain)
        tr, te = M.lodo_split(t, d, only_class="PDZ")
        assert d not in set(tr.domain) and set(common.DOMAINS[x]["cls"] for x in tr.domain) <= {"PDZ"}


# ---------------- null models behave under shuffled labels; planted signal is recovered
def test_permutation_nulls_near_zero_and_signal_recovered():
    t = synth()
    sim = {a: {b: 1.0 if a == b else 0.3 for b in common.DOMAINS} for a in common.DOMAINS}
    desc = M.domain_descriptors(); rng = np.random.default_rng(1)
    tr, te = M.lodo_split(t, "385")
    preds = {"prom": M.null_promiscuity(tr, te), "add": M.null_additive_position(tr, te),
             "phys": M.null_physchem(tr, te), "pwm": M.pwm_scores(te),
             "i": M.model_additive_offsets(tr, te), "ii": M.model_lowrank(tr, te, sim), "iii": M.model_gbm(tr, te, desc)}
    for k, p in preds.items():                                           # planted signal: all should be clearly positive
        assert common.spearman(p, te.score.values) > 0.3, k
    for k, p in preds.items():                                           # shuffled test labels: rho ~ 0
        rs = [common.spearman(p, rng.permutation(te.score.values)) for _ in range(100)]
        assert abs(np.mean(rs)) < 0.03, (k, np.mean(rs))
        assert np.std(rs) < 0.12


def test_labels_shuffled_in_train_gives_no_test_signal():
    """Training labels permuted (peptide<->score decoupled): trained models must lose their skill on real test labels."""
    t = synth(); rng = np.random.default_rng(2)
    tr, te = M.lodo_split(t, "385"); tr = tr.copy(); tr["score"] = rng.permutation(tr.score.values)
    r = common.spearman(M.null_physchem(tr, te), te.score.values)
    assert abs(r) < 0.2
