"""G5: selection JSON  ->  CRO synthesis RFQ CSV (GenScript CRO_SEND format).

Closes wiring gap G5 (multi_objective_select -> synth_rfq): until now the
``results/*_CRO_order.csv`` / ``results/CRO_SEND_*.csv`` panels were assembled BY HAND
from a selection result. This script does that conversion deterministically.

Design constraints (from the program rules):
  * SCORE-FREE BY CONSTRUCTION. The CRO gets a clean synthesis order only — sequence,
    cyclization, purity, QC, quantity, priority. No internal design scores (ΔG, iPTM,
    pAffinity, HVI, RUSH) are ever written to the CRO CSV. The columns are fixed to the
    GenScript CRO_SEND schema; there is no code path that emits a score column.
  * The ordered pick + order come from the selection result; the sequence/cyclization come
    from the candidate pool (selection results carry ids, not sequences).

Inputs
------
--selection  Selection JSON. Accepted shapes (auto-detected):
    (a) peptide_select SelectionResult.to_dict  -> uses ``selected`` (ordered ids).
    (b) mo_select_qnehvi pool JSON              -> --pool-target + --rank picks
        pools.<target>.<rank>_topk  (rank in {composite, qnehvi, greedy_hv}); these rows
        already carry ``seq`` inline, so --pool is optional.
    (c) a plain JSON list of ids, or of {id|identifier|design_id, seq?, smiles?} dicts.
--pool       Candidate pool JSON/JSONL used to resolve id -> sequence/smiles when the
             selection carries only ids. Accepts verify-json (list of PeptideProperties
             .to_dict), canonical candidates (generator_normalizer schema: design_id/
             sequence/smiles/length/cyclic), or a plain list of {id,seq,smiles} dicts.
--prefix     CRO item prefix (e.g. PDL1-A, AVB6-B). Items are <prefix>-01, <prefix>-02, ...

Output: a CRO_SEND CSV with the exact ship-ready columns.
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parent

# Fixed GenScript CRO_SEND schema (matches results/CRO_SEND_*.csv exactly). Score-free.
CRO_COLUMNS = [
    "Item", "Sequence_N_to_C", "Length", "Cyclization",
    "Purity", "Quantity_mg", "Salt_form", "QC", "Priority",
]
DEFAULTS = {
    "Cyclization": "Head-to-tail backbone amide (no free termini)",
    "Purity": ">=95% (RP-HPLC)",
    "Quantity_mg": "5",
    "Salt_form": "Acetate (TFA-free)",
    "QC": "RP-HPLC, ESI-MS, net peptide content, CoA",
    "Priority": "Expedite",
}
# Score-like keys that must NEVER reach a CRO CSV (defensive guard, see _assert_score_free).
_SCORE_KEYS = {
    "mm_gbsa_dg", "mm_gbsa", "dg", "iptm", "ptm", "rush", "paff", "paffinity", "paffinity",
    "hvi", "acquisition", "binding", "affinity", "score", "rank", "bind_q", "iface_pae",
    "iface_hbonds", "dsasa_a2", "logpapp", "permeability", "sa_score", "composite",
}


# ---------------------------------------------------------------------------- pool loading
def _norm_id(rec: Dict[str, Any]) -> Optional[str]:
    for k in ("identifier", "design_id", "id", "Peptide_ID", "peptide_id"):
        v = rec.get(k)
        if v:
            return str(v)
    return None


def _norm_seq(rec: Dict[str, Any]) -> Optional[str]:
    for k in ("sequence", "seq", "Sequence", "Sequence_N_to_C"):
        v = rec.get(k)
        if v:
            return str(v)
    return None


def _norm_smiles(rec: Dict[str, Any]) -> Optional[str]:
    for k in ("smiles", "SMILES"):
        v = rec.get(k)
        if v:
            return str(v)
    return None


def _norm_cyclic(rec: Dict[str, Any]) -> Optional[str]:
    # Only a human-readable cyclization STRING maps to the CRO column; a bare bool -> default.
    v = rec.get("Cyclization") or rec.get("cyclization")
    return str(v) if isinstance(v, str) and v.strip() else None


def load_pool_from_rows(rows: List[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    """id -> {seq, smiles, cyclization?} from already-parsed pool records."""
    pool: Dict[str, Dict[str, Any]] = {}
    for rec in rows:
        if not isinstance(rec, dict):
            continue
        cid = _norm_id(rec)
        if not cid:
            continue
        pool[cid] = {"seq": _norm_seq(rec), "smiles": _norm_smiles(rec),
                     "cyclization": _norm_cyclic(rec)}
    return pool


def load_pool(path: Optional[Path]) -> Dict[str, Dict[str, Any]]:
    """id -> {seq, smiles, cyclization?} from a pool JSON / JSONL. Empty if path is None."""
    if not path:
        return {}
    text = Path(path).read_text().strip()
    if text.startswith("["):
        rows = json.loads(text)
    else:  # JSONL
        rows = [json.loads(ln) for ln in text.splitlines() if ln.strip()]
    return load_pool_from_rows(rows)


# ------------------------------------------------------------------- selection extraction
def extract_selection(sel: Any, *, pool_target: Optional[str],
                      rank: str) -> List[Dict[str, Any]]:
    """Return an ordered list of {id, seq?, smiles?, cyclization?} from any accepted shape."""
    # (c1) plain list
    if isinstance(sel, list):
        out = []
        for i, it in enumerate(sel):
            if isinstance(it, str):
                out.append({"id": it})
            elif isinstance(it, dict):
                out.append({"id": _norm_id(it) or f"sel-{i+1:02d}", "seq": _norm_seq(it),
                            "smiles": _norm_smiles(it), "cyclization": _norm_cyclic(it)})
        return out
    if not isinstance(sel, dict):
        raise ValueError("selection JSON must be a list or an object")
    # (a) SelectionResult.to_dict
    if "selected" in sel and isinstance(sel["selected"], list):
        return [{"id": str(i)} for i in sel["selected"]]
    # (b) mo_select_qnehvi pool JSON
    if "pools" in sel and isinstance(sel["pools"], dict):
        pools = sel["pools"]
        if not pool_target:
            if len(pools) == 1:
                pool_target = next(iter(pools))
            else:
                raise ValueError(f"--pool-target required; choices: {sorted(pools)}")
        if pool_target not in pools:
            raise ValueError(f"pool-target {pool_target!r} not in {sorted(pools)}")
        key = f"{rank}_topk"
        block = pools[pool_target]
        if key not in block:
            raise ValueError(f"rank {key!r} not in pool {pool_target!r}: {sorted(block)}")
        out = []
        for i, row in enumerate(block[key]):
            out.append({"id": _norm_id(row) or f"{pool_target}-{i+1:02d}",
                        "seq": _norm_seq(row), "smiles": _norm_smiles(row),
                        "cyclization": _norm_cyclic(row)})
        return out
    raise ValueError("unrecognised selection JSON shape (no 'selected'/'pools'/list)")


# -------------------------------------------------------------------------------- assembly
def _assert_score_free(row: Dict[str, str]) -> None:
    """Defensive: fail loud if any score-like value leaked into a CRO row."""
    extra = set(row) - set(CRO_COLUMNS)
    if extra:
        raise AssertionError(f"non-CRO columns would ship to CRO: {sorted(extra)}")


def make_fto_gate(library_csv: Optional[Path] = None, cutoff: float = 0.85,
                  max_rows: Optional[int] = None, cyclic_default: bool = True,
                  check_patents: bool = False):
    """Build a novelty/FTO gate callable: (cid, seq, smiles, cyclic) -> verdict dict.

    GENERAL (small molecule + peptide): delegates to drug_novelty_fto.score_candidate,
    which runs structure (Morgan/Tanimoto vs a known-actives library), optional patent
    (SureChEMBL/PubChem), and — for peptides — sequence-identity axes. Fail-OPEN: if
    RDKit or the library is unavailable the gate returns verdict="unknown"/occupied=None
    and never drops a candidate silently. The library is fingerprinted once (cached) on
    first call. See docs for the peptide-Tanimoto-baseline caveat on the cutoff.
    """
    state: Dict[str, Any] = {"lib": None, "ready": None, "err": None, "nf": None}

    def _ensure():
        if state["ready"] is not None:
            return state["ready"]
        try:
            import importlib
            nf = importlib.import_module("drug_novelty_fto")
            state["nf"] = nf
            if library_csv and Path(library_csv).exists():
                cache = ROOT / "data/_registry_cache/novelty_lib_binding_affinity_v1.pkl"
                state["lib"] = nf.build_library(
                    str(library_csv), smiles_col="smiles", id_col="id",
                    tag_cols=["is_pdl1", "is_avb6", "target_name"],
                    max_rows=max_rows, cache_path=str(cache))
            state["ready"] = True
        except Exception as e:  # noqa: BLE001 — fail-open
            state["err"] = f"{type(e).__name__}: {e}"
            state["ready"] = False
        return state["ready"]

    def gate(cid: str, seq: Optional[str], smiles: Optional[str],
             cyclic: bool = cyclic_default) -> dict:
        if not _ensure():
            return {"candidate_id": cid, "occupied": None, "verdict": "unknown",
                    "reasons": [f"gate_unavailable: {state['err']}"]}
        nf = state["nf"]
        v = nf.score_candidate(cid, smiles=smiles, seq=seq,
                               modality="peptide" if seq and not smiles else "auto",
                               cyclic=cyclic, library=state["lib"],
                               tanimoto_cutoff=cutoff, check_patents=check_patents)
        from dataclasses import asdict as _asdict
        return _asdict(v)

    return gate


def build_rfq(selection: List[Dict[str, Any]], pool: Dict[str, Dict[str, Any]],
              prefix: str, *, quantity_mg: str = DEFAULTS["Quantity_mg"],
              priority: str = DEFAULTS["Priority"],
              fto_gate=None, fto_drop: bool = True,
              fto_records: Optional[List[dict]] = None) -> Tuple[List[Dict[str, str]], List[str]]:
    """Return (CRO rows, warnings). Rows carry ONLY CRO_COLUMNS (score-free by construction).

    Novelty/FTO filtering (opt-in): if ``fto_gate`` is given, every resolved candidate is
    scored for occupancy (known-active re-discovery / patent / sequence match) BEFORE it can
    ship. ``fto_drop=True`` removes an occupied candidate (the default — validation+filtering);
    ``fto_drop=False`` keeps it but warns (FLAG-only). Verdicts are appended to ``fto_records``
    for the audit sidecar. Fail-OPEN: verdict ``occupied is None`` (gate couldn't run) never
    drops a candidate.
    """
    rows: List[Dict[str, str]] = []
    warnings: List[str] = []
    i = 0
    for pick in selection:
        cid = pick.get("id", "")
        src = {**pool.get(cid, {}), **{k: v for k, v in pick.items() if v}}  # pick overrides pool
        seq = src.get("seq")
        if not seq:
            warnings.append(f"DROP {cid}: no sequence in selection or pool")
            continue
        if fto_gate is not None:
            verdict = fto_gate(cid, seq, src.get("smiles"))
            if fto_records is not None:
                fto_records.append(verdict)
            if verdict.get("occupied") is True:
                why = "; ".join(verdict.get("reasons", [])) or verdict.get("verdict", "occupied")
                if fto_drop:
                    warnings.append(f"DROP {cid}: FTO/novelty occupied ({why})")
                    continue
                warnings.append(f"FLAG {cid}: FTO/novelty occupied ({why}) — kept (flag-only)")
        i += 1
        cyc = src.get("cyclization") or DEFAULTS["Cyclization"]
        row = {
            "Item": f"{prefix}-{i:02d}",
            "Sequence_N_to_C": seq,
            "Length": str(len(seq)),
            "Cyclization": cyc,
            "Purity": DEFAULTS["Purity"],
            "Quantity_mg": str(quantity_mg),
            "Salt_form": DEFAULTS["Salt_form"],
            "QC": DEFAULTS["QC"],
            "Priority": priority,
        }
        _assert_score_free(row)
        rows.append(row)
    return rows, warnings


def write_csv(rows: List[Dict[str, str]], out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=CRO_COLUMNS)
        w.writeheader()
        w.writerows(rows)


# ------------------------------------------------------------------------------- self-test
def _selftest() -> int:
    import tempfile
    td = Path(tempfile.mkdtemp())
    # (a) SelectionResult + pool
    sel = {"selected": ["c2", "c1"], "pareto_front": ["c1", "c2", "c3"]}
    pool = [{"identifier": "c1", "sequence": "ACDEF", "smiles": "X"},
            {"identifier": "c2", "sequence": "GHIKL",
             "cyclization": "Disulfide (Cys1-Cys5)"}]
    (td / "sel.json").write_text(json.dumps(sel))
    (td / "pool.json").write_text(json.dumps(pool))
    rows, warn = build_rfq(extract_selection(sel, pool_target=None, rank="qnehvi"),
                           load_pool(td / "pool.json"), "PDL1-A")
    assert [r["Item"] for r in rows] == ["PDL1-A-01", "PDL1-A-02"], rows
    assert rows[0]["Sequence_N_to_C"] == "GHIKL" and rows[0]["Length"] == "5", rows[0]
    assert rows[0]["Cyclization"] == "Disulfide (Cys1-Cys5)", "pool cyclization string lost"
    assert rows[1]["Cyclization"] == DEFAULTS["Cyclization"], "default cyclization wrong"
    assert not warn, warn
    # (b) mo_select_qnehvi pool shape (seqs inline, no pool needed)
    mo = {"pools": {"PD-L1": {"qnehvi_topk": [{"seq": "MNPQR", "pAff": 7.1},
                                              {"seq": "STVWY", "pAff": 6.9}]}}}
    rows2, warn2 = build_rfq(extract_selection(mo, pool_target="PD-L1", rank="qnehvi"),
                             {}, "PDL1-A")
    assert [r["Sequence_N_to_C"] for r in rows2] == ["MNPQR", "STVWY"], rows2
    # score columns (pAff) must NOT appear
    assert all(set(r) == set(CRO_COLUMNS) for r in rows2), "score leaked into CRO row"
    # (c) missing sequence -> warn + drop, not crash
    rows3, warn3 = build_rfq(extract_selection(["ghost"], pool_target=None, rank="qnehvi"),
                             {}, "AVB6-B")
    assert rows3 == [] and len(warn3) == 1, (rows3, warn3)
    # (d) FTO gate: occupied candidate is DROPPED (and items renumber contiguously)
    def _stub_gate(cid, seq, smiles, cyclic=True):
        occ = (seq == "GHIKL")   # pretend the first pick is a known active
        return {"candidate_id": cid, "occupied": occ, "verdict": "known_active" if occ else "novel",
                "reasons": ["structure: max_tanimoto 0.90 >= 0.85"] if occ else []}
    recs: List[dict] = []
    rows4, warn4 = build_rfq(extract_selection(sel, pool_target=None, rank="qnehvi"),
                             load_pool(td / "pool.json"), "PDL1-A",
                             fto_gate=_stub_gate, fto_records=recs)
    assert [r["Sequence_N_to_C"] for r in rows4] == ["ACDEF"], rows4   # GHIKL dropped
    assert rows4[0]["Item"] == "PDL1-A-01", rows4                      # contiguous renumber
    assert len(recs) == 2 and any("DROP" in w and "FTO" in w for w in warn4), (recs, warn4)
    # (e) FTO flag-only: occupied candidate is KEPT but warned
    recs2: List[dict] = []
    rows5, warn5 = build_rfq(extract_selection(sel, pool_target=None, rank="qnehvi"),
                             load_pool(td / "pool.json"), "PDL1-A",
                             fto_gate=_stub_gate, fto_drop=False, fto_records=recs2)
    assert len(rows5) == 2 and any("FLAG" in w for w in warn5), (rows5, warn5)
    # (f) FTO fail-open: occupied=None never drops
    def _unavail_gate(cid, seq, smiles, cyclic=True):
        return {"candidate_id": cid, "occupied": None, "verdict": "unknown", "reasons": ["gate_unavailable"]}
    rows6, _ = build_rfq(extract_selection(sel, pool_target=None, rank="qnehvi"),
                         load_pool(td / "pool.json"), "PDL1-A", fto_gate=_unavail_gate)
    assert len(rows6) == 2, rows6
    # write round-trip
    write_csv(rows, td / "out.csv")
    back = list(csv.DictReader(open(td / "out.csv")))
    assert back[0]["Item"] == "PDL1-A-01" and "pAff" not in back[0]
    print("select_to_rfq self-test: OK (3 shapes, score-free guard, FTO drop/flag/fail-open, csv round-trip)")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="G5: selection JSON -> CRO synthesis RFQ CSV (score-free).")
    ap.add_argument("--selftest", action="store_true", help="run built-in tests and exit")
    ap.add_argument("--selection", type=Path, help="selection JSON (SelectionResult / mo pool / id list)")
    ap.add_argument("--pool", type=Path, help="candidate pool JSON/JSONL to resolve id -> sequence")
    ap.add_argument("--prefix", default="CRO", help="CRO item prefix, e.g. PDL1-A")
    ap.add_argument("--pool-target", help="for mo_select pool JSON: which target key")
    ap.add_argument("--rank", default="qnehvi", choices=["composite", "qnehvi", "greedy_hv"],
                    help="for mo_select pool JSON: which ranking's top-k to ship")
    ap.add_argument("--quantity-mg", default=DEFAULTS["Quantity_mg"])
    ap.add_argument("--priority", default=DEFAULTS["Priority"])
    ap.add_argument("--out", type=Path, help="output CRO CSV (default: stdout)")
    # Novelty / FTO gate (validation+filtering before the CRO order). General (small mol + peptide).
    ap.add_argument("--fto-gate", action="store_true",
                    help="screen each candidate for novelty/FTO occupancy before shipping")
    ap.add_argument("--fto-library", type=Path,
                    default=ROOT / "data/raw/binding_affinity/binding_affinity_v1.csv",
                    help="known-actives CSV (SMILES) for the structure axis")
    ap.add_argument("--fto-cutoff", type=float, default=0.85,
                    help="Tanimoto cutoff; max_tanimoto >= cutoff => occupied (not novel)")
    ap.add_argument("--fto-max-rows", type=int, default=None, help="cap library rows (speed)")
    ap.add_argument("--fto-check-patents", action="store_true",
                    help="also run coarse SureChEMBL/PubChem patent presence (network)")
    ap.add_argument("--fto-flag-only", action="store_true",
                    help="do NOT drop occupied candidates; keep + warn (flag-only)")
    ap.add_argument("--fto-report", type=Path,
                    help="write per-candidate FTO verdict JSON (default: <out>.fto.json)")
    args = ap.parse_args(argv)

    if args.selftest:
        return _selftest()
    if not args.selection:
        ap.error("--selection is required (or use --selftest)")

    sel = json.loads(Path(args.selection).read_text())
    selection = extract_selection(sel, pool_target=args.pool_target, rank=args.rank)
    pool = load_pool(args.pool)

    fto_gate = None
    fto_records: List[dict] = []
    if args.fto_gate:
        fto_gate = make_fto_gate(library_csv=args.fto_library, cutoff=args.fto_cutoff,
                                 max_rows=args.fto_max_rows, check_patents=args.fto_check_patents)

    rows, warnings = build_rfq(selection, pool, args.prefix,
                               quantity_mg=args.quantity_mg, priority=args.priority,
                               fto_gate=fto_gate, fto_drop=not args.fto_flag_only,
                               fto_records=fto_records)
    for w in warnings:
        print(f"[warn] {w}", file=sys.stderr)

    if args.fto_gate:
        report_path = args.fto_report or (
            Path(str(args.out) + ".fto.json") if args.out else ROOT / "results/select_to_rfq.fto.json")
        occ = sum(1 for r in fto_records if r.get("occupied") is True)
        unk = sum(1 for r in fto_records if r.get("occupied") is None)
        report = {"summary": {"n_screened": len(fto_records), "occupied": occ,
                              "unknown_fail_open": unk, "cutoff": args.fto_cutoff,
                              "patents_checked": bool(args.fto_check_patents),
                              "dropped": not args.fto_flag_only},
                  "verdicts": fto_records}
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, indent=2))
        print(f"[fto] screened {len(fto_records)}, occupied {occ}, fail-open {unk} "
              f"-> {report_path}", file=sys.stderr)
    if not rows:
        print("[error] no shippable rows (every pick lacked a sequence)", file=sys.stderr)
        return 2
    if args.out:
        write_csv(rows, args.out)
        print(f"wrote {len(rows)} CRO items -> {args.out}", file=sys.stderr)
    else:
        w = csv.DictWriter(sys.stdout, fieldnames=CRO_COLUMNS)
        w.writeheader()
        w.writerows(rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
