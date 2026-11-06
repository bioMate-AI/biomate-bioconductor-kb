#!/usr/bin/env python3
"""Corpus + source-disjoint split for the all-atom cyclic-peptide LLM (allatom/PREREG.md). 
Steps: (1) split CycPeptMPDB PAMPA peptides by literature SOURCE (hash order, ~25 % of peptides held out); (2) remove from EVERY training corpus any molecule with Tanimoto >= 0.9
(Morgan r=2, 2048 bits) to a held-out peptide; (3) download + canonicalise a large public SMILES corpus (ChEMBL) and filter it the same way.
usage: build_corpus.py CycPeptMPDB.csv OUTDIR [chembl_chemreps.txt.gz] [procs=16]"""
import sys, os, csv, gzip, json, hashlib, multiprocessing as mp
from rdkit import Chem, RDLogger, DataStructs
from rdkit.Chem import AllChem
RDLogger.DisableLog("rdApp.*")
HELD_FRAC, THR, MIN_HEAVY_CHECK = 0.25, 0.9, 25


def split_sources(counts, frac=HELD_FRAC):
    """Deterministic whole-source split: sort sources by sha1(name), add to held-out until >= frac of peptides."""
    total = sum(counts.values()); held, n = set(), 0
    for s in sorted(counts, key=lambda s: hashlib.sha1(s.encode()).hexdigest()):
        if n >= frac * total: break
        held.add(s); n += counts[s]
    return held


def assign_folds(counts, k=4):
    """Deterministic whole-source k-fold assignment (PREREG A1): largest sources first, each into the fold with the fewest peptides so far."""
    tot = [0] * k; fold = {}
    for s in sorted(counts, key=lambda s: (-counts[s], hashlib.sha1(s.encode()).hexdigest())):
        j = min(range(k), key=lambda i: (tot[i], i)); fold[s] = j; tot[j] += counts[s]
    return fold


def canon(smi, max_heavy=120):
    m = Chem.MolFromSmiles(smi) if isinstance(smi, str) else None
    if m is None or m.GetNumHeavyAtoms() > max_heavy or m.GetNumHeavyAtoms() < 3: return None
    return Chem.MolToSmiles(m)


def _fp(smi):
    m = Chem.MolFromSmiles(smi); return AllChem.GetMorganFingerprintAsBitVect(m, 2, 2048) if m is not None else None


def filter_near_duplicates(cand, held_smiles, thr=THR, min_heavy=MIN_HEAVY_CHECK):
    """cand: {id: smiles}. Returns {id: smiles} with every molecule having Tanimoto >= thr to any held-out molecule removed (molecules smaller than min_heavy heavy atoms are kept without checking)."""
    hf = [f for f in (_fp(s) for s in held_smiles) if f is not None]; keep = {}
    for k, s in cand.items():
        m = Chem.MolFromSmiles(s)
        if m is None: continue
        if m.GetNumHeavyAtoms() >= min_heavy:
            f = AllChem.GetMorganFingerprintAsBitVect(m, 2, 2048)
            if hf and max(DataStructs.BulkTanimotoSimilarity(f, hf)) >= thr: continue
        keep[k] = s
    return keep


def _chunk_worker(args):
    lines, held = args; cand = {}
    for ln in lines:
        p = ln.rstrip("\n").split("\t")
        if len(p) < 2 or p[0] == "chembl_id": continue
        c = canon(p[1])
        if c: cand[p[0]] = c
    return filter_near_duplicates(cand, held)


def source_normalize(y, srcs, min_n=20):
    """Within-source z-scores; sources with < min_n peptides are z-scored together (same rule as the loop study, PREREG_LOOP L3)."""
    import numpy as np
    y = np.asarray(y, float); srcs = np.asarray(srcs); out = np.zeros(len(y)); cnt = {s: int((srcs == s).sum()) for s in set(srcs.tolist())}
    grp = np.array([s if cnt[s] >= min_n else "__other__" for s in srcs.tolist()])
    for g in set(grp.tolist()):
        m = grp == g; sd = y[m].std(); out[m] = (y[m] - y[m].mean()) / (sd if sd > 0 else 1.0)
    return out


def main(cpp, outdir, chembl=None, procs=16, k=4):
    import numpy as np
    os.makedirs(outdir, exist_ok=True)
    rows = [r for r in csv.DictReader(open(cpp, encoding="utf-8-sig", errors="replace"))]
    recs = []
    for r in rows:
        try: y = float(r["Permeability"])
        except ValueError: continue
        if y <= -9.99 or not r.get("PAMPA", "").strip() or not r.get("SMILES"): continue
        c = canon(r["SMILES"])
        if c: recs.append(dict(smiles=c, y=y, source=r["Source"], id=r["ID"]))
    yn = source_normalize([r["y"] for r in recs], [r["source"] for r in recs]); thr = float(np.quantile(yn, 0.9))
    for r, z in zip(recs, yn): r["y_norm"] = round(float(z), 4); r["hit"] = int(z >= thr)
    counts = {}
    for r in recs: counts[r["source"]] = counts.get(r["source"], 0) + 1
    fold = assign_folds(counts, k)
    for r in recs: r["fold"] = fold[r["source"]]
    summary = dict(y_norm_threshold=thr, n_peptides=len(recs), folds={})
    all_smiles = sorted({r["smiles"] for r in recs})
    for f in range(k):
        held = [r for r in recs if r["fold"] == f]; train = [r for r in recs if r["fold"] != f]
        held_sm = sorted({r["smiles"] for r in held}); keep = filter_near_duplicates({i: r["smiles"] for i, r in enumerate(train)}, held_sm, min_heavy=5)
        train = [r for i, r in enumerate(train) if i in keep]
        srcs_f = sorted({r["source"] for r in held}); summary["folds"][f] = dict(n_held=len(held), n_held_hits=sum(r["hit"] for r in held), n_train_after_dedup=len(train), n_sources=len(srcs_f),
                                                                                      top_source_share_of_hits=round(max(sum(r["hit"] for r in held if r["source"] == s) for s in srcs_f) / max(1, sum(r["hit"] for r in held)), 3))
        for name, rs in ((f"fold{f}_heldout", held), (f"fold{f}_train", train)):
            with open(f"{outdir}/{name}.csv", "w", newline="") as fh:
                w = csv.DictWriter(fh, fieldnames=["id", "smiles", "y", "y_norm", "hit", "source", "fold"]); w.writeheader(); w.writerows(rs)
    json.dump(summary, open(f"{outdir}/folds.json", "w"), indent=1); print(json.dumps(summary, indent=1), flush=True)
    if chembl:
        lines = gzip.open(chembl, "rt").readlines(); n = max(1, len(lines) // (procs * 8)); chunks = [(lines[i:i + n], all_smiles) for i in range(0, len(lines), n)]
        seen, kept = set(), 0
        with mp.get_context("fork").Pool(procs) as p, gzip.open(f"{outdir}/pretrain_corpus.smi.gz", "wt") as out:
            for d in p.imap_unordered(_chunk_worker, chunks):
                for kk, s in d.items():
                    if s not in seen: seen.add(s); out.write(s + "\n"); kept += 1
        print("pretraining corpus:", kept, "unique canonical SMILES (near-duplicates of ALL CycPeptMPDB peptides removed)", flush=True)
        json.dump(dict(pretrain_unique=kept), open(f"{outdir}/corpus_stats.json", "w"))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None, int(sys.argv[4]) if len(sys.argv) > 4 else 16)
