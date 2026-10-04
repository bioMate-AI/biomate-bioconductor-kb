#!/usr/bin/env python3
"""dpo_make_pairs_from_mmap.py — emit a REAL VERIFY_SELECT PairSet from a featurized CoDesignDataset mmap.

This is the data-side of the first real close-back demonstration. VERIFY_SELECT (dpo_pairs.py stream 1)
preferences the loop's SELECTED (high binding-confidence) designs over REJECTED (low binding-confidence) ones.
Here the "pool" is a set of REAL bound cyclic-peptide complexes already featurized into the PepGLAD
CoDesignDataset mmap (so the pairs' chosen_id/rejected_id resolve to encodable latents for the DPO trainer).

BINDING-CONFIDENCE PROXY (honest + geometric, computed from the featurized complex itself):
  interface-contact density = (# peptide CA atoms within `cutoff` A of any receptor CA) / (# peptide residues).
  A denser, more-buried peptide-receptor interface is the ΔG/iptm-style binding-confidence signal VERIFY_SELECT
  ranks on. This is a WEAK, geometry-only proxy (all pool members are real co-crystals, so all bind) — the
  point is a REAL relative preference over REAL featurized designs, NOT a native-structure (DockQ) signal.
  As the coordinator notes: binding-confidence need not align with DockQ-to-native.

Pairs: rank by score; top-T = chosen, bottom-T = rejected; pair chosen[i] with rejected[i]. Emitted through
dpo_pairs.pairs_from_exemplars(stream=VERIFY_SELECT) so the trainer sees the standard dpo_pairs schema.

CPU only. No training, no GPU.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import List, Tuple

ROOT = Path(__file__).resolve().parent
RUNTIME = ROOT / "runtime" / "PepGLAD"
for p in (str(RUNTIME), str(ROOT)):
    if p not in sys.path:
        sys.path.insert(0, p)


def score_item(item, cutoff: float = 10.0) -> float:
    """Interface-contact density for one CoDesignDataset item (binding-confidence proxy).

    item: dict with 'X' [N,14,3], 'mask' [N] (peptide=True), 'atom_mask' [N,14]. Uses CA channel (index 1).
    Returns (# peptide CA within `cutoff` of any receptor CA) / (# peptide residues); 0.0 if no valid CA."""
    import torch
    X, mask, am = item["X"], item["mask"], item["atom_mask"]
    ca = 1
    pep_has_ca = mask & am[:, ca]
    rec_has_ca = (~mask) & am[:, ca]
    if pep_has_ca.sum() == 0 or rec_has_ca.sum() == 0:
        return 0.0
    pep = X[pep_has_ca][:, ca]   # [P,3]
    rec = X[rec_has_ca][:, ca]   # [R,3]
    d = torch.cdist(pep, rec)    # [P,R]
    in_contact = (d.min(dim=1).values <= cutoff)   # [P]
    n_pep = int(mask.sum())
    return float(in_contact.sum()) / max(1, n_pep)


def make_pairs(ids: List[str], scores: List[float], n_pairs: int) -> List[Tuple[str, str, float]]:
    """Rank ids by score; pair i-th best (chosen) with i-th worst (rejected). Returns (chosen_id, rejected_id,
    margin) triples. Chosen and rejected sets are disjoint (top-half vs bottom-half), so no self-pairs."""
    order = sorted(range(len(ids)), key=lambda i: scores[i], reverse=True)
    n = len(order)
    max_pairs = n // 2
    k = min(n_pairs, max_pairs)
    out = []
    for i in range(k):
        ci = order[i]            # i-th best
        ri = order[n - 1 - i]    # i-th worst
        margin = scores[ci] - scores[ri]
        out.append((ids[ci], ids[ri], margin))
    return out


def build_pairset(mmap_dir: str, specify_index: str, *, cutoff: float, n_pairs: int, prompt: str = ""):
    import torch  # noqa: F401
    import models  # noqa: F401  registers CoDesignDataset
    from data.codesign import CoDesignDataset
    import dpo_pairs as dp

    ds = CoDesignDataset(mmap_dir=mmap_dir, specify_index=specify_index,
                         backbone_only=False, use_covariance_matrix=False)
    ids, scores = [], []
    for idx in range(len(ds)):
        try:
            item = ds[idx]
        except Exception as e:
            print(f"[pairs] skip idx {idx}: {e}")
            continue
        ids.append(ds.get_summary(idx)[0])
        scores.append(score_item(item, cutoff))
    print(f"[pairs] scored {len(ids)} complexes; score range "
          f"[{min(scores):.3f}, {max(scores):.3f}] (interface-contact density, cutoff={cutoff}A)")

    triples = make_pairs(ids, scores, n_pairs)
    exemplars = [
        dp.ExemplarPair(
            chosen=cid, rejected=rid, chosen_id=cid, rejected_id=rid,
            prompt=prompt, source="verify_select:interface_contact_density",
            chosen_provenance="predicted", rejected_provenance="predicted",
            margin=margin, reason="selected (higher binding-confidence) over rejected (lower)")
        for (cid, rid, margin) in triples
    ]
    pairs = dp.pairs_from_exemplars(exemplars, dp.STREAM_VERIFY_SELECT)
    ps = dp.PairSet(pairs=pairs, notes=[
        f"VERIFY_SELECT demo pairs from {specify_index}; binding-confidence=interface-contact-density@{cutoff}A",
    ])
    return ps


def main():
    ap = argparse.ArgumentParser(description="Emit a VERIFY_SELECT PairSet from a featurized CoDesignDataset mmap.")
    ap.add_argument("--mmap", required=True, help="CoDesignDataset mmap_dir (has data.bin + index.txt)")
    ap.add_argument("--index", required=True, help="specify_index (e.g. train_index.txt — DISJOINT from the eval test set)")
    ap.add_argument("--out", required=True, help="output PairSet jsonl (full-provenance lines)")
    ap.add_argument("--cutoff", type=float, default=10.0, help="CA-CA interface contact cutoff (A)")
    ap.add_argument("--n-pairs", type=int, default=60)
    args = ap.parse_args()

    ps = build_pairset(args.mmap, args.index, cutoff=args.cutoff, n_pairs=args.n_pairs)
    ps.write_jsonl(Path(args.out))
    print(f"[pairs] wrote {len(ps.pairs)} VERIFY_SELECT pairs -> {args.out}")
    print(f"[pairs] stream_counts={ps.stream_counts()}")


if __name__ == "__main__":
    main()
