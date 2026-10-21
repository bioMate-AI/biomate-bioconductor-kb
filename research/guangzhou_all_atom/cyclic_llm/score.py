"""Consolidated verifier / reward. One score() that merges all objectives into a single record:
- CHEAP tier (inline, deterministic, zero-cost): rule pass, FTO claim verdict + DoE, developability proxy.
- EXPENSIVE tier (hooks): binding dG (MM-GBSA), selectivity gap (counter-target), groove occupancy, geometry
  triage - supplied from the GPU pipeline results when available (control-anchored / A2), else 'pending'.
This is the reward the design->score->redesign loop optimizes and the own-LLM would later train against (RLVR)."""
import json, os
from acceptance_gate import raw_tokens, _strip_mods, avb6_gate
from fto_score import fto_score

FP = {"W": 2.25, "F": 1.79, "I": 1.80, "L": 1.70, "M": 1.23, "V": 1.22, "C": 1.54, "Y": 0.96, "P": 0.72,
      "A": 0.31, "T": 0.26, "H": 0.13, "G": 0.0, "S": -0.04, "Q": -0.22, "N": -0.60, "E": -0.64, "D": -0.77,
      "K": -0.99, "R": -1.01, "2Nal": 2.8, "Phe4F": 1.9, "Phe4Cl": 2.0}
AROM = {"F", "Y", "W", "H", "2Nal", "Phe4F", "Phe4Cl"}

def developability(helm):
    cores = [_strip_mods(t) for t in raw_tokens(helm)]
    s = "".join(c if len(c) == 1 else "X" for c in cores)
    w = s + s[:1]
    liab = []
    for i in range(len(s)):
        if w[i:i+2] in ("NG", "NS"): liab.append("deamidation")
        if w[i:i+2] in ("DG", "DS"): liab.append("isomerization")
    if cores.count("M"): liab.append("Met-ox")
    if cores.count("C") == 1: liab.append("free-Cys")
    if cores.count("W") >= 2: liab.append("multi-Trp-ox")
    n2 = sum(1 for c in cores if c == "2Nal")
    meanH = round(sum(FP.get(c, 0.0) for c in cores) / max(len(cores), 1), 2)
    net = sum(1 for c in cores if c in ("R", "K")) - sum(1 for c in cores if c in ("D", "E"))
    greasy = (n2 >= 2) or (meanH > 0.9)
    return {"meanH": meanH, "n2Nal": n2, "net_charge": net, "liabilities": liab, "greasy": greasy,
            "pass": (not liab) and (not greasy) and (-2 <= net <= 2)}

def score(helm, target="avb6", binding_dG=None, selectivity_gap=None, groove=None, geometry=None,
          ddg_fep=None, tier="cheap"):
    """Merge every objective into one record + a hard-gate verdict + a rank key.
    tier='cheap' (default): deterministic tier only; expensive hooks stay 'pending' unless passed explicitly.
    tier='full': auto-dispatch the expensive tier from the GPU pipeline RESULTS (physics_dispatch), control-
    anchored (A2) — only admissible values are filled; explicit kwargs still override."""
    rec = {"helm": helm, "target": target}
    # cheap deterministic tier
    rec["rule_pass"] = avb6_gate(helm)["PASS_H1_H5"] if target == "avb6" else None
    f = fto_score(helm, target, structure=(tier == "full"))   # full tier adds the real structure/patent axis
    rec["fto"] = {"verdict": f["claim"]["verdict"], "doe": f["claim"]["doe"],
                  "patent_id": f["nearest_patented_identity"]}
    if "novelty" in f:
        rec["fto"]["novelty"] = f["novelty"]
    rec["developability"] = developability(helm)
    # expensive tier: auto-dispatch admissible physics when tier='full' (explicit kwargs take precedence)
    if tier == "full":
        from physics_dispatch import physics_for
        p = physics_for(helm, target)
        for fld, var in (("binding_dG", binding_dG), ("selectivity_gap", selectivity_gap),
                         ("groove", groove), ("geometry", geometry), ("ddg_fep", ddg_fep)):
            if var is None and p["admissible"].get(fld) and p[fld] is not None:
                if fld == "binding_dG": binding_dG = p[fld]
                elif fld == "selectivity_gap": selectivity_gap = p[fld]
                elif fld == "groove": groove = p[fld]
                elif fld == "geometry": geometry = p[fld]
                elif fld == "ddg_fep": ddg_fep = p[fld]
        rec["physics"] = {"design_id": p["design_id"], "provenance": p["provenance"], "reasons": p["reasons"]}
    # ddg_fep = relative FEP ΔΔG (trustworthy arbiter; negative = tighter than the reference edge). This is the
    # physics the RLVR reward PREFERS over MM-GBSA binding_dG (a weak feasibility proxy). Pending until the gated
    # FEP control edge runs + validates (fep_batch.py); for αvβ6 it is the ONLY admissible binding signal (the
    # metal-free MM-GBSA is voided — see physics_dispatch).
    rec["ddg_fep"] = ddg_fep if ddg_fep is not None else "pending"
    rec["binding_dG"] = binding_dG if binding_dG is not None else "pending"
    rec["selectivity_gap"] = selectivity_gap if selectivity_gap is not None else "pending"
    rec["groove_occupancy"] = groove if groove is not None else "pending"
    rec["geometry"] = geometry if geometry is not None else "pending"
    # hard gates (cheap): rule + not-infringing + developability
    infring = rec["fto"]["verdict"].startswith("INSIDE")
    rec["hard_gate_pass"] = bool(rec["rule_pass"]) and (not infring) and rec["developability"]["pass"]
    rec["hard_gate_reasons"] = {"rule": rec["rule_pass"], "fto_not_infringing": not infring,
                                "developability": rec["developability"]["pass"]}
    # rank key: gate first, then FTO DoE (LOW<MED<HIGH), then binding (if present), then low patent-id
    doe_rank = {"LOW": 0, "MED": 1, "HIGH": 2, "infringes": 3}
    # prefer the trustworthy FEP ΔΔG for ranking when present; else fall back to MM-GBSA binding_dG
    b = (ddg_fep if isinstance(ddg_fep, (int, float))
         else (binding_dG if isinstance(binding_dG, (int, float)) else 0.0))
    rec["rank_key"] = (0 if rec["hard_gate_pass"] else 1, doe_rank.get(rec["fto"]["doe"], 1), b,
                       rec["fto"]["patent_id"])
    return rec

if __name__ == "__main__":
    tests = ["cyclo(F-R-G-D-L-A-F-[dP]-[NMeK])",          # infringing
             "cyclo(F-R-G-D-L-G-[2Nal]-[dP]-[NMeK])",     # MED DoE, clean dev
             "cyclo(F-R-G-D-L-A-[2Nal]-[dP]-[2Nal])",     # greasy (2x2Nal)
             ]
    for h in tests:
        r = score(h)
        print(f"{h}")
        print(f"   gate={r['hard_gate_pass']} reasons={r['hard_gate_reasons']} | FTO {r['fto']['verdict']}({r['fto']['doe']}) | dev {r['developability']['pass']} meanH={r['developability']['meanH']} | binding={r['binding_dG']}")
