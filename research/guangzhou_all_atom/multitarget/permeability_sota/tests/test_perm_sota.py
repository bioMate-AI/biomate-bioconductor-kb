import os, sys, numpy as np, pytest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from common import *
import cv

@pytest.fixture(scope="module")
def data():
    c, f = cv.load(); return c, f, cv.splits(("S0", "S1", "S2", "S3"))

def test_no_shared_group_between_train_and_test(data):
    c, f, sp = data
    for s in sp:
        tr = np.concatenate([s["tr"], s["va"]]); te = s["te"]
        assert len(set(tr) & set(te)) == 0, s["split"]
        if s["split"] == "S1": assert not (set(c.scaf.values[tr]) & set(c.scaf.values[te]))
        if s["split"] == "S2": assert not (set(f.s2_cluster.values[tr]) & set(f.s2_cluster.values[te]))
        if s["split"] == "S3":
            assert not (set(c.source.values[tr]) & set(c.source.values[te]))  # only if source fully held out
            assert not (set(c.pid.values[tr]) & set(c.pid.values[te]))

def test_s3_source_held_out(data):
    c, f, sp = data
    for s in [x for x in sp if x["split"] == "S3"]:
        assert c.source.values[s["te"]].tolist().count(c.source.values[s["te"]][0]) == len(s["te"])

def test_inner_validation_group_disjoint(data):
    c, f, sp = data
    for s in sp:
        if s["split"] == "S1": assert not (set(c.scaf.values[s["tr"]]) & set(c.scaf.values[s["va"]]))
        if s["split"] == "S2": assert not (set(f.s2_cluster.values[s["tr"]]) & set(f.s2_cluster.values[s["va"]]))

def test_every_row_tested_once_in_grouped_splits(data):
    c, f, sp = data
    for name in ("S1", "S2"):
        te = np.concatenate([s["te"] for s in sp if s["split"] == name]); assert sorted(te) == list(range(len(c)))

def test_helm_parse():
    assert parse_helm_monomers("PEPTIDE1{[Abu].[Sar].V.[meL]}$PEPTIDE1,PEPTIDE1,1:R1-4:R2$$$") == ["Abu", "Sar", "V", "meL"]
    with pytest.raises(ValueError): parse_helm_monomers("garbage")
    assert is_nmethyl_monomer("meL") and is_nmethyl_monomer("Me_dL") and is_nmethyl_monomer("Sar") and not is_nmethyl_monomer("L")

def test_smiles_all_valid_and_clean_has_no_censored(data):
    from rdkit import Chem
    c, _, _ = data
    assert all(Chem.MolFromSmiles(s) is not None for s in c.can)
    assert (c.y > -10).all()

def test_metrics_and_bootstrap():
    y = np.random.default_rng(0).normal(size=200); assert abs(r2(y, y) - 1) < 1e-12
    g = np.arange(200) // 4; ci = cluster_bootstrap(y, {"a": y + 0.1}, g, n_boot=50)["a"]["r2"]; assert ci[1] <= ci[0] <= ci[2] + 1e-9
    d = paired_diff(y, y, y + 1, g, n_boot=50); assert d[0] > 0 and d[1] > 0

def test_label_permutation_gives_r2_near_zero(data):
    from sklearn.ensemble import RandomForestRegressor
    import features
    c, f, sp = data; Z = features.get(); s = [x for x in sp if x["split"] == "S1"][0]
    y = c.y.values.copy(); rng = np.random.default_rng(0); yp = y.copy(); yp[s["tr"]] = rng.permutation(y[s["tr"]])
    m = RandomForestRegressor(100, max_features=0.3, n_jobs=2, random_state=0).fit(Z["ecfp"][s["tr"]], yp[s["tr"]])
    assert abs(r2(y[s["te"]], m.predict(Z["ecfp"][s["te"]]))) < 0.05
