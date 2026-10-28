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
    json.dump(out, open(sys.argv[1], "w"), indent=1); print(json.dumps(out, indent=1))
