"""Pharma-Chemist Experience KB — first slice.

ONE provenance-tiered knowledge store that drives BOTH tool PARAMETERS and EVALUATION CRITERIA, so the
rich experience-based constraints a medicinal chemist applies (metal coordination, pharmacophore, selectivity
SAR, renal/CMC liabilities, FTO) stop being re-encoded by hand per target and instead resolve from one place.

Design: docs/20261021_PHARMA_CHEMIST_EXPERIENCE_KB_DESIGN.md (commit e1dec289c).

This module WRAPS the already-existing, scattered assets as provenance-wrapped KB entries — it does NOT copy
or re-author their content (no new chemistry is invented here):
  - target_kb/<t>.json + target_spec.load_spec / scorer_config.config_for  -> metal/cofactor, pose, receptor,
    counter-targets (TOOL PARAMS) and the metal-free-MIDAS => void rule (EVAL).
  - pharmacophore_knowledge.PHARMACOPHORE / generation_constraint          -> pharmacophore gate (EVAL) +
    generation constraint (TOOL PARAM).
  - knowledge_liability_flags.flag_candidate                               -> β6-selectivity, renal-charge,
    conformational-lock, CMC universals (EVAL; the live checker stays flag_candidate()).
  - fto_score.in_claim + the KB `fto` genus                                -> FTO genus (EVAL, advisory).
  - fep/forcefield/cada_mn.itp (Duarte-2014, verbatim)                     -> the Mn metal-model FF-param
    exemplar (TOOL PARAM, tier T1). NOTE: the .itp itself is still pending its grompp/NVT validation.

`resolve(target)` fires the matching entries and returns the merged {tool_params, eval_criteria} + provenance.
Deterministic, schema-validated; an LLM-RAG fallback for novel targets is a documented TODO (not in this slice).
"""
from __future__ import annotations
import os, sys, json
from dataclasses import dataclass, field, asdict
from typing import Any, Optional

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
PARENT = os.path.dirname(HERE)                       # research/guangzhou_all_atom
CADA_ITP = os.path.join(PARENT, "fep", "forcefield", "cada_mn.itp")

# ---- evidence tiers (same ladder as the design + the Grounded Standards Assistant) ----
TIERS = {
    "T1": "established literature / verbatim-sourced parameters",
    "T2": "program-validated (real run evidence)",
    "T3": "mechanistic reasoning / curated heuristic",
    "T4": "induced from data (rule_induction)",
}


@dataclass
class KBEntry:
    id: str
    kind: str                       # metal | pharmacophore | sar | cmc | fto | eval_rule | pose
    statement: str
    scope: dict = field(default_factory=dict)        # {modality, target_class, applies_when:[targets] or "*"}
    provenance: dict = field(default_factory=dict)   # {source_type, ref, evidence_tier}
    effects: dict = field(default_factory=dict)      # {tool_params:{...}, eval_criteria:[{criterion,mode,checker}]}
    version: str = "1.0"
    status: str = "active"

    def validate(self):
        assert self.id and self.kind and self.statement, f"entry {self.id}: id/kind/statement required"
        t = self.provenance.get("evidence_tier")
        assert t in TIERS, f"entry {self.id}: evidence_tier must be one of {list(TIERS)}, got {t!r}"
        # MANDATORY verified flag — citation-integrity: a source we could not check is never silently authoritative.
        v = self.provenance.get("verified")
        assert v in (True, False, "unverifiable", "n/a"), \
            f"entry {self.id}: provenance.verified required (True|False|'unverifiable'|'n/a'), got {v!r}"
        eff = self.effects or {}
        assert set(eff) <= {"tool_params", "eval_criteria"}, f"entry {self.id}: bad effects keys {set(eff)}"
        for c in eff.get("eval_criteria", []):
            assert c.get("mode") in ("hard", "advisory"), f"entry {self.id}: eval mode must be hard|advisory"
        return self


def _applies(entry: KBEntry, target: str, target_class: Optional[str]) -> bool:
    aw = entry.scope.get("applies_when", "*")
    if aw == "*":
        return True
    if isinstance(aw, (list, tuple)):
        return target in aw or (target_class is not None and target_class in aw)
    return aw == target or aw == target_class


# =========================== ADAPTERS (wrap existing assets) ===========================

def _target_class(target: str, spec: dict | None) -> Optional[str]:
    if spec is None:
        return None
    # RGD-integrin / MIDAS metal class vs PPI-groove — derived from the existing mechanism tag
    if spec.get("cofactors"):
        return "integrin-MIDAS"
    return "ppi-groove"


def _metal_entries(target, spec, cfg) -> list[KBEntry]:
    out = []
    cof = (spec or {}).get("cofactors") or []
    if not cof:
        return out
    c0 = cof[0]
    ccd, n, site = c0.get("ccd"), c0.get("n"), c0.get("site")
    ff = os.path.relpath(CADA_ITP, PARENT) if ccd == "MN" and os.path.exists(CADA_ITP) else None
    tp = {"metal_model": (f"CaDA-{ccd}" if ccd == "MN" else ccd),
          "cofactors": cof, "metal_ccd": ccd, "metal_n": n, "metal_site": site}
    if ff:
        tp["metal_ff_file"] = ff
    out.append(KBEntry(
        id=f"{target}:metal",
        kind="metal",
        statement=(f"{(spec or {}).get('name', target)} engages via a {ccd} cofactor at {site}; the physics "
                   f"tier must RETAIN and PARAMETERIZE the metal (cofold + MM-GBSA). "
                   + ("Mn uses the CaDA cationic-dummy octahedral model." if ccd == "MN" else "")),
        scope={"modality": (spec or {}).get("modality"), "target_class": _target_class(target, spec),
               "applies_when": [target]},
        provenance={"source_type": "forcefield+KB",
                    "ref": (f"cada_mn.itp (Duarte et al., J. Phys. Chem. B 2014, 118(16):4351-4362, verbatim); "
                            f"target_kb/{target}.json cofactors"
                            if ccd == "MN" else f"target_kb/{target}.json cofactors"),
                    "evidence_tier": "T1" if ccd == "MN" else "T3",
                    "verified": (True if ccd == "MN" else "n/a"),
                    "verification_note": (
                        "VERIFIED 2026-10-21: Duarte et al. JPCB 2014 confirmed real — refines octahedral Mn2+ "
                        "(+Zn/Mg/Ca) cationic-dummy params, reproduces M2+-O distances + solvation FE, LJ-transferable. "
                        "CAVEATS: (a) cada_mn.itp still pending grompp/NVT validation; (b) physiologic MIDAS metal is "
                        "Mg2+ — Mn2+ is the integrin-activating cation used experimentally (CaDA parameterizes both)."
                        if ccd == "MN" else "cofactor list is a program config, not a literature claim")},
        effects={"tool_params": tp},
    ).validate())
    return out


def _pose_entry(target, spec, cfg) -> list[KBEntry]:
    if spec is None:
        return []
    return [KBEntry(
        id=f"{target}:pose",
        kind="pose",
        statement=f"Epitope '{spec.get('epitope')}' (motif {spec.get('motif')}) -> pose by {spec.get('pose_method')}; "
                  f"{spec.get('pose_why','')}",
        scope={"applies_when": [target]},
        provenance={"source_type": "KB-engine", "ref": "target_spec.load_spec (POSE_BY_EPITOPE)",
                    "evidence_tier": "T3", "verified": "n/a",
                    "verification_note": "program method-config heuristic (which pose method per epitope), not a "
                                         "literature claim; receptor/counter-targets come from the target KB."},
        effects={"tool_params": {"pose_method": spec.get("pose_method"),
                                 "dock_acceptable_prepose": spec.get("dock_prepose_ok"),
                                 "receptor_asset": (spec.get("receptor") or {}).get("structure"),
                                 "counter_targets": spec.get("counter_targets", [])}},
    ).validate()]


def _pharmacophore_entries(target) -> list[KBEntry]:
    try:
        import pharmacophore_knowledge as pk
    except Exception:                                        # pragma: no cover
        return []
    t = pk.PHARMACOPHORE.get(target)
    if t is None:
        return []
    gc = pk.generation_constraint(target)
    needs_struct = t.get("needs_structure_gate", False)
    return [KBEntry(
        id=f"{target}:pharmacophore",
        kind="pharmacophore",
        statement=(f"{t['class']}: required motif(s) {t['required_motifs'] or '(none — structure-gated)'}, "
                   f"required residue(s) {t['required_residues']}, lock {t['conformational_lock']}. "
                   + ("Sequence gate decisive." if target == "avb6" else "Sequence necessary-not-sufficient; docking-gated.")),
        scope={"target_class": "integrin-MIDAS" if target == "avb6" else "ppi-groove", "applies_when": [target]},
        provenance={"source_type": "literature", "ref": t.get("refs", "pharmacophore_knowledge.py"),
                    "evidence_tier": "T1" if target == "avb6" else "T3",
                    "verified": (True if target == "avb6" else "unverifiable"),
                    "verification_note": (
                        "VERIFIED 2026-10-21: RGD-Asp carboxylate -> MIDAS metal is established integrin biology; "
                        "Trivehexin c[YRGDLAYp(NMe)K] + avebehexin c(FRGDLAFp(NMe)K) are real published alphavbeta6 "
                        "ligands (EJNMM 2021, s00259-021-05559-x) carrying the RGD + D-Pro/N-methyl lock."
                        if target == "avb6" else
                        "refs name known PD-L1 macrocycle classes (WL12, BMS-986229, dmp10) but were NOT "
                        "independently verified this session; entry is structure-gated/advisory, not authoritative.")},
        effects={
            "tool_params": {"generation_constraint": gc},   # the decoder contract
            "eval_criteria": [{"criterion": f"pharmacophore_gate[{target}]",
                               "mode": "advisory" if needs_struct else "hard",
                               "checker": "pharmacophore_knowledge.pharmacophore_gate",
                               "note": ("decisive at sequence level" if not needs_struct
                                        else "sequence necessary; decisive gate is docking")}],
        },
    ).validate()]


def _sar_cmc_entries(target) -> list[KBEntry]:
    """Declarative SAR/CMC entries; the LIVE checker is knowledge_liability_flags.flag_candidate (not re-authored)."""
    entries = []
    # Universal CMC (applies to all cyclic-peptide targets)
    entries.append(KBEntry(
        id="cmc:universal",
        kind="cmc",
        statement="Universal CMC/chemical liabilities (deamidation NG/NS, Asp-isomerisation DG/DS, Met/Trp "
                  "oxidation, odd free-Cys) flagged sequence-side before any docking spend.",
        scope={"modality": "cyclic_peptide", "applies_when": "*"},
        provenance={"source_type": "textbook-medchem",
                    "ref": "knowledge_liability_flags.DIPEPTIDE_LIABILITIES; standard biopharm CMC refs "
                           "(Asn-deamidation NG/NS, Asp-isomerisation DG/DS via succinimide, Met/Trp oxidation)",
                    "evidence_tier": "T1", "verified": True,
                    "verification_note": "VERIFIED 2026-10-21: these are standard, well-documented biopharm "
                                         "liabilities (e.g. PMID 30526254 deamidation/isomerisation analysis of 131 "
                                         "clinical antibodies; NG most labile; Asp-X succinimide isomerisation)."},
        effects={"eval_criteria": [{"criterion": "cmc_liabilities", "mode": "advisory",
                                    "checker": "knowledge_liability_flags.flag_candidate"}]},
    ).validate())
    if target == "avb6":
        entries += [
            KBEntry(id="avb6:sar-b6-selectivity", kind="sar",
                    statement="Bare RGD engages all RGD integrins (αvβ3/αvβ5/αvβ8/α5β1); β6-selectivity requires "
                              "the RGD-L element (Leu C-terminal to Asp; Trivehexin RGDLAY / avebehexin RGDLAF). "
                              "RGD without RGDL -> pan-integrin, off-target tox.",
                    scope={"target_class": "integrin-MIDAS", "applies_when": ["avb6"]},
                    provenance={"source_type": "radiopharm-SAR", "ref": "knowledge_liability_flags (αvβ6 SAR); "
                                "Trivehexin selectivity data (EJNMM 2021)",
                                "evidence_tier": "T2", "verified": False,
                                "verification_note": "PARTIAL: Trivehexin's beta6-selectivity IS published (IC50 "
                                "factors avb8 131x, avb3 57x, a5b1 468x). BUT the causal claim 'RGDL element confers "
                                "selectivity / no-RGDL -> pan-integrin' is a program SAR INFERENCE — no cited "
                                "mutational/negative-control study was verified. Not authoritative as a determinant."},
                    effects={"eval_criteria": [{"criterion": "sar:rgd-selectivity-element", "mode": "hard",
                                                "checker": "knowledge_liability_flags.flag_candidate"}]}).validate(),
            KBEntry(id="avb6:sar-lock", kind="sar",
                    statement="D-Pro + N-methyl conformational lock expected, else RGD presented uncontrolled.",
                    scope={"applies_when": ["avb6"]},
                    provenance={"source_type": "literature", "ref": "Trivehexin/avebehexin (EJNMM 2021)",
                                "evidence_tier": "T2", "verified": True,
                                "verification_note": "VERIFIED 2026-10-21: the validated high-affinity compounds "
                                "c[YRGDLAYp(NMe)K]/c(FRGDLAFp(NMe)K) demonstrably carry the D-Pro + N-methyl lock. "
                                "The 'else uncontrolled' necessity is mechanistic inference (lock present in all "
                                "validated actives), hence T2 not T1."},
                    effects={"eval_criteria": [{"criterion": "sar:conformational-lock", "mode": "hard",
                                                "checker": "knowledge_liability_flags.flag_candidate"}]}).validate(),
            KBEntry(id="avb6:sar-renal-charge", kind="sar",
                    statement="Kidney is dose-limiting for peptide RLT; net-positive (cationic) peptides are "
                              "reabsorbed in the proximal tubule (megalin/cubilin) -> higher kidney dose. Extra "
                              "Lys/Arg worsens (does NOT 'tune') renal clearance.",
                    scope={"modality": "targeted radioligand", "applies_when": ["avb6"]},
                    provenance={"source_type": "radiopharm-pharmacology",
                                "ref": "knowledge_liability_flags (renal); megalin/cubilin reabsorption lit "
                                       "(EJNMM s00259-009-1239-1, s00259-010-1685-9)",
                                "evidence_tier": "T1", "verified": True,
                                "verification_note": "VERIFIED 2026-10-21: established radiopharmacology — radiopeptides "
                                "reabsorbed in proximal tubule via megalin/cubilin; cationic Lys/Arg co-infusion "
                                "competitively reduces renal dose; cationic peptides bind megalin via cationic sites "
                                "-> net-positive charge raises kidney (dose-limiting organ) uptake."},
                    effects={"eval_criteria": [{"criterion": "sar:renal-cationic-charge", "mode": "advisory",
                                                "checker": "knowledge_liability_flags.flag_candidate"}]}).validate(),
        ]
    return entries


def _eval_rule_entries(target, spec, cfg) -> list[KBEntry]:
    out = []
    if (spec or {}).get("cofactors"):
        out.append(KBEntry(
            id=f"{target}:metal-free-void",
            kind="eval_rule",
            statement="A metal-free MIDAS run is mechanism-NON-COMPLIANT: its MM-GBSA ΔG is VOID (this is exactly "
                      "why the metal-free αvβ6 round-3 numbers were positive/unphysical).",
            scope={"target_class": "integrin-MIDAS", "applies_when": [target]},
            provenance={"source_type": "program-mechanism", "ref": "scorer_config.mechanism_compliant (applies the "
                        "verified RGD-Asp->MIDAS-metal requirement)", "evidence_tier": "T2", "verified": True,
                        "verification_note": "VERIFIED 2026-10-21: grounded in the confirmed integrin mechanism "
                        "(RGD-Asp carboxylate coordinates the MIDAS divalent metal) — a metal-free run is therefore "
                        "mechanism-incomplete and its MM-GBSA dG is physically void. Program admissibility rule "
                        "applying a verified fact (hence T2, not a raw literature citation)."},
            effects={"eval_criteria": [{"criterion": "metal_retained_in_run", "mode": "hard",
                                        "checker": "scorer_config.mechanism_compliant"}]},
        ).validate())
    return out


def _raw_kb(target) -> dict:
    """The raw target_kb/<target>.json (load_spec drops some fields like `fto`)."""
    p = os.path.join(HERE, "target_kb", f"{target}.json")
    try:
        with open(p) as fh:
            return json.load(fh)
    except Exception:
        return {}


def _fto_entries(target, spec) -> list[KBEntry]:
    fto = (spec or {}).get("fto") or _raw_kb(target).get("fto")
    if not fto:
        return []
    return [KBEntry(
        id=f"{target}:fto-genus",
        kind="fto",
        statement=f"Freedom-to-operate: patent {fto.get('patent')} genus {fto.get('genus')} ({fto.get('status')}); "
                  f"candidates mapping inside the genus are FTO-flagged.",
        scope={"applies_when": [target]},
        provenance={"source_type": "patent-KB",
                    "ref": f"target_kb/{target}.json fto (patent {fto.get('patent')}); fto_score.in_claim",
                    "evidence_tier": "T2", "verified": "unverifiable",
                    "verification_note": f"UNVERIFIABLE 2026-10-21: the specific patent id {fto.get('patent')} and its "
                    "exact genus were NOT independently confirmed. The alphavbeta6-cyclic-RGD patent SPACE is real "
                    "(e.g. US20230173113, US5849692), so the FTO concern is legitimate, but this entry must NOT be "
                    "treated as an authoritative clearance — verify the patent id/claims before relying on it."},
        effects={"eval_criteria": [{"criterion": "fto_genus_clearance", "mode": "advisory",
                                    "checker": "fto_score.in_claim"}]},
    ).validate()]


# =========================== RESOLVER (single source for params + eval) ===========================

def all_entries(target: str) -> list[KBEntry]:
    """Fire every adapter for `target`, returning the concrete provenance-wrapped entries."""
    try:
        import target_spec, scorer_config
        spec = target_spec.load_spec(target)
        cfg = scorer_config.config_for(target)
    except Exception as e:                                   # pragma: no cover
        spec, cfg = None, {"target": target, "known": False, "reason": f"load failed: {e}"}
    entries: list[KBEntry] = []
    entries += _metal_entries(target, spec, cfg)
    entries += _pose_entry(target, spec, cfg)
    entries += _pharmacophore_entries(target)
    entries += _sar_cmc_entries(target)
    entries += _eval_rule_entries(target, spec, cfg)
    entries += _fto_entries(target, spec)
    tclass = _target_class(target, spec)
    return [e for e in entries if isinstance(e, KBEntry) and _applies(e, target, tclass)]


def resolve(target: str) -> dict:
    """The single knowledge entry point: merge the fired entries into {tool_params, eval_criteria} + provenance.
    Existing consumers (target_spec param-setting, the gate assembly) are thin views over this."""
    try:
        import target_spec
        spec = target_spec.load_spec(target)
    except Exception:
        spec = None
    tclass = _target_class(target, spec)
    entries = all_entries(target)
    tool_params: dict[str, Any] = {}
    eval_criteria: list[dict] = []
    provenance: list[dict] = []
    for e in entries:
        tp = (e.effects or {}).get("tool_params", {})
        for k, v in tp.items():
            tool_params[k] = v                               # last-writer; entries are non-overlapping by design
        for c in (e.effects or {}).get("eval_criteria", []):
            eval_criteria.append({**c, "entry": e.id, "tier": e.provenance.get("evidence_tier"),
                                  "verified": e.provenance.get("verified")})
        provenance.append({"entry": e.id, "kind": e.kind, "tier": e.provenance.get("evidence_tier"),
                           "verified": e.provenance.get("verified"), "source": e.provenance.get("ref"),
                           "note": e.provenance.get("verification_note"), "statement": e.statement})
    return {
        "target": target,
        "known": spec is not None,
        "target_class": tclass,
        "modality": (spec or {}).get("modality"),
        "entries_fired": [e.id for e in entries],
        "tool_params": tool_params,
        "eval_criteria": eval_criteria,
        "provenance": provenance,
    }


def main():
    import argparse
    ap = argparse.ArgumentParser(description="Resolve the Experience KB for a target")
    ap.add_argument("--target", default="avb6")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    r = resolve(a.target)
    if a.json:
        print(json.dumps(r, indent=2, default=str)); return
    print(f"EXPERIENCE-KB resolve({a.target})  known={r['known']}  class={r['target_class']}")
    print(f"  entries: {r['entries_fired']}")
    print("  TOOL PARAMS:")
    for k, v in r["tool_params"].items():
        s = v if not isinstance(v, (dict, list)) else json.dumps(v, default=str)
        print(f"    {k} = {str(s)[:120]}")
    print("  EVAL CRITERIA (gate-set):")
    for c in r["eval_criteria"]:
        print(f"    [{c['mode']:8}] {c['criterion']:32} tier={c['tier']} verified={c['verified']} <- {c['checker']}")
    print("  PROVENANCE LEDGER:")
    for p in r["provenance"]:
        print(f"    {p['entry']:28} tier={p['tier']} verified={str(p['verified']):11} src={str(p['source'])[:70]}")


if __name__ == "__main__":
    main()
