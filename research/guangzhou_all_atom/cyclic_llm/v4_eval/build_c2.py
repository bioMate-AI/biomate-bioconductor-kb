#!/usr/bin/env python3
"""C2 peptide-enriched training set + dedup report + target-family-disjoint folds (docs/20261028_V5_PREREG_AND_LOOP_INTERFACE.md C2).
Uses Workstream 3's FROZEN files read-only (retro_recovery/data: compounds, pair_labels, targets with families, items_I/M; hashes verified).
Fold rule (proposal, to be confirmed by WS3 before any training): family id -> sha256 -> fold in {0..K-1}. For held-out fold f:
  train = pair_labels whose target's family is not in fold f, minus every compound that (a) shares a flat structure with, or (b) has Morgan-r2 Tanimoto >= 0.9 to,
  any compound appearing in a benchmark item list of a held-out-fold target (so a compound active on a training-family target and a held-out target cannot leak).
Also reports: CycPeptMPDB source-grouped fold overlap (the 9.1 % verbatim case), CycPeptMPDB vs benchmark compounds, display families vs benchmark families.
usage: python3 build_c2.py OUT_DIR [K=5]   (run from cyclic_llm/)"""
import os, sys, json, hashlib
import numpy as np, pandas as pd
from rdkit import Chem, DataStructs, RDLogger
from rdkit.Chem import rdFingerprintGenerator
RDLogger.DisableLog("rdApp.*")
HERE = os.path.dirname(os.path.abspath(__file__))
W3 = os.path.join(HERE, "..", "..", "multitarget", "integrin_chembl", "retro_recovery", "data")
DATA = os.path.join(HERE, "..", "..", "data")
TAN = 0.9
out_dir = sys.argv[1]; K = int(sys.argv[2]) if len(sys.argv) > 2 else 5
os.makedirs(out_dir, exist_ok=True)

# ---- verify frozen hashes (read-only consumption)
fz = json.load(open(f"{W3}/FROZEN_HASHES.json"))["hashes"]
for f, h in fz.items():
    p = f"{W3}/{f}" if os.path.exists(f"{W3}/{f}") else None
    if p and f.endswith((".gz", ".csv", ".tsv")):
        assert hashlib.sha256(open(p, "rb").read()).hexdigest() == h, f"frozen file changed: {f}"
T = pd.read_csv(f"{W3}/targets.csv"); C = pd.read_csv(f"{W3}/compounds.csv.gz"); P = pd.read_csv(f"{W3}/pair_labels.csv.gz")
IM = pd.read_csv(f"{W3}/items_M.csv.gz"); II = pd.read_csv(f"{W3}/items_I.csv.gz")
fam_of = dict(zip(T.target_key, T.family)); fold_of_fam = {f: int(hashlib.sha256(f.encode()).hexdigest(), 16) % K for f in T.family.unique()}
T["fold"] = T.family.map(fold_of_fam); fold_of_t = dict(zip(T.target_key, T.fold))
P["fold"] = P.target_key.map(fold_of_t); IM["fold"] = IM.target_key.map(fold_of_t); II["fold"] = II.target_key.map(fold_of_t)
gen = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048)
fps = {cid: gen.GetFingerprint(Chem.MolFromSmiles(s)) for cid, s in zip(C.compound_id, C.iso_smiles)}
flat = dict(zip(C.compound_id, C.flat_key)); cid_list = list(C.compound_id); fp_list = [fps[c] for c in cid_list]
rep = {"K": K, "fold_rule": "sha256(family_id) % K", "n_targets": int(len(T)), "n_families": int(T.family.nunique()),
       "families_per_fold": {int(k): int(v) for k, v in T.groupby("fold").family.nunique().items()},
       "targets_per_fold": {int(k): int(v) for k, v in T.groupby("fold").size().items()}, "folds": {}}
for f in range(K):
    held_items = pd.concat([IM[IM.fold == f], II[II.fold == f]]); held_c = set(held_items.compound_id)
    held_flat = {flat[c] for c in held_c}; held_fps = [fps[c] for c in held_c]
    tr = P[P.fold != f]
    cand = sorted(set(tr.compound_id)); drop_flat = {c for c in cand if flat[c] in held_flat}
    drop_sim = set()
    for c in cand:
        if c in drop_flat: continue
        if held_fps and max(DataStructs.BulkTanimotoSimilarity(fps[c], held_fps)) >= TAN: drop_sim.add(c)
    keep = tr[~tr.compound_id.isin(drop_flat | drop_sim)]
    rep["folds"][f] = {"held_out_targets": int((T.fold == f).sum()), "held_out_benchmark_compounds": len(held_c), "train_pair_rows_before": int(len(tr)), "train_compounds_before": len(cand),
                       "dropped_same_flat_structure": len(drop_flat), "dropped_tanimoto_ge_0.9": len(drop_sim), "train_pair_rows_after": int(len(keep)),
                       "train_compounds_after": int(keep.compound_id.nunique()), "train_targets": int(keep.target_key.nunique()), "train_families": int(keep.target_key.map(fam_of).nunique()),
                       "train_labels": {k: int(v) for k, v in keep.label.value_counts().items()}}
    keep[["compound_id", "target_key", "label", "value_nM", "relations", "stratum"]].to_csv(f"{out_dir}/c2_train_heldout_fold{f}.csv.gz", index=False)
    print("fold", f, json.dumps(rep["folds"][f]), flush=True)

# ---- CycPeptMPDB: the 9.1 % verbatim overlap case, random split vs source-grouped split
import csv
rows = [r for r in csv.DictReader(open(f"{DATA}/raw/CycPeptMPDB_Peptide_All.csv", encoding="utf-8-sig", errors="replace")) if r.get("PAMPA", "").strip() and r.get("SMILES")]
fk = {}
for r in rows:
    m = Chem.MolFromSmiles(r["SMILES"])
    r["flat"] = Chem.MolToSmiles(m, isomericSmiles=False) if m else None
rows = [r for r in rows if r["flat"]]
import random, re
rr = rows[:]; random.Random(1).shuffle(rr); nv = max(200, int(len(rr) * 0.15)); val, tr = rr[:nv], rr[nv:]
trs = {r["flat"] for r in tr}
rep["cycpept_random_split_val_flat_in_train"] = {"n_val": len(val), "overlap": sum(r["flat"] in trs for r in val), "frac": round(sum(r["flat"] in trs for r in val) / len(val), 3)}
srcs = sorted({r["Source"] for r in rows}); sfold = {s: int(hashlib.sha256(s.encode()).hexdigest(), 16) % K for s in srcs}
ov = []
for f in range(K):
    v = [r for r in rows if sfold[r["Source"]] == f]; t_ = {r["flat"] for r in rows if sfold[r["Source"]] != f}
    ov.append((len(v), sum(r["flat"] in t_ for r in v)))
rep["cycpept_source_grouped_folds_before_dedup"] = [{"fold": i, "n_heldout": a, "flat_overlap_with_train_sources": b, "frac": round(b / max(a, 1), 3)} for i, (a, b) in enumerate(ov)]
rep["cycpept_source_grouped_note"] = "same peptide measured by several sources: after source-grouping the remaining overlap is removed from TRAINING by flat-structure dedup (train minus held-out flat set), reported as 0 by construction"
# CycPeptMPDB vs benchmark compounds
bench_flat = set(C.flat_key)
cyc_flat = {r["flat"] for r in rows}
rep["cycpept_vs_benchmark"] = {"cycpept_unique_flat": len(cyc_flat), "benchmark_unique_flat": len(bench_flat), "shared_flat": len(cyc_flat & bench_flat)}
# display families vs benchmark families (the five display targets are in-family for v4)
disp_genes = {"PADI4", "PCSK9", "FIKK13", "APP", "IAPP"}
hit = T[T.genes.fillna("").apply(lambda g: any(x in disp_genes for x in str(g).replace(",", ";").split(";")))]
rep["display_target_families_in_benchmark"] = {"targets_matching_display_genes": hit[["target_key", "genes", "family", "fold"]].to_dict("records")}
# bound-cyclic PDB manifest: usable peptides (sequence only; X = non-canonical placeholder -> no structure to tokenise)
bc = [json.loads(l) for l in open(f"{DATA}/bound_cyclic/v2/bound_cyclic_manifest.jsonl")]
ok = [b for b in bc if b.get("status") == "ok"]
rep["bound_cyclic_v2"] = {"entries": len(bc), "status_ok": len(ok), "with_X_placeholders": sum("X" in b["peptide_seq"] for b in ok), "median_len": float(np.median([b["seq_len"] for b in ok])) if ok else None}
rep["composition_note"] = "C2 = affinity pairs (per-fold train files) + CycPeptMPDB (source-grouped) + display pools (in-family exclusion rule applies) + bound-cyclic PDB sequences; general SMILES <= 20 % of tokens; NOT trained until WS3 confirms the fold rule."
json.dump(rep, open(f"{out_dir}/c2_report.json", "w"), indent=1); print(json.dumps({k: v for k, v in rep.items() if k != "folds"}, indent=1)[:2500])
