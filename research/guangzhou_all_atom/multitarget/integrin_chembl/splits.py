"""Split construction (S0, S1, S2, S2b, S3, S3b). Pure functions on DataFrames; leakage is unit-tested in tests/."""
import numpy as np, pandas as pd
SIM = 0.6
EXT_DOC = "KAPP2017"; EXCLUDE_DOCS_S3 = {"CHEMBL5214901"}   # Tomassi 2021 (ChEMBL); Kapp 2017 and Quigley 2023 are not in ChEMBL (verified by DOI and PMID)
def load(data="data"):
    L = pd.read_csv(f"{data}/long_all.csv.gz"); U = L[L.censor == "eq"].rename(columns={"cmpd_key": "ck", "target": "t", "pact": "y"})[["doc", "ck", "t", "y", "remapped"]].reset_index(drop=True)
    P = pd.read_csv(f"{data}/pairs_all.csv.gz"); Pp = P[P.same_class].rename(columns={"cmpd_key": "ck", "delta": "delta"})[["doc", "ck", "tA", "tB", "delta"]].reset_index(drop=True)
    ends = set(zip(Pp.doc, Pp.ck, Pp.tA)) | set(zip(Pp.doc, Pp.ck, Pp.tB))
    U["inE"] = [(d, c, t) in ends for d, c, t in zip(U.doc, U.ck, U.t)]
    cl = pd.read_csv(f"{data}/compound_clusters.csv.gz"); clus = dict(zip(cl.cmpd_key, cl.cluster))
    X = pd.read_csv(f"{data}/external_cells.csv"); X = X[X.censor == "="].rename(columns={"flat_key": "ck", "target": "t", "pact": "y"}); X["doc"] = EXT_DOC
    xs = X[["doc", "ck", "t", "y"]].reset_index(drop=True); rows = []
    for ck, g in xs.groupby("ck"):
        ts = sorted(g.t.unique()); yy = dict(zip(g.t, g.y))
        for i in range(len(ts)):
            for j in range(i + 1, len(ts)): rows.append(dict(doc=EXT_DOC, ck=ck, tA=ts[i], tB=ts[j], delta=yy[ts[i]] - yy[ts[j]]))
    return U, Pp, clus, xs, pd.DataFrame(rows)
def maxsim_to(T, ci_all, ci_test):
    """max Tanimoto of each compound (global index array ci_all) to the set ci_test."""
    return np.asarray(T[:, list(ci_test)]).max(1)[np.asarray(ci_all)] if len(ci_test) else np.zeros(len(ci_all))
def fold_spec(U, Pp, test_rows, test_pairs, train_rows_mask, train_pairs_mask, doc_null=False):
    return dict(train=U[train_rows_mask][["doc", "ck", "t", "y"]], train_pairs=Pp[train_pairs_mask], test=test_rows, test_pairs=test_pairs, use_doc_null=doc_null)
def make_folds(split, U, Pp, clus, xs, xp, ci_of, T, seed=0):
    """Returns list of (fold_id, spec, test_group_fn_name). Compounds identified by flat InChIKey (ck)."""
    folds = []; rng = np.random.RandomState(seed); allck = pd.Series(sorted(set(U.ck)))
    ciarr = np.array([ci_of[c] for c in allck]); ckci = dict(zip(allck, ciarr)); Ur = U; E = U[U.inE]
    if split == "S0":
        units = E[["doc", "ck"]].drop_duplicates().reset_index(drop=True); units["f"] = rng.permutation(len(units)) % 5
        fu = {(d, c): f for d, c, f in zip(units.doc, units.ck, units.f)}
        uf = np.array([fu.get((d, c), -1) for d, c in zip(U.doc, U.ck)]); pf = np.array([fu[(d, c)] for d, c in zip(Pp.doc, Pp.ck)])
        for k in range(5):
            te = U[(uf == k) & U.inE.values][["doc", "ck", "t", "y"]]; tp = Pp[pf == k]
            folds.append((f"S0_{k}", fold_spec(U, Pp, te, tp, uf != k, pf != k, True)))
    elif split == "S1":
        cl_ids = sorted(set(clus[c] for c in allck)); fcl = dict(zip(cl_ids, rng.permutation(len(cl_ids)) % 10))
        ckf = np.array([fcl[clus[c]] for c in U.ck])
        for k in range(10):
            testcks = set(allck[[fcl[clus[c]] == k for c in allck]]); tci = [ckci[c] for c in testcks]
            far = dict(zip(allck, maxsim_to(T, ciarr, tci) < SIM)); trm = np.array([(c not in testcks) and far[c] for c in U.ck])
            te = U[U.ck.isin(testcks) & U.inE][["doc", "ck", "t", "y"]]; tp = Pp[Pp.ck.isin(testcks)]
            pm = np.array([(c not in testcks) and far[c] for c in Pp.ck])
            if len(te): folds.append((f"S1_{k}", fold_spec(U, Pp, te, tp, trm, pm, True)))
    elif split in ("S2", "S2b"):
        for d in sorted(Pp.doc.unique()):
            dcks = set(U[U.doc == d].ck); te = E[E.doc == d][["doc", "ck", "t", "y"]]; tp = Pp[Pp.doc == d]
            far = {c: True for c in allck}
            if split == "S2b": far = dict(zip(allck, maxsim_to(T, ciarr, [ckci[c] for c in dcks]) < SIM))
            trm = np.array([(dd != d) and (c not in dcks) and far.get(c, True) for dd, c in zip(U.doc, U.ck)])
            pm = np.array([(dd != d) and (c not in dcks) and far.get(c, True) for dd, c in zip(Pp.doc, Pp.ck)])
            folds.append((f"{split}_{d}", fold_spec(U, Pp, te, tp, trm, pm, False)))
    elif split in ("S3", "S3b"):
        xcks = set(xs.ck); far = {c: True for c in allck}
        if split == "S3b": far = dict(zip(allck, maxsim_to(T, ciarr, [ci_of[c] for c in xcks if c in ci_of]) < SIM))
        trm = np.array([(d not in EXCLUDE_DOCS_S3) and (c not in xcks) and far.get(c, True) for d, c in zip(U.doc, U.ck)])
        pm = np.array([(d not in EXCLUDE_DOCS_S3) and (c not in xcks) and far.get(c, True) for d, c in zip(Pp.doc, Pp.ck)])
        folds.append((split, fold_spec(U, Pp, xs, xp, trm, pm, False)))
    return folds
