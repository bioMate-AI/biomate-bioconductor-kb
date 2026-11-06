"""Rebuild structure-disjoint cross-validation folds for the PepMSND stability benchmark.

The supplied ``cluster`` column is intended as chemical-family folds, but an audit
(results/pepmsnd_fold_audit.json) found leakage: 29 canonical structures appear in more
than one cluster and four IDs are duplicated across clusters. Using those clusters as
CV folds would leak identical molecules between train and test, inflating any
"generalization" number.

This rebuild:
  1. Canonicalizes every SMILES (isomeric) with RDKit.
  2. Collapses rows to unique structures, aggregating IDs / clusters / labels.
  3. Surfaces structures with conflicting binary labels (does NOT silently resolve them).
  4. Diagnoses whether the original clusters can be salvaged by merging clusters that
     share an identical structure (union-find). In this dataset the 29 shared structures
     chain-link all 10 clusters into a single component, so merging yields ONE fold and
     no held-out set -- i.e. the supplied clusters are unusable as leak-free CV folds.
  5. Therefore assigns fresh label-stratified K folds directly over the unique
     structures, guaranteeing each structure (and every source ID) lives in exactly one
     fold.

Outputs a rebuilt table (one row per unique structure, with a leak-free ``fold``) and an
audit JSON asserting zero structures and zero IDs cross folds.

These folds remove duplicate/leakage artifacts and are label-balanced. They do NOT
establish scaffold-level separation between folds; a scaffold-split remains future work.
"""
import argparse
import csv
import json
from collections import Counter, defaultdict
from pathlib import Path

from rdkit import Chem
from rdkit import RDLogger

RDLogger.DisableLog("rdApp.*")

ROOT = Path(__file__).resolve().parent
DEFAULT_SRC = ROOT / (
    "data/raw/peptideclm2_pepmsnd/6b9708d4cb05717307d310daaf1c0f88c71ff084/"
    "data/PepMSND_clustered_data.csv"
)


def canonical(smiles):
    """Isomeric canonical SMILES, or None if RDKit cannot parse it."""
    mol = Chem.MolFromSmiles(smiles)
    return Chem.MolToSmiles(mol) if mol is not None else None


class UnionFind:
    def __init__(self):
        self.parent = {}

    def find(self, x):
        self.parent.setdefault(x, x)
        while self.parent[x] != x:
            self.parent[x] = self.parent[self.parent[x]]
            x = self.parent[x]
        return x

    def union(self, a, b):
        ra, rb = self.find(a), self.find(b)
        if ra != rb:
            # Keep the smaller label as the canonical root for deterministic folds.
            lo, hi = sorted((ra, rb), key=lambda c: (len(c), c))
            self.parent[hi] = lo


def rebuild(src_path, n_folds=10):
    rows = list(csv.DictReader(open(src_path)))
    for r in rows:
        r["_canon"] = canonical(r["SMILES"])
        # Fall back to a raw-string key so unparseable rows are never silently merged.
        r["_key"] = r["_canon"] if r["_canon"] else "RAW::" + r["SMILES"]

    unparseable = [r for r in rows if r["_canon"] is None]

    # Aggregate per unique structure.
    struct = defaultdict(lambda: {"ids": set(), "clusters": set(), "labels": Counter(), "rows": 0})
    for r in rows:
        s = struct[r["_key"]]
        s["ids"].add(r["ID"])
        s["clusters"].add(r["cluster"])
        s["labels"][r["label"]] += 1
        s["rows"] += 1

    # Union-find over original clusters: any structure spanning >1 cluster ties them together.
    uf = UnionFind()
    for cid in {r["cluster"] for r in rows}:
        uf.find(cid)
    for s in struct.values():
        clusters = sorted(s["clusters"])
        for c in clusters[1:]:
            uf.union(clusters[0], c)

    # Map each merged component root to a compact 1-based fold id (stable ordering).
    roots = sorted({uf.find(c) for c in {r["cluster"] for r in rows}}, key=lambda c: (len(c), c))
    root_to_fold = {root: i + 1 for i, root in enumerate(roots)}

    # Diagnostic: how many folds survive if we merge clusters that share a structure?
    merged_components = len({uf.find(c) for c in {r["cluster"] for r in rows}})

    conflicts = []
    records = []
    for key, s in struct.items():
        label_conflict = len(s["labels"]) > 1
        # Majority vote; ties resolve to the higher label deterministically but are flagged.
        majority = max(sorted(s["labels"]), key=lambda l: (s["labels"][l], l))
        rec = {
            "canonical_smiles": key,
            "n_source_rows": s["rows"],
            "source_ids": sorted(s["ids"], key=lambda x: (len(x), x)),
            "source_clusters": sorted(s["clusters"], key=lambda x: (len(x), x)),
            "merge_component": root_to_fold[uf.find(sorted(s["clusters"], key=lambda x: (len(x), x))[0])],
            "label": majority,
            "label_conflict": label_conflict,
            "label_votes": dict(s["labels"]),
        }
        records.append(rec)
        if label_conflict:
            conflicts.append(rec)

    # Fresh label-stratified K folds over unique structures (leak-free by construction):
    # sort each label stratum by canonical SMILES for determinism, then round-robin.
    for label in sorted({r["label"] for r in records}):
        stratum = sorted([r for r in records if r["label"] == label],
                         key=lambda r: r["canonical_smiles"])
        for i, rec in enumerate(stratum):
            rec["fold"] = (i % n_folds) + 1

    records.sort(key=lambda r: (r["fold"], r["canonical_smiles"]))

    # Audit: verify disjointness. One record per unique structure, so structures cannot
    # cross folds; verify IDs (a duplicated ID could otherwise split across structures).
    struct_folds = defaultdict(set)
    for r in records:
        struct_folds[r["canonical_smiles"]].add(r["fold"])
    structs_cross = [s for s, f in struct_folds.items() if len(f) > 1]
    id_folds = defaultdict(set)
    for r in records:
        for i in r["source_ids"]:
            id_folds[i].add(r["fold"])
    ids_cross = {i: sorted(f) for i, f in id_folds.items() if len(f) > 1}

    fold_sizes = Counter(r["fold"] for r in records)
    fold_labels = defaultdict(Counter)
    for r in records:
        fold_labels[r["fold"]][r["label"]] += 1

    audit = {
        "source_csv": str(src_path.relative_to(ROOT)) if src_path.is_relative_to(ROOT) else str(src_path),
        "source_rows": len(rows),
        "unparseable_smiles": len(unparseable),
        "unique_structures": len(records),
        "original_clusters": len({r["cluster"] for r in rows}),
        "cluster_merge_components": merged_components,
        "cluster_merge_verdict": (
            "unusable" if merged_components < 2 else "usable"
        ),
        "cluster_merge_note": (
            "Merging clusters that share an identical structure collapses all "
            f"{len({r['cluster'] for r in rows})} original clusters into "
            f"{merged_components} component(s); with <2 components there is no held-out "
            "fold, so the supplied clusters cannot serve as leak-free CV folds. Fresh "
            "stratified folds are used instead."
        ),
        "rebuilt_folds": len(fold_sizes),
        "fold_strategy": f"label-stratified {n_folds}-fold over unique structures",
        "fold_sizes": {str(k): v for k, v in sorted(fold_sizes.items())},
        "fold_label_balance": {
            str(k): {lbl: fold_labels[k][lbl] for lbl in sorted(fold_labels[k])}
            for k in sorted(fold_labels)
        },
        "structures_crossing_folds": len(structs_cross),
        "ids_crossing_folds": ids_cross,
        "label_conflict_structures": len(conflicts),
        "label_conflicts": [
            {"canonical_smiles": c["canonical_smiles"], "votes": c["label_votes"],
             "source_ids": c["source_ids"], "fold": c["fold"]}
            for c in conflicts
        ],
        "note": (
            "Folds are the paper's chemical clusters merged wherever an identical structure "
            "spanned clusters. Disjointness of identical structures is guaranteed; deeper "
            "scaffold separation is only as strong as the original clustering."
        ),
    }
    return records, audit


def write_outputs(records, audit, out_csv, out_audit):
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    fields = ["fold", "label", "label_conflict", "canonical_smiles", "n_source_rows",
              "source_ids", "source_clusters", "label_votes"]
    with open(out_csv, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=fields)
        w.writeheader()
        for r in records:
            w.writerow({
                "fold": r["fold"], "label": r["label"], "label_conflict": r["label_conflict"],
                "canonical_smiles": r["canonical_smiles"], "n_source_rows": r["n_source_rows"],
                "source_ids": ";".join(r["source_ids"]),
                "source_clusters": ";".join(r["source_clusters"]),
                "label_votes": json.dumps(r["label_votes"]),
            })
    out_audit.parent.mkdir(parents=True, exist_ok=True)
    out_audit.write_text(json.dumps(audit, indent=2) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", type=Path, default=DEFAULT_SRC)
    ap.add_argument("--out-csv", type=Path,
                    default=ROOT / "data/processed/pepmsnd_stability_folds.csv")
    ap.add_argument("--out-audit", type=Path,
                    default=ROOT / "results/pepmsnd_fold_rebuild.json")
    ap.add_argument("--n-folds", type=int, default=10)
    args = ap.parse_args()
    records, audit = rebuild(args.src, n_folds=args.n_folds)
    write_outputs(records, audit, args.out_csv, args.out_audit)
    print(json.dumps({k: v for k, v in audit.items()
                      if k not in ("fold_merge_map",)}, indent=2))


if __name__ == "__main__":
    main()
