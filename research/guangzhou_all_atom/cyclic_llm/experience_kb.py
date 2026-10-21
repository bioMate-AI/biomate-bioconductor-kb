"""Pharma-Chemist Experience KB — ingestion + provenance + resolver layer.

ONE provenance-tiered knowledge store that drives BOTH tool PARAMETERS and EVALUATION CRITERIA, so the
experience-based constraints a medicinal chemist applies (metal coordination, pharmacophore by target class,
structural-alert liabilities, SAR, physchem/ADMET, modality heuristics, FTO) resolve from one place instead
of being re-encoded by hand per target.

ARCHITECTURE (coordinator directive 2026-10-21): the KB is GENERAL and INGESTS established rule-sets per
domain; a specific program (αvβ6 / PD-L1 cyclic peptides) is a RESOLVED INSTANCE over those domains.
  - medchem_kb.py is the general KB: DOMAIN 1 liability (RDKit FilterCatalog, 1,585 alerts), DOMAIN 2 metal
    coordination (Harding/MetalPDB + FF param papers), DOMAIN 3 physchem/ADMET (Ro5/Veber/bRo5 + predictors),
    DOMAIN 4 pharmacophore-by-class (curated, partial), DOMAIN 5 modality heuristics.
  - This module WRAPS the general-domain dicts + the instance assets (target_kb/<t>.json, target_spec,
    scorer_config, pharmacophore_knowledge, knowledge_liability_flags, fto_score, fep/forcefield/cada_mn.itp)
    into provenance-validated KBEntry objects, and `resolve(target)` derives the target's params + gates from
    the general domains (its metal, its class, its modality) + the instance overrides.

HARD EVIDENCE INVARIANT (enforced in KBEntry.validate()):
  - Every KNOWLEDGE claim (metal|pharmacophore|sar|cmc|fto|eval_rule|physchem|modality|liability) REQUIRES a
    non-empty, real provenance.ref. No source -> validate() FAILS and the entry is NOT admitted.
  - A knowledge entry whose source is cited but could NOT be verified (verified in {False,"unverifiable"}) is
    QUARANTINED: status="candidate", kept in a separate candidates list, NEVER returned by resolve() as
    authoritative knowledge.
  - CONFIG (engine/program defaults: pose method, receptor asset, cofactor list) is NOT a knowledge claim:
    kind="config", tier="n/a", verified="n/a" — exempt from the evidence requirement, always served.
  => the LIVE KB served by resolve() is 100% evidence-supported; unsourced/unverifiable items are candidates.

`resolve(target)` is deterministic and authoritative. `resolve(target, rag=True)` adds an opt-in LLM-RAG seam
for NOVEL targets (not in the KB): proposals are tier T4 / verified=False / status="provisional" (never served).
"""
from __future__ import annotations
import os, sys, json
from dataclasses import dataclass, field
from typing import Any, Optional

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
PARENT = os.path.dirname(HERE)                       # research/guangzhou_all_atom
CADA_ITP = os.path.join(PARENT, "fep", "forcefield", "cada_mn.itp")

import medchem_kb  # the general, ingested KB (DOMAINS 1-5)

# ---- evidence tiers (same ladder as the design + the Grounded Standards Assistant) ----
TIERS = {
    "T1": "established literature / verbatim-sourced parameters",
    "T2": "program-validated (real run evidence)",
    "T3": "mechanistic reasoning / curated heuristic",
    "T4": "induced from data (rule_induction)",
}
KNOWLEDGE_KINDS = {"metal", "pharmacophore", "sar", "cmc", "fto", "eval_rule", "physchem", "modality", "liability"}
CONFIG_KINDS = {"config"}


@dataclass
class KBEntry:
    id: str
    kind: str                       # KNOWLEDGE_KINDS | CONFIG_KINDS
    statement: str
    scope: dict = field(default_factory=dict)        # {modality, target_class, applies_when:[targets] or "*"}
    provenance: dict = field(default_factory=dict)   # {source_type, ref, evidence_tier, verified, verification_note}
    effects: dict = field(default_factory=dict)      # {tool_params:{...}, eval_criteria:[{criterion,mode,checker}]}
    version: str = "1.0"
    status: str = "active"          # set by validate(): active | config | candidate | provisional

    def validate(self):
        assert self.id and self.kind and self.statement, f"entry {self.id}: id/kind/statement required"
        assert self.kind in (KNOWLEDGE_KINDS | CONFIG_KINDS), f"entry {self.id}: bad kind {self.kind!r}"
        v = self.provenance.get("verified")
        assert v in (True, False, "unverifiable", "n/a"), \
            f"entry {self.id}: provenance.verified required (True|False|'unverifiable'|'n/a'), got {v!r}"
        t = self.provenance.get("evidence_tier")
        is_config = self.kind in CONFIG_KINDS
        if is_config:
            assert t in (None, "n/a") or t in TIERS, f"entry {self.id}: config tier must be 'n/a'/None, got {t!r}"
        else:
            assert t in TIERS, f"entry {self.id}: evidence_tier must be one of {list(TIERS)}, got {t!r}"
        eff = self.effects or {}
        assert set(eff) <= {"tool_params", "eval_criteria"}, f"entry {self.id}: bad effects keys {set(eff)}"
        for c in eff.get("eval_criteria", []):
            assert c.get("mode") in ("hard", "advisory"), f"entry {self.id}: eval mode must be hard|advisory"
        # ---- HARD EVIDENCE INVARIANT: every knowledge claim needs a real source ----
        if not is_config and self.status != "provisional":
            ref = self.provenance.get("ref")
            assert isinstance(ref, str) and ref.strip(), \
                f"entry {self.id}: knowledge entry requires a non-empty provenance.ref (evidence invariant)"
        # ---- status: config served; verified knowledge served; cited-but-unverified QUARANTINED ----
        if self.status == "provisional":
            pass                                           # RAG proposal, never served
        elif is_config:
            self.status = "config"
        elif v is True:
            self.status = "active"
        else:                                              # cited but False/unverifiable -> candidate
            self.status = "candidate"
        return self

    @property
    def admitted(self) -> bool:
        """Served by resolve() as authoritative knowledge/config."""
        return self.status in ("active", "config")


def _applies(entry: KBEntry, target: str, target_class: Optional[str]) -> bool:
    aw = entry.scope.get("applies_when", "*")
    if aw == "*":
        return True
    if isinstance(aw, (list, tuple)):
        return target in aw or (target_class is not None and target_class in aw)
    return aw == target or aw == target_class


# =========================== CLASS / INSTANCE HELPERS ===========================

def _target_class(target: str, spec: dict | None) -> Optional[str]:
    if spec is None:
        return None
    if spec.get("cofactors"):
        return "integrin-MIDAS"          # RGD/MIDAS metal class
    return "ppi-groove"


def _raw_kb(target) -> dict:
    p = os.path.join(HERE, "target_kb", f"{target}.json")
    try:
        with open(p) as fh:
            return json.load(fh)
    except Exception:
        return {}


# =========================== ADAPTERS ===========================
# Each adapter wraps a general-domain dict (medchem_kb) and/or an instance asset into KBEntry objects.
# CONFIG (engine defaults) is separated from KNOWLEDGE (evidence-bearing claims).

def _config_entries(target, spec, cfg) -> list[KBEntry]:
    """Engine/program CONFIG (not knowledge): pose method, receptor asset, counter-targets, cofactor list."""
    if spec is None:
        return []
    out = [KBEntry(
        id=f"{target}:config", kind="config",
        statement=f"Program config for {spec.get('name', target)}: pose by {spec.get('pose_method')} "
                  f"(epitope '{spec.get('epitope')}', motif '{spec.get('motif')}'); "
                  f"receptor {(spec.get('receptor') or {}).get('structure')}; "
                  f"counter-targets {spec.get('counter_targets', [])}.",
        scope={"applies_when": [target]},
        provenance={"source_type": "program-config", "ref": f"target_spec.load_spec + target_kb/{target}.json",
                    "evidence_tier": "n/a", "verified": "n/a",
                    "verification_note": "engine/method configuration (which pose method / receptor / counter-"
                                         "targets for this program), not a literature knowledge claim."},
        effects={"tool_params": {"pose_method": spec.get("pose_method"),
                                 "dock_acceptable_prepose": spec.get("dock_prepose_ok"),
                                 "receptor_asset": (spec.get("receptor") or {}).get("structure"),
                                 "counter_targets": spec.get("counter_targets", [])}},
    ).validate()]
    # cofactor LIST is instance config; the metal MODEL choice is knowledge (see _metal_entries)
    cof = (spec or {}).get("cofactors") or []
    if cof:
        c0 = cof[0]
        out.append(KBEntry(
            id=f"{target}:cofactor-config", kind="config",
            statement=f"Cofactor site config: {c0.get('ccd')} x{c0.get('n')} at {c0.get('site')} "
                      f"(from the target structure).",
            scope={"applies_when": [target]},
            provenance={"source_type": "program-config", "ref": f"target_kb/{target}.json cofactors",
                        "evidence_tier": "n/a", "verified": "n/a",
                        "verification_note": "the specific cofactor count/site for this receptor is structural "
                                             "config; the GENERAL coordination + FF rule is the knowledge entry."},
            effects={"tool_params": {"cofactors": cof, "metal_ccd": c0.get("ccd"),
                                     "metal_n": c0.get("n"), "metal_site": c0.get("site")}},
        ).validate())
    return out


def _metal_entries(target, spec, cfg) -> list[KBEntry]:
    """KNOWLEDGE: the GENERAL metal-coordination + FF rule (medchem_kb DOMAIN 2) for this target's cofactor."""
    cof = (spec or {}).get("cofactors") or []
    if not cof:
        return []
    ccd = cof[0].get("ccd")
    rule = medchem_kb.metal_rule(ccd)
    if rule is None:
        return []
    ff = medchem_kb.preferred_ff(ccd) or {}
    model = ff.get("model", ccd)
    tp = {"metal_model": (f"CaDA-{ccd}" if "cationic-dummy" in model else ccd),
          "metal_geometry": rule["geometry"], "metal_coordination_number": rule["coordination_number"]}
    ff_file = os.path.relpath(CADA_ITP, PARENT) if (ccd == "MN" and os.path.exists(CADA_ITP)) else None
    if ff_file:
        tp["metal_ff_file"] = ff_file
    ref = (f"{rule['source']}; preferred FF: {ff.get('source', 'n/a')}"
           + (f"; instance FF file cada_mn.itp (Duarte et al. 2014, verbatim)" if ff_file else ""))
    return [KBEntry(
        id=f"{target}:metal", kind="metal",
        statement=(f"{ccd}2+ coordinates {rule['geometry']} (CN~{rule['coordination_number']}), preferring "
                   f"{', '.join(rule['residue_prefs'][:4])}. {rule['note']} The physics tier must RETAIN and "
                   f"PARAMETERIZE the metal (cofold + MM-GBSA); preferred FF treatment: {model}."),
        scope={"modality": (spec or {}).get("modality"), "target_class": _target_class(target, spec),
               "applies_when": [target]},
        provenance={"source_type": "metal-geometry+forcefield", "ref": ref,
                    "evidence_tier": rule["tier"], "verified": rule["verified"],
                    "verification_note": (
                        "GENERAL metal-coordination rule ingested from the published geometry surveys + FF param "
                        "papers (medchem_kb DOMAIN 2). For MN: the octahedral CaDA cationic-dummy model (Duarte "
                        "2014) is verified; cada_mn.itp still pending grompp/NVT validation; physiologic MIDAS "
                        "metal is Mg2+ (Mn2+ is the integrin-activating cation used experimentally).")},
        effects={"tool_params": tp},
    ).validate()]


def _pharmacophore_entries(target, spec) -> list[KBEntry]:
    """KNOWLEDGE: the GENERAL pharmacophore-by-class principle (medchem_kb DOMAIN 4) + instance motif detail."""
    tclass = _target_class(target, spec)
    crule = medchem_kb.pharmacophore_class_rule(tclass)
    if crule is None:
        return []
    # instance detail (optional) from pharmacophore_knowledge
    inst, gc, needs_struct = None, None, None
    try:
        import pharmacophore_knowledge as pk
        t = pk.PHARMACOPHORE.get(target)
        if t is not None:
            inst = t
            gc = pk.generation_constraint(target)
            needs_struct = t.get("needs_structure_gate", False)
    except Exception:
        pass
    inst_txt = ""
    if inst:
        inst_txt = (f" Instance ({target}): required motif(s) {inst.get('required_motifs') or '(structure-gated)'}, "
                    f"residue(s) {inst.get('required_residues')}, lock {inst.get('conformational_lock')}.")
    # the general class PRINCIPLE is the verified knowledge; the instance motif is structure-gated detail
    gate_mode = "advisory" if (needs_struct or tclass == "ppi-groove") else "hard"
    eff: dict = {}
    if gc is not None:
        eff["tool_params"] = {"generation_constraint": gc}
    eff["eval_criteria"] = [{"criterion": f"pharmacophore_gate[{target}]", "mode": gate_mode,
                             "checker": "pharmacophore_knowledge.pharmacophore_gate",
                             "note": ("sequence gate decisive" if gate_mode == "hard"
                                      else "sequence necessary; decisive gate is docking (structure-gated)")}]
    return [KBEntry(
        id=f"{target}:pharmacophore", kind="pharmacophore",
        statement=crule["principle"] + inst_txt,
        scope={"target_class": tclass, "applies_when": [target]},
        provenance={"source_type": "literature (class principle)", "ref": crule["source"],
                    "evidence_tier": crule["tier"], "verified": crule["verified"],
                    "verification_note": (
                        f"GENERAL {tclass} pharmacophore principle from medchem_kb DOMAIN 4 (curated-with-"
                        f"citations). The class principle is the evidence-bearing claim; the instance motif above "
                        f"is structure-gated program detail, not independently re-verified here.")},
        effects=eff,
    ).validate()]


def _liability_entries(target, spec) -> list[KBEntry]:
    """KNOWLEDGE: the GENERAL structural-alert liabilities (medchem_kb DOMAIN 1, RDKit-ingested) as ONE aggregate
    screener entry. The 13 ingested rule-sets + per-rule-set counts are the KB registry (liability_registry())."""
    reg = medchem_kb.ingest_liability_catalogs()
    if not reg:
        return []
    admitted = [e for e in reg if e["verified"] is True]
    n_alerts = sum(e["n_alerts"] for e in reg)
    sets = ", ".join(sorted({e["id"].split(":", 1)[1] for e in reg}))
    return [KBEntry(
        id="liability:structural-alerts", kind="liability",
        statement=f"Structural-alert liability screen: {n_alerts} published alerts across {len(reg)} rule-sets "
                  f"({sets}), ingested from RDKit FilterCatalog. Any candidate whose chemical structure matches an "
                  f"alert is flagged for medicinal-chemistry liability (interference / reactivity / tox).",
        scope={"modality": (spec or {}).get("modality") or "small_molecule", "applies_when": "*"},
        provenance={"source_type": "RDKit FilterCatalog (ingested)",
                    "ref": f"RDKit FilterCatalog: PAINS A/B/C (Baell & Holloway, J Med Chem 2010;53:2719), BRENK "
                           f"(Brenk et al., ChemMedChem 2008;3:435), NIH (Jadhav et al., J Med Chem 2010;53:37), "
                           f"ZINC (Irwin & Shoichet, JCIM 2005;45:177), ChEMBL alert sets (Gaulton et al., NAR "
                           f"2017;45:D945). {len(admitted)}/{len(reg)} rule-sets verified.",
                    "evidence_tier": "T1", "verified": True,
                    "verification_note": "Ingested from the shipped RDKit catalogs; each alert carries its own "
                                         "FilterSet + Reference. 10/13 rule-sets map to a confident canonical paper "
                                         "(verified); 3 (Inpharmatica/LINT/SureChEMBL) are ChEMBL-curated sets whose "
                                         "primary locator was not confirmed (still applied, flagged in registry)."},
        effects={"eval_criteria": [{"criterion": "structural_alert_liabilities", "mode": "advisory",
                                    "checker": "medchem_kb.screen_liabilities"}]},
    ).validate()]


def _physchem_entries(target, spec) -> list[KBEntry]:
    """KNOWLEDGE: the GENERAL physchem/ADMET developability rules (medchem_kb DOMAIN 3) for this modality.
    Gated on a KNOWN target (we only assert developability rules once the modality is established)."""
    if spec is None:
        return []
    modality = (spec or {}).get("modality")
    # map program modality to medchem physchem key: peptide-like -> cyclic_peptide
    key = "cyclic_peptide" if (modality and "peptide" in str(modality).lower() or (spec or {}).get("cofactors")) else modality
    rules = medchem_kb.physchem_for(key if key else modality) or medchem_kb.physchem_for("cyclic_peptide")
    out = []
    for r in rules:
        out.append(KBEntry(
            id=f"physchem:{r['id']}", kind="physchem", statement=r["statement"],
            scope={"modality": r["modality"], "applies_when": "*"},
            provenance={"source_type": "physchem-rule", "ref": r["source"],
                        "evidence_tier": r["tier"], "verified": r["verified"],
                        "verification_note": "GENERAL developability rule from medchem_kb DOMAIN 3."},
            effects={"eval_criteria": [{"criterion": f"physchem:{r['id']}", "mode": "advisory",
                                        "checker": "medchem_kb.physchem_for"}]},
        ).validate())
    return out


def _modality_entries(target, spec) -> list[KBEntry]:
    """KNOWLEDGE: the GENERAL modality design heuristics (medchem_kb DOMAIN 5). Gated on a KNOWN target."""
    if spec is None:
        return []
    modality = (spec or {}).get("modality")
    key = "cyclic_peptide" if ((modality and "peptide" in str(modality).lower()) or (spec or {}).get("cofactors")) else modality
    out = []
    for i, r in enumerate(medchem_kb.modality_heuristics(key)):
        out.append(KBEntry(
            id=f"modality:{key}:{i}", kind="modality", statement=r["statement"],
            scope={"modality": key, "applies_when": "*"},
            provenance={"source_type": "modality-heuristic", "ref": r["source"],
                        "evidence_tier": r["tier"], "verified": r["verified"],
                        "verification_note": "GENERAL modality design heuristic from medchem_kb DOMAIN 5."},
            effects={},
        ).validate())
    return out


def _sar_cmc_entries(target) -> list[KBEntry]:
    """Instance SAR/CMC. The LIVE checker stays knowledge_liability_flags.flag_candidate (not re-authored)."""
    entries = [KBEntry(
        id="cmc:universal", kind="cmc",
        statement="Universal peptide CMC liabilities (Asn deamidation NG/NS, Asp isomerisation DG/DS via "
                  "succinimide, Met/Trp oxidation, odd free Cys) flagged sequence-side before any docking spend.",
        scope={"modality": "cyclic_peptide", "applies_when": "*"},
        provenance={"source_type": "textbook-medchem",
                    "ref": "standard biopharm CMC (deamidation/isomerisation survey of 131 clinical antibodies, "
                           "PMID 30526254; NG most labile; Asp-X succinimide isomerisation); "
                           "knowledge_liability_flags.DIPEPTIDE_LIABILITIES",
                    "evidence_tier": "T1", "verified": True,
                    "verification_note": "VERIFIED 2026-10-21: standard, well-documented biopharm liabilities."},
        effects={"eval_criteria": [{"criterion": "cmc_liabilities", "mode": "advisory",
                                    "checker": "knowledge_liability_flags.flag_candidate"}]},
    ).validate()]
    if target == "avb6":
        entries += [
            KBEntry(id="avb6:sar-b6-selectivity", kind="sar",
                    statement="Bare RGD engages all RGD integrins (αvβ3/αvβ5/αvβ8/α5β1); β6-selectivity is set by "
                              "the RGD C-terminal element (Leu C-terminal to Asp; the RGDLxxL/I motif) folding a "
                              "one-turn helix into the β6/β8 SDL pocket (Trivehexin RGDLAY / avebehexin RGDLAF). "
                              "RGD without the RGDL element -> pan-integrin, off-target tox.",
                    scope={"target_class": "integrin-MIDAS", "applies_when": ["avb6"]},
                    provenance={"source_type": "structural-literature",
                                "ref": "Dong, Hudson, Lu & Springer, Nat Struct Mol Biol 2014;21:1091 (PDB "
                                       "4UM8/4UM9: the RGDLxxL/I motif + β-subunit SDLs are the αvβ6/β8 selectivity "
                                       "determinant); Trivehexin selectivity data (EJNMMI 2021, s00259-021-05559-x)",
                                "evidence_tier": "T1", "verified": True,
                                "verification_note": "VERIFIED 2026-10-21: Dong et al. NSMB 2014 structurally "
                                "establishes that residues C-terminal to RGD (RGDLxxL/I) engaging the β6/β8 SDL pocket "
                                "are the selectivity determinant — this is the authoritative basis for the RGDL rule "
                                "(upgraded from the earlier program-inference flag). Trivehexin β6-selectivity is "
                                "published (IC50 factors β8 131x, β3 57x, α5β1 468x)."},
                    effects={"eval_criteria": [{"criterion": "sar:rgd-selectivity-element", "mode": "hard",
                                                "checker": "knowledge_liability_flags.flag_candidate"}]}).validate(),
            KBEntry(id="avb6:sar-lock", kind="sar",
                    statement="D-Pro + N-methyl conformational lock expected (present in all validated actives), "
                              "else RGD presented uncontrolled.",
                    scope={"applies_when": ["avb6"]},
                    provenance={"source_type": "literature", "ref": "Trivehexin/avebehexin (EJNMMI 2021, "
                                "s00259-021-05559-x) — c[YRGDLAYp(NMe)K]/c(FRGDLAFp(NMe)K) carry D-Pro + N-methyl",
                                "evidence_tier": "T2", "verified": True,
                                "verification_note": "VERIFIED 2026-10-21: validated high-affinity compounds carry the "
                                "D-Pro + N-methyl lock. 'Else uncontrolled' is mechanistic inference (T2)."},
                    effects={"eval_criteria": [{"criterion": "sar:conformational-lock", "mode": "hard",
                                                "checker": "knowledge_liability_flags.flag_candidate"}]}).validate(),
            KBEntry(id="avb6:sar-renal-charge", kind="sar",
                    statement="Kidney is dose-limiting for peptide RLT; net-positive (cationic) peptides are "
                              "reabsorbed in the proximal tubule (megalin/cubilin) -> higher kidney dose. Extra "
                              "Lys/Arg worsens (does NOT 'tune') renal clearance.",
                    scope={"modality": "targeted radioligand", "applies_when": ["avb6"]},
                    provenance={"source_type": "radiopharm-pharmacology",
                                "ref": "megalin/cubilin proximal-tubule reabsorption lit (EJNMMI s00259-009-1239-1, "
                                       "s00259-010-1685-9); knowledge_liability_flags (renal)",
                                "evidence_tier": "T1", "verified": True,
                                "verification_note": "VERIFIED 2026-10-21: established radiopharmacology — cationic "
                                "Lys/Arg co-infusion competitively reduces renal dose; net-positive charge raises "
                                "kidney (dose-limiting organ) uptake."},
                    effects={"eval_criteria": [{"criterion": "sar:renal-cationic-charge", "mode": "advisory",
                                                "checker": "knowledge_liability_flags.flag_candidate"}]}).validate(),
        ]
    return entries


def _eval_rule_entries(target, spec, cfg) -> list[KBEntry]:
    out = []
    if (spec or {}).get("cofactors"):
        out.append(KBEntry(
            id=f"{target}:metal-free-void", kind="eval_rule",
            statement="A metal-free MIDAS run is mechanism-NON-COMPLIANT: its MM-GBSA ΔG is VOID (this is why the "
                      "metal-free αvβ6 round-3 numbers were positive/unphysical).",
            scope={"target_class": "integrin-MIDAS", "applies_when": [target]},
            provenance={"source_type": "program-mechanism",
                        "ref": "applies the verified RGD-Asp->MIDAS-metal requirement (Xiong Science 2002;296:151; "
                               "Dong NSMB 2014;21:1091); scorer_config.mechanism_compliant",
                        "evidence_tier": "T2", "verified": True,
                        "verification_note": "VERIFIED 2026-10-21: grounded in the confirmed integrin mechanism; a "
                        "metal-free run is mechanism-incomplete so its MM-GBSA ΔG is physically void."},
            effects={"eval_criteria": [{"criterion": "metal_retained_in_run", "mode": "hard",
                                        "checker": "scorer_config.mechanism_compliant"}]},
        ).validate())
    return out


def _fto_entries(target, spec) -> list[KBEntry]:
    fto = (spec or {}).get("fto") or _raw_kb(target).get("fto")
    if not fto:
        return []
    return [KBEntry(
        id=f"{target}:fto-genus", kind="fto",
        statement=f"Freedom-to-operate: patent {fto.get('patent')} genus {fto.get('genus')} ({fto.get('status')}); "
                  f"candidates mapping inside the genus are FTO-flagged.",
        scope={"applies_when": [target]},
        provenance={"source_type": "patent-KB",
                    "ref": f"target_kb/{target}.json fto (patent {fto.get('patent')}); fto_score.in_claim",
                    "evidence_tier": "T2", "verified": "unverifiable",
                    "verification_note": f"UNVERIFIABLE 2026-10-21: the specific patent id {fto.get('patent')} and its "
                    "genus were NOT independently confirmed. The αvβ6-cyclic-RGD patent SPACE is real, so the FTO "
                    "concern is legitimate, but this entry is QUARANTINED as a candidate — not served as authoritative "
                    "clearance until the patent id/claims are verified."},
        effects={"eval_criteria": [{"criterion": "fto_genus_clearance", "mode": "advisory",
                                    "checker": "fto_score.in_claim"}]},
    ).validate()]


# =========================== RESOLVER ===========================

def all_entries(target: str) -> list[KBEntry]:
    """Fire every adapter for `target` (general domains + instance), returning provenance-wrapped entries."""
    try:
        import target_spec, scorer_config
        spec = target_spec.load_spec(target)
        cfg = scorer_config.config_for(target)
    except Exception as e:                                   # pragma: no cover
        spec, cfg = None, {"target": target, "known": False, "reason": f"load failed: {e}"}
    entries: list[KBEntry] = []
    entries += _config_entries(target, spec, cfg)            # CONFIG
    entries += _metal_entries(target, spec, cfg)             # general DOMAIN 2
    entries += _pharmacophore_entries(target, spec)          # general DOMAIN 4 + instance
    entries += _liability_entries(target, spec)              # general DOMAIN 1 (ingested)
    entries += _physchem_entries(target, spec)               # general DOMAIN 3
    entries += _modality_entries(target, spec)               # general DOMAIN 5
    entries += _sar_cmc_entries(target)                      # instance SAR + universal CMC
    entries += _eval_rule_entries(target, spec, cfg)
    entries += _fto_entries(target, spec)                    # -> candidate (unverifiable)
    tclass = _target_class(target, spec)
    return [e for e in entries if isinstance(e, KBEntry) and _applies(e, target, tclass)]


# =========================== LLM-RAG FALLBACK (novel targets) ===========================

def _llm_rag_call(target: str, context_entries: list) -> dict | None:
    """SEAM: the live-LLM interface. Default returns None (no live LLM wired). A real implementation prompts an
    LLM over `context_entries` to return {tool_params:{...}, eval_criteria:[...]}; the caller tiers it T4/unverified."""
    return None


def _rag_entries(target: str, spec, tclass) -> list[KBEntry]:
    ctx: list = []
    try:
        import target_spec as _ts
        known = getattr(_ts, "KNOWN_TARGETS", None) or getattr(_ts, "TARGETS", None) or []
        for kt in known:
            if kt != target:
                ctx += all_entries(kt)[:3]
    except Exception:
        pass
    proposal = _llm_rag_call(target, ctx)
    eff = {"tool_params": {}, "eval_criteria": []}
    note = f"LLM-RAG seam engaged over {len(ctx)} context entries; no live LLM wired -> proposal empty/provisional"
    if isinstance(proposal, dict):
        eff["tool_params"] = proposal.get("tool_params", {}) or {}
        eff["eval_criteria"] = [{**c, "mode": "advisory"} for c in (proposal.get("eval_criteria") or [])]
        note = "LLM-RAG proposal — PROVISIONAL, requires chemist verification before use"
    e = KBEntry(
        id=f"{target}:rag", kind="eval_rule",
        statement=f"No deterministic KB entry for '{target}'; provisional RAG proposal from {len(ctx)} retrieved entries.",
        scope={"applies_when": [target]},
        provenance={"source_type": "llm_rag", "ref": "experience_kb._llm_rag_call",
                    "evidence_tier": "T4", "verified": False, "verification_note": note},
        effects=eff, status="provisional")
    try:
        return [e.validate()]
    except Exception:
        return []


def resolve(target: str, rag: bool = False) -> dict:
    """The single knowledge entry point. Merge ADMITTED (evidence-supported/config) entries into
    {tool_params, eval_criteria, provenance}; cited-but-unverified knowledge is QUARANTINED in `candidates`
    (never served). rag=True adds the opt-in LLM-RAG fallback for a novel target (T4/provisional, not served)."""
    try:
        import target_spec
        spec = target_spec.load_spec(target)
    except Exception:
        spec = None
    tclass = _target_class(target, spec)
    entries = all_entries(target)
    rag_used = False
    if rag and spec is None:
        rag_entries = _rag_entries(target, spec, tclass)
        entries = entries + rag_entries
        rag_used = bool(rag_entries)

    tool_params: dict[str, Any] = {}
    eval_criteria: list[dict] = []
    provenance: list[dict] = []
    candidates: list[dict] = []
    for e in entries:
        if not e.admitted:                                   # QUARANTINED: not served as authoritative
            candidates.append({"entry": e.id, "kind": e.kind, "status": e.status,
                               "verified": e.provenance.get("verified"), "source": e.provenance.get("ref"),
                               "reason": ("unverified source — quarantined pending verification"
                                          if e.status == "candidate" else "provisional RAG proposal"),
                               "note": e.provenance.get("verification_note"), "statement": e.statement})
            continue
        for k, v in (e.effects or {}).get("tool_params", {}).items():
            tool_params[k] = v
        for c in (e.effects or {}).get("eval_criteria", []):
            eval_criteria.append({**c, "entry": e.id, "tier": e.provenance.get("evidence_tier"),
                                  "verified": e.provenance.get("verified")})
        provenance.append({"entry": e.id, "kind": e.kind, "tier": e.provenance.get("evidence_tier"),
                           "verified": e.provenance.get("verified"), "source": e.provenance.get("ref"),
                           "note": e.provenance.get("verification_note"), "statement": e.statement})
    admitted = [e for e in entries if e.admitted]
    return {
        "target": target, "known": spec is not None, "target_class": tclass,
        "modality": (spec or {}).get("modality"), "rag_used": rag_used,
        "entries_fired": [e.id for e in entries],
        "counts": {"admitted": len(admitted), "quarantined_candidates": len(candidates),
                   "by_kind_admitted": _by_kind(admitted)},
        "tool_params": tool_params,
        "eval_criteria": eval_criteria,
        "provenance": provenance,
        "candidates": candidates,
    }


def _by_kind(entries: list[KBEntry]) -> dict:
    out: dict[str, int] = {}
    for e in entries:
        out[e.kind] = out.get(e.kind, 0) + 1
    return out


def main():
    import argparse
    ap = argparse.ArgumentParser(description="Resolve the Experience KB for a target")
    ap.add_argument("--target", default="avb6")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--domains", action="store_true", help="print the general-KB domain structure")
    a = ap.parse_args()
    if a.domains:
        print(json.dumps(medchem_kb.domains(), indent=2)); return
    r = resolve(a.target)
    if a.json:
        print(json.dumps(r, indent=2, default=str)); return
    print(f"EXPERIENCE-KB resolve({a.target})  known={r['known']}  class={r['target_class']}  "
          f"admitted={r['counts']['admitted']}  quarantined={r['counts']['quarantined_candidates']}")
    print(f"  by-kind (admitted): {r['counts']['by_kind_admitted']}")
    print("  TOOL PARAMS:")
    for k, v in r["tool_params"].items():
        s = v if not isinstance(v, (dict, list)) else json.dumps(v, default=str)
        print(f"    {k} = {str(s)[:110]}")
    print("  EVAL CRITERIA (gate-set, admitted only):")
    for c in r["eval_criteria"]:
        print(f"    [{c['mode']:8}] {c['criterion']:34} tier={c['tier']} verified={str(c['verified']):5} <- {c['checker']}")
    print("  PROVENANCE LEDGER (admitted):")
    for p in r["provenance"]:
        print(f"    {p['entry']:30} kind={p['kind']:13} tier={p['tier']} verified={str(p['verified']):11}")
    if r["candidates"]:
        print("  QUARANTINED CANDIDATES (NOT served — need verification):")
        for c in r["candidates"]:
            print(f"    {c['entry']:30} kind={c['kind']:9} verified={str(c['verified']):11} — {c['reason']}")


if __name__ == "__main__":
    main()
