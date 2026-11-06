#!/usr/bin/env python3
"""Generator-output normaliser (gap G1): heterogeneous generator outputs -> ONE canonical
candidate schema that feeds the fold / scoring loop (build_candidates.py, fold_to_pool.py).

Each generator emits a DIFFERENT layout; before this, every one was wired in by hand:

  RFpeptides   launch_rfpeptides.sh -> status/candidates_<pdb>.jsonl
               rows: {"target","backbone","seq","length","scrmsd","fold_confidence","scrmsd_computed"}
  UniMoMo      generate.py -> results/<label>/results.jsonl
               rows: per-design {id, gen_seq|gen_pep_seq|seq, number, gen_pdb|pdb, ...} (dyMEAN/PepGLAD lineage)
  BoltzGen     boltzgen_ourtarget.sh -> out/<pdb>/**/*metrics*.csv  (+ .cif/.pdb structures)
               cols include a sequence col + iptm/ptm/plddt/pae/rmsd/quality/filter
  PepGLAD-M2c  pdl1_m2c_generate.py -> pdl1_m2c_designs.jsonl
               rows: {design_id,target,variant,sequence,length,pdb_path,all_canonical,
                      head_to_tail_NC_dist,valid_for_rerank,...}

CANONICAL CANDIDATE SCHEMA (one JSON object per line in the output .jsonl):
  {
    "design_id":  str,          # unique id within the run
    "target":     str | None,   # receptor / target label
    "source":     str,          # rfpeptides | unimomo | boltzgen | pepglad_m2c
    "sequence":   str | None,   # 1-letter peptide sequence (None if only a SMILES is known)
    "smiles":     str | None,   # SMILES if the generator provided one (not fabricated here)
    "pose_path":  str | None,   # generated structure (pdb/cif), if the generator wrote one
    "length":     int | None,
    "cyclic":     bool,         # these generators design cyclic binders (head-to-tail / disulfide)
    "metrics": {                # generator-native numbers ONLY — never invented:
        "likelihood": float|None,  # generator score, HIGHER = more likely (selfconsistency sense)
        "dockq":      float|None,
        "scrmsd":     float|None,  # Å vs independent re-fold, LOWER = better (RFpeptides inline)
        "confidence": float|None,  # ipTM / pLDDT in [0,1], HIGHER = better
        ... extra source-specific keys pass through
    },
    "native": {...}             # the raw original record, for provenance / debugging
  }

HONESTY: this maps + renames + validates; it does NOT fabricate structures, SMILES, or scores.
A field the generator did not provide stays None. SMILES is derived from a canonical sequence only
when --derive-smiles is passed (RDKit MolFromSequence; non-canonical macrocycles -> None, flagged).
Unknown / unrecognised record shapes FAIL LOUD rather than emit a half-empty candidate.
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path
from typing import Dict, List, Optional

SOURCES = ("rfpeptides", "unimomo", "boltzgen", "pepglad_m2c")

# candidate keys for flexible field discovery (generators disagree on names)
_SEQ_KEYS = ("gen_seq", "gen_pep_seq", "sequence", "seq", "pep_seq", "designed_seq")
_ID_KEYS = ("design_id", "id", "name", "sample_id")
_POSE_KEYS = ("gen_pdb", "gen_pep_pdb", "pdb_path", "pose_path", "pdb", "cif", "structure")
_NUM_KEYS = ("number", "n", "idx", "index", "sample")


def _first(d: dict, keys, default=None):
    for k in keys:
        if k in d and d[k] not in (None, ""):
            return d[k]
    return default


def _num(v) -> Optional[float]:
    try:
        f = float(v)
        return f if f == f else None  # drop NaN
    except (TypeError, ValueError):
        return None


def _canon(design_id, target, source, sequence, *, smiles=None, pose_path=None,
           length=None, cyclic=True, metrics=None, native=None) -> dict:
    if sequence is None and smiles is None:
        raise ValueError(f"[{source}] candidate {design_id!r} has neither sequence nor smiles")
    if length is None and isinstance(sequence, str):
        length = len(sequence)
    return {
        "design_id": str(design_id),
        "target": target,
        "source": source,
        "sequence": sequence,
        "smiles": smiles,
        "pose_path": pose_path,
        "length": length,
        "cyclic": bool(cyclic),
        "metrics": {k: v for k, v in (metrics or {}).items()},
        "native": native or {},
    }


# --------------------------------------------------------------------------------------------
# per-generator adapters
# --------------------------------------------------------------------------------------------
def normalize_rfpeptides(records: List[dict], target: Optional[str] = None) -> List[dict]:
    """launch_rfpeptides.sh candidates_<pdb>.jsonl -> canonical. Has inline scrmsd already."""
    out = []
    for i, r in enumerate(records):
        seq = _first(r, _SEQ_KEYS)
        if seq is None:
            raise ValueError(f"[rfpeptides] record {i} has no sequence (keys={list(r)})")
        tgt = r.get("target", target)
        did = f"rfpep_{tgt}_{i:04d}"
        metrics = {
            "scrmsd": _num(r.get("scrmsd")),
            "confidence": _num(r.get("fold_confidence")),
            "scrmsd_computed": bool(r.get("scrmsd_computed", False)),
        }
        out.append(_canon(did, tgt, "rfpeptides", seq,
                          pose_path=r.get("backbone"), length=_num(r.get("length")) and int(r["length"]),
                          metrics=metrics, native=r))
    return out


def normalize_unimomo(records: List[dict], target: Optional[str] = None) -> List[dict]:
    """UniMoMo generate.py results.jsonl (per-design) -> canonical. FAIL LOUD if no sequence
    column is recognised (do not silently assume the grouped eval_report schema, which carries no
    sequences and cannot feed the fold step)."""
    out = []
    n_seq = 0
    for i, r in enumerate(records):
        seq = _first(r, _SEQ_KEYS)
        if seq is None:
            continue  # tolerate interleaved non-design rows; counted below
        n_seq += 1
        tgt = _first(r, ("target", "pdb", "receptor")) or target
        num = _first(r, _NUM_KEYS, default=i)
        rid = _first(r, _ID_KEYS, default=tgt or "unimomo")
        did = f"unimomo_{rid}_{num}"
        metrics = {
            "likelihood": _num(_first(r, ("pmet", "likelihood", "logp", "log_prob", "score", "elbo"))),
            "dockq": _num(r.get("DockQ") if not isinstance(r.get("DockQ"), dict) else None),
            "confidence": _num(_first(r, ("confidence", "iptm", "plddt"))),
        }
        out.append(_canon(did, tgt, "unimomo", seq,
                          pose_path=_first(r, _POSE_KEYS), native=r, metrics=metrics))
    if n_seq == 0:
        raise ValueError(
            "[unimomo] no record carried a sequence key "
            f"({_SEQ_KEYS}); got keys e.g. {list(records[0]) if records else '[]'}. "
            "This looks like the grouped eval_report (DockQ.individual) — point me at generate.py's "
            "results.jsonl (per-design rows with gen_seq), not the metrics eval log.")
    return out


def normalize_boltzgen(rows: List[dict], target: Optional[str] = None,
                       struct_dir: Optional[str] = None) -> List[dict]:
    """BoltzGen *metrics*.csv rows -> canonical. Discovers the sequence column + quality columns
    by name; associates a structure file by design index if struct_dir is given."""
    if not rows:
        return []
    cols = list(rows[0].keys())
    seq_col = next((c for c in cols if "seq" in c.lower()), None)
    if seq_col is None:
        raise ValueError(f"[boltzgen] no sequence column in metrics CSV (cols={cols})")
    conf_col = next((c for c in cols if c.lower() in ("iptm", "complex_iptm", "plddt", "confidence")), None)
    dockq_col = next((c for c in cols if "dockq" in c.lower()), None)
    structs = sorted(str(p) for p in Path(struct_dir).glob("**/*") if p.suffix in (".pdb", ".cif")) if struct_dir else []
    out = []
    for i, r in enumerate(rows):
        seq = r.get(seq_col)
        if not seq:
            continue
        did = f"boltzgen_{target or 'tgt'}_{i:04d}"
        metrics = {
            "confidence": _num(r.get(conf_col)) if conf_col else None,
            "dockq": _num(r.get(dockq_col)) if dockq_col else None,
        }
        # pass through any other numeric quality columns verbatim
        for c in cols:
            if c in (seq_col, conf_col, dockq_col):
                continue
            v = _num(r.get(c))
            if v is not None:
                metrics.setdefault(c.lower(), v)
        out.append(_canon(did, target, "boltzgen", seq,
                          pose_path=structs[i] if i < len(structs) else None,
                          native=r, metrics=metrics))
    if not out:
        raise ValueError(f"[boltzgen] metrics CSV had no usable sequence rows in column {seq_col!r}")
    return out


def normalize_m2c(records: List[dict], target: Optional[str] = None) -> List[dict]:
    """pdl1_m2c_generate.py pdl1_m2c_designs.jsonl -> canonical."""
    out = []
    for i, r in enumerate(records):
        seq = _first(r, _SEQ_KEYS)
        if seq is None:
            raise ValueError(f"[pepglad_m2c] record {i} has no sequence (keys={list(r)})")
        did = r.get("design_id") or f"m2c_{r.get('variant', target or 'tgt')}_{i:04d}"
        metrics = {
            "head_to_tail_NC_dist": _num(r.get("head_to_tail_NC_dist")),
            "all_canonical": bool(r.get("all_canonical", False)),
            "valid_for_rerank": bool(r.get("valid_for_rerank", True)),
        }
        out.append(_canon(did, r.get("target", target), "pepglad_m2c", seq,
                          pose_path=r.get("pdb_path"), length=_num(r.get("length")) and int(r["length"]),
                          metrics=metrics, native=r))
    return out


_ADAPTERS = {
    "rfpeptides": normalize_rfpeptides,
    "unimomo": normalize_unimomo,
    "boltzgen": normalize_boltzgen,
    "pepglad_m2c": normalize_m2c,
}


# --------------------------------------------------------------------------------------------
# optional SMILES derivation (canonical sequences only; honest about non-canonical failures)
# --------------------------------------------------------------------------------------------
def _derive_smiles(cands: List[dict]) -> int:
    from rdkit import Chem, RDLogger  # local import — optional feature
    RDLogger.DisableLog("rdApp.*")
    n = 0
    for c in cands:
        if c.get("smiles") or not c.get("sequence"):
            continue
        m = Chem.MolFromSequence(c["sequence"])
        if m is not None:
            c["smiles"] = Chem.MolToSmiles(m)
            n += 1
        else:
            c.setdefault("native", {})["smiles_derivation"] = "failed (non-canonical / unparseable)"
    return n


# --------------------------------------------------------------------------------------------
# IO + dispatch
# --------------------------------------------------------------------------------------------
def load_jsonl(path) -> List[dict]:
    out = []
    for ln in Path(path).read_text().splitlines():
        ln = ln.strip()
        if ln.startswith("{"):
            out.append(json.loads(ln))
    return out


def load_csv(path) -> List[dict]:
    with open(path, newline="") as fh:
        return list(csv.DictReader(fh))


def normalize_file(source: str, in_path: str, target: Optional[str] = None,
                   struct_dir: Optional[str] = None, derive_smiles: bool = False) -> List[dict]:
    if source not in _ADAPTERS:
        raise ValueError(f"unknown source {source!r}; expected one of {SOURCES}")
    if source == "boltzgen":
        rows = load_csv(in_path)
        cands = normalize_boltzgen(rows, target=target, struct_dir=struct_dir)
    else:
        recs = load_jsonl(in_path)
        cands = _ADAPTERS[source](recs, target=target)
    if derive_smiles:
        _derive_smiles(cands)
    return cands


# --------------------------------------------------------------------------------------------
# selftest — one synthetic sample per generator in its REAL schema
# --------------------------------------------------------------------------------------------
def _selftest() -> int:
    checks = {}

    rfp = normalize_rfpeptides([
        {"target": "9xmm", "backbone": "bb_0.pdb", "seq": "ACDEFGHIK", "length": 9,
         "scrmsd": 1.3, "fold_confidence": 0.82, "scrmsd_computed": True}], target="9xmm")
    checks["rfpeptides seq+scrmsd+conf"] = (
        rfp[0]["sequence"] == "ACDEFGHIK" and rfp[0]["source"] == "rfpeptides"
        and rfp[0]["metrics"]["scrmsd"] == 1.3 and rfp[0]["metrics"]["confidence"] == 0.82
        and rfp[0]["pose_path"] == "bb_0.pdb" and rfp[0]["length"] == 9)

    um = normalize_unimomo([
        {"id": "1yf4", "gen_seq": "WKLMNPQR", "number": 3, "gen_pdb": "d3.pdb", "pmet": -8.1},
        {"id": "1yf4", "gen_seq": "WKLMNPQS", "number": 7, "pmet": -6.2}], target="1yf4")
    checks["unimomo 2 designs, likelihood=pmet"] = (
        len(um) == 2 and um[0]["metrics"]["likelihood"] == -8.1
        and um[0]["design_id"] == "unimomo_1yf4_3" and um[0]["pose_path"] == "d3.pdb")
    # grouped eval_report (no sequences) must FAIL LOUD, not emit empties
    try:
        normalize_unimomo([{"id": "t1", "DockQ": {"individual": [0.2, 0.3]}}])
        checks["unimomo eval_report fails loud"] = False
    except ValueError:
        checks["unimomo eval_report fails loud"] = True

    bg = normalize_boltzgen([
        {"design": "0", "sequence": "CYCLICPEP", "iptm": "0.74", "ptm": "0.6", "dockq": "0.31"},
        {"design": "1", "sequence": "CYCLICPEX", "iptm": "0.55", "ptm": "0.5", "dockq": "0.22"}],
        target="1g9i")
    checks["boltzgen seq+confidence(iptm)+dockq"] = (
        len(bg) == 2 and bg[0]["metrics"]["confidence"] == 0.74
        and bg[0]["metrics"]["dockq"] == 0.31 and bg[0]["metrics"].get("ptm") == 0.6
        and bg[0]["source"] == "boltzgen")

    m2c = normalize_m2c([
        {"design_id": "L14_gen_5", "target": "PD-L1_5O45", "variant": "L14", "sequence": "NONCANONPEP",
         "length": 11, "pdb_path": "g5.pdb", "all_canonical": True, "head_to_tail_NC_dist": 1.4,
         "valid_for_rerank": True}])
    checks["m2c design_id+pose+NCdist"] = (
        m2c[0]["design_id"] == "L14_gen_5" and m2c[0]["pose_path"] == "g5.pdb"
        and m2c[0]["metrics"]["head_to_tail_NC_dist"] == 1.4 and m2c[0]["target"] == "PD-L1_5O45")

    # every candidate has the full canonical key set
    allc = rfp + um + bg + m2c
    need = {"design_id", "target", "source", "sequence", "smiles", "pose_path", "length", "cyclic", "metrics", "native"}
    checks["all candidates carry the canonical schema"] = all(need <= set(c) for c in allc)
    checks["cyclic defaults True"] = all(c["cyclic"] for c in allc)

    for k, v in checks.items():
        print(f"  {'PASS' if v else 'FAIL'}  {k}")
    ok = all(checks.values())
    print("ALL_CHECKS_PASS=" + str(ok))
    return 0 if ok else 1


def _main(argv=None):
    ap = argparse.ArgumentParser(description="Normalise a generator's output to the canonical candidate schema.")
    ap.add_argument("--source", choices=SOURCES)
    ap.add_argument("--in", dest="in_path")
    ap.add_argument("--out", help="output candidates .jsonl (default: stdout)")
    ap.add_argument("--target", help="target label if the records don't carry one")
    ap.add_argument("--struct-dir", help="(boltzgen) directory of design .pdb/.cif structures")
    ap.add_argument("--derive-smiles", action="store_true",
                    help="derive SMILES from canonical sequences via RDKit (non-canonical -> None)")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args(argv)
    if a.selftest:
        return _selftest()
    if not (a.source and a.in_path):
        ap.error("need --source and --in (or --selftest)")
    cands = normalize_file(a.source, a.in_path, target=a.target,
                           struct_dir=a.struct_dir, derive_smiles=a.derive_smiles)
    text = "\n".join(json.dumps(c) for c in cands)
    if a.out:
        Path(a.out).write_text(text + "\n")
        print(f"wrote {len(cands)} candidates -> {a.out}")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    sys.exit(_main())
