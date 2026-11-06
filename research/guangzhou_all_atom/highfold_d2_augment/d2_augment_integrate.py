#!/usr/bin/env python3
"""
d2_augment_integrate.py — D2 (2ii) OUTPUT INTEGRATION: fold the confidence-gated PREDICTED cyclic complexes into
the EXACT PepGLAD format the D2 mine emits, so they drop straight into m2c_process_complexes.py alongside the 235
experimental complexes. CPU only. NO GPU.

THE CONTRACT THIS MUST MATCH (verified against mine_bound_cyclic_complexes.py + m2c_process_complexes.py):
  * <out-dir>/index.txt              lines: "<pdb_id>\t<rec_chain>\t<pep_chain>\t0"
                                     (m2c reads col0=pdb_id, col1=rec_chain, col2=pep_chain; col3 unused)
  * <out-dir>/pdbs/<pdb_id>.pdb      a 2-chain PDB containing EXACTLY [rec_chain, pep_chain], re-emitted through
                                     PepGLAD's OWN list_blocks_to_pdb so process.py re-parses it identically.
  * <out-dir>/bound_cyclic_manifest.jsonl   one row/complex with the SAME keys the mine writes + the predicted-tag:
        pdb_id, pep_chain, rec_chains, peptide_seq, seq_len, cyclization_type, resolution(=null),
        method(="PREDICTED_<tool>"), receptor_name, n_interface_residues, provenance="<tool>_predicted",
        conformer_provenance="<tool>_predicted", status="ok", train_only=True, gate={iptm,plddt}, affinity_nM
  * <out-dir>/summary.json

CHAIN CONVENTION: our Boltz YAML wrote receptor=A, peptide=B. So rec_chain="A", pep_chain="B" for every predicted
complex. We assign a synthetic pdb_id "PRED<zero-padded index>_B" (col0), guaranteed not to collide with real 4-char
PDB ids (so a mixed experimental+predicted index has no id clash), and stage pdbs/PRED####_B.pdb.

TRAIN-ONLY ENFORCEMENT (hard):
  * Every manifest row carries train_only=True and conformer_provenance="<tool>_predicted".
  * We ALSO write <out-dir>/TRAIN_ONLY_DO_NOT_EVAL and a train_only_ids.txt so the m2c split step can exclude
    these ids from val/test by construction. m2c's seq-cluster split holds out experimental crystal/NMR/cryoEM
    only; predicted ids being train-only is the belt-and-suspenders guard.

MERGE MODES:
  * --merge-into <experimental_d2_dir>  : produce a COMBINED dir (experimental + predicted) as bound_cyclic_v2 for
    a single m2c run. The combined index/manifest keep provenance tags so the split can route predicted->train.
  * default (no --merge-into)           : emit a standalone predicted-only dir.

USAGE
  python3 d2_augment_integrate.py \
      --pred-dir ./d2_augment_pred_v1 \        # has predicted/<job_id>/complex.pdb + predictions_manifest.jsonl
      --out-dir ./data/bound_cyclic_pred_v1 \
      [--merge-into ./data/bound_cyclic/v1 --merged-out ./data/bound_cyclic/v2]
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent   # research/guangzhou_all_atom
RUNTIME = ROOT / "runtime" / "PepGLAD"
for p in (str(RUNTIME), str(ROOT)):
    if p not in sys.path:
        sys.path.insert(0, p)

INTERFACE_MAX = 6.0  # matches the mine + PepGLAD blocks_interface 6.0 A


def _reemit_two_chain(src_pdb: Path, dst_pdb: Path, rec_chain: str, pep_chain: str):
    """Re-parse the Boltz complex.pdb with PepGLAD's own converter and re-emit EXACTLY [rec_chain, pep_chain] so
    process.py downstream re-parses it identically. Returns (ok, reason, n_rec, n_pep)."""
    from data.converter.pdb_to_list_blocks import pdb_to_list_blocks
    from data.converter.list_blocks_to_pdb import list_blocks_to_pdb
    try:
        blocks_by_chain = pdb_to_list_blocks(str(src_pdb), dict_form=True)
    except Exception as e:  # noqa: BLE001
        return False, f"parse_failed:{type(e).__name__}", 0, 0
    if rec_chain not in blocks_by_chain:
        return False, f"rec_chain_absent:{rec_chain}(have={list(blocks_by_chain)[:6]})", 0, 0
    if pep_chain not in blocks_by_chain:
        return False, f"pep_chain_absent:{pep_chain}(have={list(blocks_by_chain)[:6]})", 0, 0
    rec_blocks = blocks_by_chain[rec_chain]
    pep_blocks = blocks_by_chain[pep_chain]
    if len(pep_blocks) < 3:
        return False, f"peptide_too_short:{len(pep_blocks)}", 0, 0
    if len(rec_blocks) < 5:
        return False, f"receptor_too_short:{len(rec_blocks)}", 0, 0
    try:
        list_blocks_to_pdb([rec_blocks, pep_blocks], [rec_chain, pep_chain], str(dst_pdb))
    except Exception as e:  # noqa: BLE001
        return False, f"emit_failed:{type(e).__name__}", 0, 0
    return True, "ok", len(rec_blocks), len(pep_blocks)


def _count_interface(src_pdb: Path, rec_chain: str, pep_chain: str, cutoff: float = INTERFACE_MAX) -> int:
    """Receptor residues with any heavy atom within cutoff of any peptide heavy atom. Coordinate-based, same
    definition as the mine (so predicted rows carry a comparable n_interface_residues)."""
    import math
    rec_at, pep_at = [], []
    for ln in src_pdb.read_text().splitlines():
        if not ln.startswith(("ATOM", "HETATM")):
            continue
        ch = ln[21]
        elem = ln[76:78].strip() or ln[12:16].strip()[:1]
        if elem == "H":
            continue
        try:
            x, y, z = float(ln[30:38]), float(ln[38:46]), float(ln[46:54])
        except ValueError:
            continue
        resid = ln[22:27]
        if ch == rec_chain:
            rec_at.append((resid, x, y, z))
        elif ch == pep_chain:
            pep_at.append((x, y, z))
    if not rec_at or not pep_at:
        return 0
    cut2 = cutoff * cutoff
    contacted = set()
    for (rid, rx, ry, rz) in rec_at:
        for (px, py, pz) in pep_at:
            if (rx - px) ** 2 + (ry - py) ** 2 + (rz - pz) ** 2 <= cut2:
                contacted.add(rid)
                break
    return len(contacted)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pred-dir", required=True, help="d2_augment_predict output (predicted/ + predictions_manifest.jsonl)")
    ap.add_argument("--out-dir", required=True, help="predicted-only PepGLAD-format dir to write")
    ap.add_argument("--merge-into", default=None, help="optional experimental D2 dir to combine with (bound_cyclic/v1)")
    ap.add_argument("--merged-out", default=None, help="combined output dir (required if --merge-into set)")
    ap.add_argument("--rec-chain", default="A")
    ap.add_argument("--pep-chain", default="B")
    args = ap.parse_args(argv)

    pred_dir = Path(args.pred_dir)
    out_dir = Path(args.out_dir)
    pdbs_dir = out_dir / "pdbs"
    pdbs_dir.mkdir(parents=True, exist_ok=True)

    man_path = pred_dir / "predictions_manifest.jsonl"
    if not man_path.is_file():
        print(f"FATAL: {man_path} not found", file=sys.stderr)
        return 2
    kept = []
    for ln in man_path.read_text().splitlines():
        if not ln.strip():
            continue
        r = json.loads(ln)
        if r.get("kept") and r.get("status") == "kept":
            kept.append(r)
    print(f"[integrate] {len(kept)} gate-passing predicted complexes to fold in", flush=True)

    index_rows, manifest_rows, dropped = [], [], []
    for i, r in enumerate(kept):
        jid = r["job_id"]
        src = pred_dir / "predicted" / jid / "complex.pdb"
        if not src.is_file():
            dropped.append({"job_id": jid, "reason": "complex_pdb_missing"})
            continue
        pdb_id = f"PRED{i:05d}_{args.pep_chain}"   # col0 in index.txt; PepGLAD keys pdbs/<pdb_id>.pdb
        dst = pdbs_dir / f"{pdb_id}.pdb"
        ok, reason, n_rec, n_pep = _reemit_two_chain(src, dst, args.rec_chain, args.pep_chain)
        if not ok:
            dropped.append({"job_id": jid, "reason": reason})
            continue
        n_if = _count_interface(dst, args.rec_chain, args.pep_chain)
        if n_if == 0:
            dropped.append({"job_id": jid, "reason": "no_interface_after_reemit"})
            try:
                dst.unlink()
            except OSError:
                pass
            continue

        conf = r.get("confidence") or {}
        gate = r.get("gate") or {}
        index_rows.append((pdb_id, args.rec_chain, args.pep_chain))
        manifest_rows.append({
            "pdb_id": pdb_id.split("_")[0],   # mine stores pdb_id WITHOUT the chain suffix; m2c re-appends _pep
            "pep_chain": args.pep_chain,
            "rec_chains": [args.rec_chain],
            "peptide_seq": r.get("peptide_seq", ""),
            "seq_len": len(r.get("peptide_seq", "")),
            "cyclization_type": r.get("cyclic_type", "backbone_macrocycle"),
            "cyclization_evidence": f"predicted cyclic:true ({r.get('tool')})",
            "resolution": None,
            "method": f"PREDICTED_{r.get('tool')}",
            "receptor_name": r.get("target_name"),
            "uniprot": r.get("uniprot"),
            "affinity_nM": r.get("affinity_nM"),
            "n_interface_residues": n_if,
            "provenance": r["conformer_provenance"],          # "<tool>_predicted"
            "conformer_provenance": r["conformer_provenance"],
            "confidence_iptm": conf.get("iptm"),
            "confidence_plddt": conf.get("complex_plddt"),
            "gate_pass": gate.get("pass", True),
            "train_only": True,
            "status": "ok",
        })

    # ------- write the PepGLAD-format outputs (index keyed pdb_id_pepchain, exactly like the mine) -------
    def _write_pepglad(target_dir: Path, idx_rows, man_rows, note):
        target_dir.mkdir(parents=True, exist_ok=True)
        with open(target_dir / "index.txt", "w") as f:
            for (pid, rec, pep) in idx_rows:
                # index col0 must be the pdbs/<file> stem. Our stem IS "<pdb_id>_<pep_chain>", so write pid as-is.
                f.write(f"{pid}\t{rec}\t{pep}\t0\n")
        with open(target_dir / "bound_cyclic_manifest.jsonl", "w") as f:
            for m in man_rows:
                f.write(json.dumps(m) + "\n")
        summary = {
            "n_predicted_complexes": len(idx_rows),
            "provenance": "predicted (train-only)",
            "train_only": True,
            "note": note,
        }
        (target_dir / "summary.json").write_text(json.dumps(summary, indent=2))

    _write_pepglad(out_dir, index_rows, manifest_rows,
                   "PREDICTED cyclic complexes (Boltz cyclic:true). PepGLAD format: pdbs/<pdb_id_pepchain>.pdb + "
                   "index.txt. conformer_provenance=<tool>_predicted, train_only=True. Feed to "
                   "m2c_process_complexes.py; the split MUST keep these in TRAIN only (experimental=eval anchor).")
    (out_dir / "TRAIN_ONLY_DO_NOT_EVAL").write_text(
        "All complexes in this dir are model-PREDICTED and are TRAIN-ONLY. Never place in a val/test split.\n")
    (out_dir / "train_only_ids.txt").write_text("\n".join(f"{pid}_{pep}" for (pid, rec, pep) in
                                                 [(p, r, q) for (p, r, q) in index_rows]) + "\n")

    result = {
        "experiment": "D2 (2ii) integrate predicted complexes -> PepGLAD format",
        "pred_dir": os.path.abspath(args.pred_dir),
        "out_dir": os.path.abspath(str(out_dir)),
        "n_gate_passing_input": len(kept),
        "n_written": len(index_rows),
        "n_dropped_reemit": len(dropped),
        "dropped_examples": dropped[:15],
        "chain_convention": {"rec_chain": args.rec_chain, "pep_chain": args.pep_chain},
        "train_only": True,
    }

    # ------- optional merge with experimental D2 (bound_cyclic_v2) -------
    if args.merge_into:
        if not args.merged_out:
            print("FATAL: --merge-into requires --merged-out", file=sys.stderr)
            return 2
        exp_dir = Path(args.merge_into)
        merged = Path(args.merged_out)
        (merged / "pdbs").mkdir(parents=True, exist_ok=True)
        # copy experimental index + manifest, tag them provenance-preserving, then append predicted.
        exp_idx = (exp_dir / "index.txt").read_text().splitlines() if (exp_dir / "index.txt").is_file() else []
        exp_man = []
        emp = exp_dir / "bound_cyclic_manifest.jsonl"
        if emp.is_file():
            exp_man = [json.loads(l) for l in emp.read_text().splitlines() if l.strip()]
        # HOW m2c CONSUMES THIS (verified against m2c_process_complexes.py:198-215 + 362-365):
        #   * read_d2 reads merged/index.txt (col0=pdb_id e.g. "PRED00001_B") + merged/bound_cyclic_manifest.jsonl
        #     (keyed by (pdb4.upper(), pep_chain) = ("PRED00001","B")). Our manifest rows use pdb_id="PRED00001"
        #     (no suffix) + pep_chain="B" -> matches read_d2's key EXACTLY.
        #   * m2c's stage loop SKIPS the RCSB fetch when out_dir/pdbs/<pdb_id>.pdb already exists (line 362-365,
        #     "resume-aware"). So if the m2c run's out_dir/pdbs/ is PRE-SEEDED with our PRED#####_B.pdb files, m2c
        #     never tries (and never fails) to fetch a 4-char PDB for them — it uses our pre-staged 2-chain file.
        #   * Experimental rows (real 4-char ids) still get fetched from RCSB by stage_one as usual.
        #   => merge WORKS with ZERO m2c code change, IF the operator points m2c --out-dir at a dir whose pdbs/ is
        #      seeded with merged/pdbs/*.pdb. run_d2_augment.sh does exactly this seeding step.
        with open(merged / "index.txt", "w") as f:
            for ln in exp_idx:
                f.write(ln.rstrip("\n") + "\n")
            for (pid, rec, pep) in index_rows:
                f.write(f"{pid}\t{rec}\t{pep}\t0\n")
        with open(merged / "bound_cyclic_manifest.jsonl", "w") as f:
            for m in exp_man:
                m.setdefault("train_only", False)  # experimental -> eligible for eval
                f.write(json.dumps(m) + "\n")
            for m in manifest_rows:
                f.write(json.dumps(m) + "\n")
        # copy our predicted pdbs into merged/pdbs
        for (pid, rec, pep) in index_rows:
            srcp = pdbs_dir / f"{pid}.pdb"
            if srcp.is_file():
                (merged / "pdbs" / f"{pid}.pdb").write_text(srcp.read_text())
        result["merged_out"] = os.path.abspath(str(merged))
        result["merge_usage"] = (
            "Run m2c on the merged dir; SEED its --out-dir/pdbs/ with merged/pdbs/*.pdb FIRST so m2c's resume-skip "
            "(m2c line 362-365) uses our pre-staged predicted complexes instead of trying to RCSB-fetch PRED##### "
            "ids. Experimental 4-char ids are fetched normally. Zero m2c code change. Example: "
            "cp merged/pdbs/*.pdb <m2c_out>/pdbs/ && python3 m2c_process_complexes.py --d2-dir merged --out-dir <m2c_out>. "
            "NOTE the split: m2c's seq-cluster split does NOT read train_only, so pass the predicted ids to its "
            "test-exclusion — OR run m2c on experimental-only for the eval anchor and merge predicted into TRAIN "
            "index post-hoc (train_only_ids.txt lists them). Predicted must never land in valid/test.")

    (out_dir / "integrate_result.json").write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
