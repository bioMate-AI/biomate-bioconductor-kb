"""G4: precompute per-candidate permeability predictions for a candidate pool.

Closes wiring gap G4 (score_permeability -> gate_and_verify). Until now
peptide_verify._score_permeability RE-TRAINED the full CycPeptMPDB bootstrap-bagged
ensemble FROM SCRATCH for *every candidate* (perm.load + perm.bagged_fit_predict inside
the per-candidate call). In a pool of N candidates that is N full retrains — O(N) wasted
training passes. There was also no step that emits a predictor CSV the loop can consume.

This script trains the ensemble ONCE on CycPeptMPDB, predicts the whole pool in a single
batched ensemble call, and writes a per-candidate CSV:

    identifier,sequence,smiles,logPapp_mean,logPapp_std

peptide_verify._score_permeability now LOOKS UP this CSV (via perm_pred_csv=) by identifier
-> smiles -> sequence, and only falls back to train-on-the-fly when no precomputed row exists.
Behaviour is unchanged when no CSV is supplied (exact same numbers, just recomputed).
"""
from __future__ import annotations

import argparse
import csv
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

ROOT = Path(__file__).resolve().parent


def _load_module(name: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)  # type: ignore[union-attr]
    return mod


def _read_pool(path: Path) -> List[Dict[str, Any]]:
    text = path.read_text().strip()
    if text.startswith("["):
        rows = json.loads(text)
    elif path.suffix == ".csv":
        rows = list(csv.DictReader(open(path)))
    else:  # JSONL
        rows = [json.loads(ln) for ln in text.splitlines() if ln.strip()]
    return [r for r in rows if isinstance(r, dict)]


def _cid(rec: Dict[str, Any]) -> str:
    for k in ("identifier", "design_id", "id", "Peptide_ID"):
        if rec.get(k):
            return str(rec[k])
    return ""


def _seq(rec: Dict[str, Any]) -> Optional[str]:
    for k in ("sequence", "seq", "Sequence", "Sequence_N_to_C"):
        if rec.get(k):
            return str(rec[k])
    return None


def _smiles(rec: Dict[str, Any]) -> Optional[str]:
    for k in ("smiles", "SMILES"):
        if rec.get(k):
            return str(rec[k])
    return None


def predict_pool(pool: List[Dict[str, Any]], train_csv: Path,
                 n_bags: int = 5) -> List[Dict[str, Any]]:
    """Train the CycPeptMPDB ensemble ONCE, predict every candidate in one batched call."""
    import numpy as np
    from rdkit import Chem, RDLogger
    from rdkit.Chem import rdFingerprintGenerator

    RDLogger.DisableLog("rdApp.*")
    perm = _load_module("permeability_predictor")
    fpgen = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048)

    feats, keep = [], []
    skipped = []
    for rec in pool:
        smi, sq = _smiles(rec), _seq(rec)
        mol = Chem.MolFromSmiles(smi) if smi else None
        if mol is None and sq:
            mol = Chem.MolFromSequence(sq)
        if mol is None:
            skipped.append({"identifier": _cid(rec), "reason": "no RDKit mol from seq/smiles"})
            continue
        feats.append(np.asarray(fpgen.GetFingerprint(mol), dtype=np.float32))
        keep.append(rec)

    out: List[Dict[str, Any]] = []
    if feats:
        X, y, _ = perm.load(str(train_csv))          # train data loaded ONCE
        if len(y) == 0:
            raise SystemExit(f"FATAL: training set empty after filtering: {train_csv}")
        feat_mat = np.vstack(feats)
        mean, std = perm.bagged_fit_predict(X, y, feat_mat, n=n_bags)   # ensemble trained ONCE
        for rec, mu, sd in zip(keep, mean, std):
            out.append({"identifier": _cid(rec), "sequence": _seq(rec) or "",
                        "smiles": _smiles(rec) or "",
                        "logPapp_mean": round(float(mu), 4), "logPapp_std": round(float(sd), 4)})
    if skipped:
        print(f"[warn] {len(skipped)} candidate(s) skipped (no RDKit mol)", file=sys.stderr)
    return out


def write_csv(rows: List[Dict[str, Any]], out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    cols = ["identifier", "sequence", "smiles", "logPapp_mean", "logPapp_std"]
    with open(out, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="G4: precompute per-candidate permeability predictions.")
    ap.add_argument("--pool", type=Path, required=True,
                    help="candidate pool JSON/JSONL/CSV with identifier + sequence/smiles")
    ap.add_argument("--train-csv", type=Path,
                    help="CycPeptMPDB training CSV (default: registry/committed path)")
    ap.add_argument("--out", type=Path, required=True, help="output per-candidate predictions CSV")
    ap.add_argument("--n-bags", type=int, default=5)
    args = ap.parse_args(argv)

    train_csv = args.train_csv
    if train_csv is None:
        # G8: resolve through the shared registry resolver (cache-first, committed fallback)
        train_csv = _load_module("dataset_path").resolve(
            "cycpeptmpdb", "data/raw/CycPeptMPDB_Peptide_All.csv")
    train_csv = Path(train_csv)
    if not train_csv.exists():
        print(f"[error] training CSV not found: {train_csv}", file=sys.stderr)
        return 2

    pool = _read_pool(args.pool)
    rows = predict_pool(pool, train_csv, n_bags=args.n_bags)
    write_csv(rows, args.out)
    print(f"wrote {len(rows)} permeability predictions -> {args.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
