#!/usr/bin/env python3
"""Self-consistency -> loop pool adapter (gap G2).

The fold/self-consistency step (selfconsistency_rerank.py + build_candidates.py) emits ranked
candidates, but nothing turned those into peptide_loop's pool ({identifier,seq,smiles}) or into
peptide_verify input. This adapter joins the two.

It accepts EITHER input layout:

  (A) GROUPED  — build_candidates.py / selfconsistency candidates.jsonl, one record per target:
        {"id": "<tgt>", "candidates": [{"cand":0,"dockq":..,"likelihood":..,"scrmsd":..,"confidence":..}, ...]}
      These per-candidate entries carry NO sequence, so a --seq-source (the G1 normalised
      candidates) is required to resolve seq/smiles by (target, candidate index).

  (B) FLAT     — generator_normalizer.py canonical candidates, one record per design, each already
      carrying sequence/smiles + metrics{scrmsd,confidence,...}. No join needed (preferred path).

Output = a JSON **list** of pool records, each STRICTLY {identifier, seq, smiles} so it drops
straight into:
  * peptide_loop.py  --pool-json <pool.json>
  * peptide_verify.verify_batch(pool)
CRITICAL: verify_batch passes each pool dict as **kwargs to verify_peptide, so the pool records
must carry ONLY keys verify_peptide accepts. The fold metrics (scrmsd/confidence/dockq/likelihood)
are written to a SEPARATE --metrics-out sidecar keyed by identifier, never mixed into the pool.

Ranking (which candidates survive --top-k): self-consistency, matching selfconsistency_rerank.py —
lowest scRMSD first, tiebreak highest confidence; candidates with no scRMSD sort last.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

DESIGNABLE_SCRMSD = 2.0  # Å, RFpeptides-style designability threshold (same as selfconsistency_rerank)

_SEQ_KEYS = ("sequence", "seq", "gen_seq", "pep_seq")
_RANK_INF = float("inf")


def _seq_of(c: dict) -> Optional[str]:
    for k in _SEQ_KEYS:
        if c.get(k):
            return c[k]
    return None


def _rank_key(scrmsd, confidence) -> Tuple[float, float]:
    """Self-consistency order: scRMSD ascending, confidence descending. None scRMSD -> last."""
    return (scrmsd if scrmsd is not None else _RANK_INF, -(confidence or 0.0))


def load_jsonl(path) -> List[dict]:
    out = []
    for ln in Path(path).read_text().splitlines():
        ln = ln.strip()
        if ln.startswith("{"):
            out.append(json.loads(ln))
    return out


def is_grouped(records: List[dict]) -> bool:
    return bool(records) and isinstance(records[0].get("candidates"), list)


# --------------------------------------------------------------------------------------------
# FLAT path (generator_normalizer canonical candidates)
# --------------------------------------------------------------------------------------------
def pool_from_flat(cands: List[dict], top_k_per_target: Optional[int] = None,
                   require_designable: bool = False,
                   designable_scrmsd: float = DESIGNABLE_SCRMSD) -> Tuple[List[dict], List[dict]]:
    by_tgt: Dict[Optional[str], List[dict]] = {}
    for c in cands:
        by_tgt.setdefault(c.get("target"), []).append(c)
    pool, metrics = [], []
    for tgt, group in by_tgt.items():
        def sc(c):
            return (c.get("metrics") or {}).get("scrmsd")
        def cf(c):
            return (c.get("metrics") or {}).get("confidence")
        group = sorted(group, key=lambda c: _rank_key(sc(c), cf(c)))
        if require_designable:
            group = [c for c in group if sc(c) is not None and sc(c) < designable_scrmsd]
        if top_k_per_target:
            group = group[:top_k_per_target]
        for c in group:
            ident = c.get("design_id") or c.get("identifier")
            if not ident:
                raise ValueError(f"flat candidate missing design_id/identifier: {c}")
            seq, smi = _seq_of(c), c.get("smiles")
            if not seq and not smi:
                raise ValueError(f"candidate {ident!r} has neither sequence nor smiles")
            pool.append({"identifier": str(ident), "seq": seq, "smiles": smi})
            m = dict(c.get("metrics") or {})
            m.update({"identifier": str(ident), "target": tgt, "source": c.get("source"),
                      "pose_path": c.get("pose_path"),
                      "designable": (sc(c) is not None and sc(c) < designable_scrmsd)})
            metrics.append(m)
    return pool, metrics


# --------------------------------------------------------------------------------------------
# GROUPED path (build_candidates.py / selfconsistency candidates.jsonl) + seq join
# --------------------------------------------------------------------------------------------
def build_seq_map(normalized: List[dict]) -> Dict[Tuple[str, int], dict]:
    """{(target, candidate_index): {seq, smiles, design_id}} from the G1 normalised candidates.

    candidate_index = native['number'] if the generator recorded one (UniMoMo/M2c), else the
    positional order within that target (the order build_candidates.py also iterates)."""
    counters: Dict[Optional[str], int] = {}
    out: Dict[Tuple[str, int], dict] = {}
    for c in normalized:
        tgt = c.get("target")
        num = (c.get("native") or {}).get("number")
        if num is None:
            num = counters.get(tgt, 0)
        counters[tgt] = counters.get(tgt, 0) + 1
        try:
            idx = int(num)
        except (TypeError, ValueError):
            continue
        out[(str(tgt), idx)] = {"seq": _seq_of(c), "smiles": c.get("smiles"),
                                "design_id": c.get("design_id")}
    return out


def pool_from_grouped(grouped: List[dict], seq_map: Dict[Tuple[str, int], dict],
                      top_k_per_target: Optional[int] = None,
                      require_designable: bool = False,
                      designable_scrmsd: float = DESIGNABLE_SCRMSD) -> Tuple[List[dict], List[dict]]:
    pool, metrics, unresolved = [], [], []
    for rec in grouped:
        tgt = str(rec.get("id"))
        cands = sorted(rec.get("candidates") or [],
                       key=lambda c: _rank_key(c.get("scrmsd"), c.get("confidence")))
        if require_designable:
            cands = [c for c in cands if c.get("scrmsd") is not None and c["scrmsd"] < designable_scrmsd]
        if top_k_per_target:
            cands = cands[:top_k_per_target]
        for c in cands:
            k = c.get("cand")
            info = seq_map.get((tgt, int(k))) if k is not None else None
            if not info or (not info.get("seq") and not info.get("smiles")):
                unresolved.append((tgt, k))
                continue
            ident = info.get("design_id") or f"{tgt}_{k}"
            pool.append({"identifier": str(ident), "seq": info.get("seq"), "smiles": info.get("smiles")})
            metrics.append({"identifier": str(ident), "target": tgt, "cand": k,
                            "scrmsd": c.get("scrmsd"), "confidence": c.get("confidence"),
                            "dockq": c.get("dockq"), "likelihood": c.get("likelihood"),
                            "designable": (c.get("scrmsd") is not None and c["scrmsd"] < designable_scrmsd)})
    if unresolved:
        raise ValueError(
            f"{len(unresolved)} grouped candidate(s) had no sequence in --seq-source, e.g. {unresolved[:5]}. "
            "Point --seq-source at the SAME normalised candidates the fold step consumed (keyed by "
            "(target, candidate index)); do not emit sequence-less pool rows.")
    return pool, metrics


# --------------------------------------------------------------------------------------------
# top-level
# --------------------------------------------------------------------------------------------
def candidates_to_pool(in_path, seq_source=None, top_k_per_target=None,
                       require_designable=False) -> Tuple[List[dict], List[dict]]:
    records = load_jsonl(in_path)
    if is_grouped(records):
        if not seq_source:
            raise ValueError(
                "grouped candidates.jsonl carries no sequences — pass --seq-source "
                "(the generator_normalizer canonical candidates) to resolve seq/smiles.")
        seq_map = build_seq_map(load_jsonl(seq_source))
        return pool_from_grouped(records, seq_map, top_k_per_target, require_designable)
    return pool_from_flat(records, top_k_per_target, require_designable)


# --------------------------------------------------------------------------------------------
# selftest
# --------------------------------------------------------------------------------------------
def _selftest() -> int:
    checks = {}

    # FLAT: two targets, candidates out of scRMSD order -> pool ranked by self-consistency
    flat = [
        {"design_id": "a2", "target": "T1", "sequence": "AAA", "smiles": "CC", "source": "unimomo",
         "metrics": {"scrmsd": 2.4, "confidence": 0.5}},
        {"design_id": "a0", "target": "T1", "sequence": "BBB", "source": "unimomo",
         "metrics": {"scrmsd": 0.8, "confidence": 0.9}},   # best self-consistency
        {"design_id": "a1", "target": "T1", "sequence": "CCC", "source": "unimomo",
         "metrics": {"scrmsd": 1.5, "confidence": 0.7}},
    ]
    pool, met = pool_from_flat(flat)
    checks["flat ranked by scRMSD (a0 first)"] = [p["identifier"] for p in pool] == ["a0", "a1", "a2"]
    checks["flat pool rows are verify-safe (only id/seq/smiles)"] = all(
        set(p) == {"identifier", "seq", "smiles"} for p in pool)
    checks["flat metrics sidecar keeps scrmsd + designable"] = (
        met[0]["identifier"] == "a0" and met[0]["scrmsd"] == 0.8 and met[0]["designable"] is True
        and met[2]["designable"] is False)

    pool_k, _ = pool_from_flat(flat, top_k_per_target=1)
    checks["flat top_k=1 keeps best only"] = [p["identifier"] for p in pool_k] == ["a0"]

    pool_d, _ = pool_from_flat(flat, require_designable=True)
    checks["flat require_designable drops scRMSD>=2"] = [p["identifier"] for p in pool_d] == ["a0", "a1"]

    # GROUPED: build_candidates output + seq join from normalised candidates
    grouped = [{"id": "T1", "candidates": [
        {"cand": 0, "dockq": 0.3, "likelihood": -5.0, "scrmsd": 1.9, "confidence": 0.6},
        {"cand": 1, "dockq": 0.4, "likelihood": -8.0, "scrmsd": 0.7, "confidence": 0.9}]}]
    normalized = [
        {"design_id": "unimomo_T1_0", "target": "T1", "sequence": "SEQ0", "native": {"number": 0}},
        {"design_id": "unimomo_T1_1", "target": "T1", "sequence": "SEQ1", "native": {"number": 1}}]
    gpool, gmet = pool_from_grouped(grouped, build_seq_map(normalized))
    checks["grouped ranked (cand1 scRMSD 0.7 first) + seq joined"] = (
        [p["identifier"] for p in gpool] == ["unimomo_T1_1", "unimomo_T1_0"]
        and gpool[0]["seq"] == "SEQ1")
    checks["grouped pool rows verify-safe"] = all(set(p) == {"identifier", "seq", "smiles"} for p in gpool)
    checks["grouped metrics carry dockq/likelihood"] = (
        gmet[0]["dockq"] == 0.4 and gmet[0]["likelihood"] == -8.0)

    # grouped with a missing sequence must FAIL LOUD (no sequence-less pool rows)
    try:
        pool_from_grouped(grouped, build_seq_map(normalized[:1]))
        checks["grouped unresolved seq fails loud"] = False
    except ValueError:
        checks["grouped unresolved seq fails loud"] = True

    for k, v in checks.items():
        print(f"  {'PASS' if v else 'FAIL'}  {k}")
    ok = all(checks.values())
    print("ALL_CHECKS_PASS=" + str(ok))
    return 0 if ok else 1


def _main(argv=None):
    ap = argparse.ArgumentParser(description="Convert fold/self-consistency candidates into a peptide_loop pool.")
    ap.add_argument("--in", dest="in_path", help="candidates.jsonl (grouped build_candidates OR flat normalised)")
    ap.add_argument("--seq-source", help="generator_normalizer candidates.jsonl (required for grouped input)")
    ap.add_argument("--out", help="pool JSON list (for peptide_loop --pool-json); default stdout")
    ap.add_argument("--metrics-out", help="sidecar jsonl of per-candidate fold metrics (keyed by identifier)")
    ap.add_argument("--top-k", type=int, help="keep best K candidates per target")
    ap.add_argument("--require-designable", action="store_true", help="drop candidates with scRMSD >= 2 Å")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args(argv)
    if a.selftest:
        return _selftest()
    if not a.in_path:
        ap.error("need --in (or --selftest)")
    pool, metrics = candidates_to_pool(a.in_path, seq_source=a.seq_source,
                                       top_k_per_target=a.top_k, require_designable=a.require_designable)
    out_text = json.dumps(pool, indent=2)
    if a.out:
        Path(a.out).write_text(out_text + "\n")
        print(f"wrote {len(pool)} pool records -> {a.out}")
    else:
        print(out_text)
    if a.metrics_out:
        Path(a.metrics_out).write_text("\n".join(json.dumps(m) for m in metrics) + "\n")
        print(f"wrote {len(metrics)} metric rows -> {a.metrics_out}")
    return 0


if __name__ == "__main__":
    sys.exit(_main())
