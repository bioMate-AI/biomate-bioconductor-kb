"""Knowledge-grounded pharmacophore gate + constraint — the fix for 'pure LLM is too naive'.

The 2026-10-12 sequence audit found the generated αvβ6 set is mechanistically DEAD: 0/12 contain the RGD
tripeptide, 0/12 contain aspartate (D). αvβ6 is an RGD-class integrin — every validated ligand engages
via RGD, whose Asp carboxylate coordinates the MIDAS metal; the high-affinity class carries the extended
motif RGDLxxL/I plus a conformational lock (D-Pro + N-methyl). A display-enrichment LLM learned the shallow
Arg-Gly correlate (RGR/RGK/RGN near-misses) but NOT the hard Asp constraint. This module encodes that KNOWN
biology as (a) a HARD gate (reject candidates lacking the required pharmacophore) and (b) a generation
CONSTRAINT contract (what a constrained decoder must enforce) — so the LLM optimizes WITHIN the feasible
space knowledge defines, never emitting a mechanism-dead candidate.

Pharmacophores are literature-grounded (see docs/ refs: Trivehexin c[YRGDLAYp(NMe)K], avebehexin
cyclo(FRGDLAFp(NMe)K); PD-L1 WL12/BMS-986229/dmp10). Extend per target; never silently pass an un-encoded
target as 'ok'.
"""
from __future__ import annotations
import argparse, csv, json, re
from pathlib import Path

# ---- knowledge base: target -> required/preferred pharmacophore + conformational lock -------------------
PHARMACOPHORE = {
    "avb6": {
        "class": "RGD-integrin (MIDAS)",
        "required_motifs": ["RGD"],                       # the Asp carboxylate -> MIDAS metal; non-substitutable
        "required_residues": ["D"],                       # must contain aspartate
        "preferred_regex": r"RGDL[A-Z]{2}[LI]",           # extended RGDLxxL/I high-affinity class
        "conformational_lock": ["D-Pro", "N-methyl"],     # validated αvβ6 peptides lock RGD with dPro + NMe
        "cyclic_scan": True,                              # head-to-tail: scan motif across the wrap
        "refs": "Trivehexin c[YRGDLAYp(NMe)K]; avebehexin cyclo(FRGDLAFp(NMe)K)",
    },
    "pdl1": {
        "class": "discontinuous PPI surface (no SLiM)",
        "required_motifs": [],                            # not a linear motif -> cannot gate by sequence alone
        "required_residues": [],
        "preferred_regex": None,
        "conformational_lock": ["disulfide-directed", "constrained scaffold"],  # WL12/dmp10/BMS class
        "cyclic_scan": True,
        "needs_structure_gate": True,                     # MUST be gated by docking, not sequence
        "refs": "WL12; BMS-986229 class; dmp10 disulfide-directed multicyclic",
    },
}

AA = set("ACDEFGHIKLMNPQRSTVWY")


def _wrap(seq, k):
    """cyclic k-window strings for a head-to-tail macrocycle."""
    return seq + seq[:k-1] if len(seq) >= k else seq


def pharmacophore_gate(seq, target, cyclization="head-to-tail-L", has_dPro=False, has_NMe=False):
    """Hard knowledge gate. Returns a verdict dict; occupied/pass = carries the required pharmacophore."""
    t = PHARMACOPHORE.get(target)
    if t is None:
        return {"target": target, "status": "unknown_target", "pass": None,
                "reason": "no pharmacophore encoded; do NOT pass on faith"}
    seq = seq.upper()
    reasons = []; ok = True
    # required linear motifs (cyclic-aware)
    for m in t["required_motifs"]:
        hay = _wrap(seq, len(m)) if t.get("cyclic_scan") else seq
        if m not in hay:
            ok = False; reasons.append(f"missing required motif {m}")
    # required residues
    for r in t["required_residues"]:
        if r not in seq:
            ok = False; reasons.append(f"missing required residue {r}")
    pref = bool(re.search(t["preferred_regex"], _wrap(seq, 7))) if t.get("preferred_regex") else None
    # conformational lock (knowledge: naked L-cyclic presents the motif in an uncontrolled conformation)
    lock_ok = (has_dPro or has_NMe) if t["conformational_lock"] else None
    if t["conformational_lock"] and not lock_ok:
        reasons.append("no conformational lock (D-Pro/N-methyl) — motif presented uncontrolled")
    verdict = {
        "target": target, "class": t["class"], "sequence": seq,
        "has_required_pharmacophore": ok,
        "has_preferred_extended_motif": pref,
        "has_conformational_lock": lock_ok,
        "needs_structure_gate": t.get("needs_structure_gate", False),
        "pass": (ok and (lock_ok is not False)) if not t.get("needs_structure_gate") else None,
        "reasons": reasons or (["carries required pharmacophore"] if ok else []),
        "note": ("sequence gate decisive for RGD-integrin" if target == "avb6" else
                 "sequence necessary-but-not-sufficient; REQUIRES docking gate" if t.get("needs_structure_gate") else ""),
    }
    return verdict


def generation_constraint(target):
    """The contract a constrained decoder / generator MUST enforce for this target (knowledge -> hard constraint)."""
    t = PHARMACOPHORE.get(target)
    if t is None: return {"target": target, "constraint": "UNKNOWN target — do not generate blind"}
    return {"target": target,
            "must_contain": t["required_motifs"] + [f"residue:{r}" for r in t["required_residues"]],
            "prefer_regex": t["preferred_regex"],
            "require_lock": t["conformational_lock"],
            "enforce": ("constrained decoding: fix an RGD (ideally RGDLxxL/I) span + require >=1 Asp; sample "
                        "flanks/scaffold with the LLM; add a D-Pro + N-methyl lock (needs the HELM/ncAA "
                        "representation)." if target == "avb6" else
                        "sequence cannot gate; generate scaffold-constrained candidates and GATE by docking "
                        "against the target structure + known-binder scaffold similarity."),
            "refs": t["refs"]}


def main():
    ap = argparse.ArgumentParser(description="Knowledge-grounded pharmacophore gate on a candidate panel.")
    ap.add_argument("--panel", required=True); ap.add_argument("--target", required=True, choices=list(PHARMACOPHORE))
    ap.add_argument("--id-col", default="Item"); ap.add_argument("--seq-col", default="Sequence_N_to_C")
    ap.add_argument("--out")
    a = ap.parse_args()
    rows = list(csv.DictReader(open(a.panel)))
    verdicts = []
    for r in rows:
        v = pharmacophore_gate(r.get(a.seq_col, ""), a.target)
        v["id"] = r.get(a.id_col, "")
        verdicts.append(v)
        print(f"  {v['id']:11s} {v['sequence']:17s} pharmacophore={v['has_required_pharmacophore']} "
              f"pass={v['pass']}  {'; '.join(v['reasons'])}")
    npass = sum(1 for v in verdicts if v["has_required_pharmacophore"])
    out = {"target": a.target, "constraint": generation_constraint(a.target),
           "n": len(verdicts), "n_with_pharmacophore": npass, "n_fail": len(verdicts) - npass,
           "verdicts": verdicts}
    print(f"\nKNOWLEDGE GATE [{a.target}]: {npass}/{len(verdicts)} carry the required pharmacophore "
          f"({len(verdicts)-npass} mechanism-dead, would be rejected before synthesis)")
    if a.out:
        Path(a.out).parent.mkdir(parents=True, exist_ok=True); json.dump(out, open(a.out, "w"), indent=2)


if __name__ == "__main__":
    main()
