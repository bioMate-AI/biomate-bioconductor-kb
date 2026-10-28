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


def main(cpp, outdir, chembl=None, procs=16):
    os.makedirs(outdir, exist_ok=True)
    rows = [r for r in csv.DictReader(open(cpp, encoding="utf-8-sig", errors="replace"))]
    recs = []
    for r in rows:
        try: y = float(r["Permeability"])
        except ValueError: continue
        if y <= -9.99 or not r.get("PAMPA", "").strip() or not r.get("SMILES"): continue
        c = canon(r["SMILES"])
        if c: recs.append(dict(smiles=c, y=y, source=r["Source"], id=r["ID"]))
    counts = {}
    for r in recs: counts[r["source"]] = counts.get(r["source"], 0) + 1
    held_src = split_sources(counts); held = [r for r in recs if r["source"] in held_src]; train = [r for r in recs if r["source"] not in held_src]
    held_smiles = sorted({r["smiles"] for r in held})
    train_f = filter_near_duplicates({i: r["smiles"] for i, r in enumerate(train)}, held_smiles, min_heavy=5)
    train = [r for i, r in enumerate(train) if i in train_f]
    json.dump(dict(held_out_sources=sorted(held_src), n_held_peptides=len(held), n_train_peptides_after_dedup=len(train), n_peptides_total=len(recs), threshold_top10=sorted(r["y"] for r in recs)[int(0.9 * len(recs))]), open(f"{outdir}/split.json", "w"), indent=1)
    for name, rs in (("cyclic_heldout", held), ("cyclic_train", train)):
        with open(f"{outdir}/{name}.csv", "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=["id", "smiles", "y", "source"]); w.writeheader(); w.writerows(rs)
    print("split:", len(held_src), "held-out sources;", len(held), "held-out peptides;", len(train), "train peptides after near-duplicate removal", flush=True)
    if chembl:
        lines = gzip.open(chembl, "rt").readlines(); n = max(1, len(lines) // (procs * 8)); chunks = [(lines[i:i + n], held_smiles) for i in range(0, len(lines), n)]
        seen, kept = set(), 0
        with mp.get_context("fork").Pool(procs) as p, gzip.open(f"{outdir}/pretrain_corpus.smi.gz", "wt") as out:
            for d in p.imap_unordered(_chunk_worker, chunks):
                for k, s in d.items():
                    if s not in seen: seen.add(s); out.write(s + "\n"); kept += 1
        print("pretraining corpus:", kept, "unique canonical SMILES (near-duplicates of held-out peptides removed)", flush=True)
        json.dump(dict(pretrain_unique=kept), open(f"{outdir}/corpus_stats.json", "w"))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None, int(sys.argv[4]) if len(sys.argv) > 4 else 16)
