"""Stereo-resolved within-flat-group ranking on CycPeptMPDB (measured PAMPA), pre-registered in docs/20261028_V5_PREREG_AND_LOOP_INTERFACE.md section 9.
Group = compounds sharing a flat (stereo-free) canonical SMILES but differing in isomeric SMILES. Label per isomer = mean over its rows of within-source z-scored PAMPA
(sources < 20 peptides pooled, as in loop_retro). Metrics (groups with >= 3 labelled isomers): mean within-group Spearman; and pairwise concordance over all isomer pairs with different labels.
Bootstrap over groups (B=2000). Flat-structure scorers give identical scores to all isomers -> ties -> Spearman 0 by construction (reported, not assumed).
Modes: zero_fit (scorers need no labels) and sar (a random half of each group's isomers is REVEALED to the scorer's trainer; the other half is ranked; reveal split by seed).
usage: python3 stereo_eval.py OUT.json"""
import sys, os, json, csv, random, collections
import numpy as np
from rdkit import Chem, RDLogger
from rdkit.Chem import rdFingerprintGenerator
from scipy.stats import spearmanr
RDLogger.DisableLog("rdApp.*")
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = f"{HERE}/../../data"


def load_groups(min_iso=3):
    rows = [r for r in csv.DictReader(open(f"{DATA}/raw/CycPeptMPDB_Peptide_All.csv", encoding="utf-8-sig", errors="replace")) if r.get("PAMPA", "").strip() and r.get("SMILES")]
    for r in rows: r["y"] = float(r["PAMPA"])
    rows = [r for r in rows if r["y"] > -9.99]
    cnt = collections.Counter(r["Source"] for r in rows); grp = {s: (s if cnt[s] >= 20 else "__other__") for s in cnt}
    by = collections.defaultdict(list)
    for r in rows: by[grp[r["Source"]]].append(r["y"])
    mu = {g: np.mean(v) for g, v in by.items()}; sd = {g: (np.std(v) or 1.0) for g, v in by.items()}
    iso = collections.defaultdict(lambda: {"z": [], "smiles": None, "flat": None})
    for r in rows:
        m = Chem.MolFromSmiles(r["SMILES"])
        if m is None: continue
        k = Chem.MolToSmiles(m, isomericSmiles=True); g = grp[r["Source"]]
        iso[k]["z"].append((r["y"] - mu[g]) / sd[g]); iso[k]["smiles"] = k; iso[k]["flat"] = Chem.MolToSmiles(m, isomericSmiles=False)
    flat = collections.defaultdict(list)
    for k, v in iso.items(): flat[v["flat"]].append(dict(smiles=k, label=float(np.mean(v["z"]))))
    return {f: v for f, v in flat.items() if len(v) >= min_iso}


def group_metrics(groups, score_of):
    """score_of: dict smiles -> score (missing -> group skipped for that scorer). Returns per-group spearman list and pair concordance."""
    sp, conc, tot = [], 0, 0
    for f, items in groups.items():
        s = [score_of.get(i["smiles"]) for i in items]
        if any(x is None for x in s): continue
        y = [i["label"] for i in items]
        if np.std(y) == 0: continue          # rule: groups with no label variance are excluded (Spearman undefined)
        sp.append(0.0 if len(set(s)) == 1 else float(spearmanr(s, y)[0]))
        for a in range(len(items)):
            for b in range(a + 1, len(items)):
                if y[a] != y[b] and s[a] != s[b]: tot += 1; conc += ((s[a] > s[b]) == (y[a] > y[b]))
    return sp, conc, tot


def boot(sp, B=2000, seed=0):
    rng = np.random.default_rng(seed); sp = np.array(sp)
    m = [sp[rng.integers(0, len(sp), len(sp))].mean() for _ in range(B)]; return float(sp.mean()), [float(np.percentile(m, 2.5)), float(np.percentile(m, 97.5))]


def report(name, groups, score_of):
    sp, conc, tot = group_metrics(groups, score_of)
    if not sp: return {"name": name, "n_groups_scored": 0}
    m, ci = boot(sp); return {"name": name, "n_groups_scored": len(sp), "mean_within_group_spearman": round(m, 4), "ci95": [round(ci[0], 4), round(ci[1], 4)],
                              "pair_concordance": round(conc / tot, 4) if tot else None, "n_pairs_scored": tot}


import hashlib


def split_group(items, flat_key, seed=0):
    """ONE fixed seeded split per group: ~half revealed, the rest are TARGET members. Deterministic in (flat_key, seed). Never leave-one-out: a stereo-blind
    predictor equal to the mean of the other members has within-group Spearman exactly -1 under LOO (artifact; see test_stereo_eval.py)."""
    n = len(items); order = sorted(range(n), key=lambda k: hashlib.sha256(f"{seed}|{flat_key}|{items[k]['smiles']}".encode()).hexdigest())
    n_rev = max(1, n // 2); rev = [items[k] for k in order[:n_rev]]; tgt = [items[k] for k in order[n_rev:]]
    return rev, tgt


def sar_groups(groups, seed=0, min_group=4):
    """-> list of (flat_key, revealed, target); keeps groups with >= min_group members (so >= 2 target members), non-constant labels overall AND among targets."""
    out = []
    for f, items in groups.items():
        if len(items) < min_group or np.std([i["label"] for i in items]) == 0: continue
        rev, tgt = split_group(items, f, seed)
        if len(tgt) < 2 or np.std([i["label"] for i in tgt]) == 0: continue
        out.append((f, rev, tgt))
    return out


def sar_metrics(sg, scorer, min_target_for_spearman=3):
    """scorer(revealed_items_all_groups, target_items) -> dict smiles->score. Train/update ONLY on revealed members; rank ONLY target members.
    Spearman among target members (groups with >= min_target_for_spearman targets) and pair concordance over target pairs with different labels and different scores."""
    revealed_all = [i for _, rev, _ in sg for i in rev]; sc = scorer(revealed_all, [i for _, _, tgt in sg for i in tgt])
    sp, conc, tot = [], 0, 0
    for f, rev, tgt in sg:
        s = [sc.get(i["smiles"]) for i in tgt]
        if any(x is None for x in s): continue
        y = [i["label"] for i in tgt]
        if len(tgt) >= min_target_for_spearman:
            sp.append(0.0 if len(set(s)) == 1 else float(spearmanr(s, y)[0]))
        for a in range(len(tgt)):
            for b in range(a + 1, len(tgt)):
                if y[a] != y[b] and s[a] != s[b]: tot += 1; conc += ((s[a] > s[b]) == (y[a] > y[b]))
    return sp, conc, tot


def sar_report(name, sg, scorer):
    sp, conc, tot = sar_metrics(sg, scorer)
    r = {"name": name, "n_groups_total": len(sg), "n_groups_spearman": len(sp), "n_pairs_scored": tot, "pair_concordance": round(conc / tot, 4) if tot else None}
    if sp: m, ci = boot(sp); r.update(mean_target_spearman=round(m, 4), ci95=[round(ci[0], 4), round(ci[1], 4)])
    return r


def loo_group_mean_spearman(groups):
    """DOCUMENTS the artifact: leave-one-out 'mean of the other members' predictor; returns mean within-group Spearman (= -1 exactly when labels vary)."""
    sp = []
    for f, items in groups.items():
        y = np.array([i["label"] for i in items])
        if np.std(y) == 0: continue
        pred = (y.sum() - y) / (len(y) - 1); sp.append(float(spearmanr(pred, y)[0]))
    return float(np.mean(sp)) if sp else None


def chiral_gbm_scorer(chirality=True, radius=2, nbits=2048):
    from sklearn.ensemble import HistGradientBoostingRegressor
    gen = rdFingerprintGenerator.GetMorganGenerator(radius=radius, fpSize=nbits, includeChirality=chirality)
    def feat(s):
        m = Chem.MolFromSmiles(s)
        if not chirality: m = Chem.MolFromSmiles(Chem.MolToSmiles(m, isomericSmiles=False))
        return np.array(gen.GetCountFingerprintAsNumPy(m), dtype=np.float32)
    def run(revealed, targets):
        X = np.stack([feat(i["smiles"]) for i in revealed]); y = np.array([i["label"] for i in revealed])
        m = HistGradientBoostingRegressor(max_iter=200, learning_rate=0.1, random_state=0).fit(X, y)
        Xt = np.stack([feat(i["smiles"]) for i in targets]); return {i["smiles"]: float(v) for i, v in zip(targets, m.predict(Xt))}
    return run


def revealed_mean_scorer(revealed, targets):
    mu = float(np.mean([i["label"] for i in revealed])); return {i["smiles"]: mu for i in targets}   # constant -> ties -> 0 by construction


if __name__ == "__main__":
    G = load_groups(3); n_iso = sum(len(v) for v in G.values())
    out = {"n_groups_ge3_isomers": len(G), "n_isomers": n_iso, "group_size_hist": dict(collections.Counter(len(v) for v in G.values()))}
    gen = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=1024)
    allsm = [i["smiles"] for v in G.values() for i in v]
    # flat-structure baseline: any function of a stereo-free fingerprint is identical across isomers (random linear scorer on the flat FP)
    rng = np.random.default_rng(0); w = rng.normal(size=1024)
    def flat_fp(s):
        m = Chem.MolFromSmiles(s); m = Chem.MolFromSmiles(Chem.MolToSmiles(m, isomericSmiles=False)); return np.array(list(gen.GetCountFingerprintAsNumPy(m)))
    out["flat_fp_random_linear"] = report("flat_fp_random_linear", G, {s: float(flat_fp(s) @ w) for s in allsm})
    out["random_score_control"] = report("random_scores(seed0)", G, {s: float(np.random.default_rng(abs(hash(s)) % (2**32)).normal()) for s in allsm})
    # zero-fit chiral scorers (optional, if checkpoints are given)
    if len(sys.argv) > 3:
        from atom_loop_model import AtomLoopModel
        am = AtomLoopModel.from_checkpoint(sys.argv[2], sys.argv[3]); sc = am.score(allsm); out["atom_lm_mean_logp"] = report("atom_lm_mean_logp", G, {s: v for s, v in zip(allsm, sc) if v is not None})
        out["atom_lm_cost"] = am.cost()
    sg = sar_groups(G, seed=0)
    out["sar_protocol"] = {"seed": 0, "n_groups": len(sg), "n_revealed": sum(len(r) for _, r, _ in sg), "n_target": sum(len(t_) for _, _, t_ in sg),
                           "loo_group_mean_artifact_spearman(documented, NOT a result)": round(loo_group_mean_spearman(G), 4)}
    out["sar_revealed_mean_reference"] = sar_report("revealed_mean", sg, revealed_mean_scorer)
    out["sar_chiral_fp_gbm"] = sar_report("chiral_fp_gbm", sg, chiral_gbm_scorer(True))
    out["sar_blind_flat_fp_gbm"] = sar_report("stereo_blind_fp_gbm", sg, chiral_gbm_scorer(False))
    if len(sys.argv) > 3:
        def atom_scorer(revealed, targets):
            sc = am.score([i["smiles"] for i in targets]); return {i["smiles"]: v for i, v in zip(targets, sc) if v is not None}
        out["sar_atom_lm_zero_fit"] = sar_report("atom_lm_zero_fit", sg, atom_scorer)
    json.dump(out, open(sys.argv[1], "w"), indent=1); print(json.dumps({k: v for k, v in out.items() if k != "group_size_hist"}, indent=1))
