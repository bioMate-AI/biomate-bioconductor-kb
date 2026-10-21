"""General medicinal-chemistry knowledge base — an INGESTION + provenance layer over established rule-sets.

This is the GENERAL KB (not a project's literal rules). Knowledge is organized by DOMAIN and, per domain,
is INGESTED from an authoritative existing resource rather than hand-written entry-by-entry:

  DOMAIN 1  LIABILITY / SAR     <- RDKit `FilterCatalog` (PAINS A/B/C, BRENK, NIH, ZINC, ChEMBL structural
                                   alert sets) — 1,585 published alerts, each carrying its catalog + paper.
  DOMAIN 2  METAL COORDINATION  <- published metal-geometry surveys (Harding; MetalPDB; CheckMyMetal) +
                                   the force-field param papers (MCPB.py, Li-Merz 12-6-4, Duarte CaDA). Not
                                   cheaply downloadable -> the PUBLISHED tables are encoded with citations.
  DOMAIN 3  PHYSCHEM / ADMET    <- the standard rule definitions (Lipinski Ro5, Veber, Doak-Kihlberg bRo5),
                                   + pointers to the external predictors (SwissADME, ADMETlab) to call.
  DOMAIN 4  PHARMACOPHORE       <- the one domain with no single clean DB: target-class principles curated
                                   from reviews WITH citations. FLAGGED as the partially-curated domain.
  DOMAIN 5  MODALITY HEURISTICS <- cyclization / N-methylation / stapling design rules, cited.
  (+ DATA SOURCES: affinity = ChEMBL/BindingDB via binding_affinity_v1; permeability = CycPeptMPDB.)

A specific program (the αvβ6 / PD-L1 cyclic-peptide work) is a RESOLVED INSTANCE: experience_kb.resolve(target)
looks the target up against these general domains (its metal, its target class, its modality) and layers the
target_kb/<t>.json instance facts on top. These functions return plain dicts (data + real provenance refs);
experience_kb wraps them into provenance-validated KBEntry objects and enforces the evidence invariant.

Citation-integrity: ingested alerts carry the catalog's own shipped provenance verbatim (FilterSet + Reference
+ Scope) PLUS a canonical paper where held with confidence. Encoded tables cite the real survey/param paper.
`verified=True` = established/shipped source; `verified="unverifiable"` = standard principle, specific locator
not confirmed here (such entries are QUARANTINED as candidates by experience_kb, never served as fact).
"""
from __future__ import annotations
from typing import Optional

# =============================================================================================
# DOMAIN 1 — LIABILITY / SAR  (INGESTED from RDKit FilterCatalog; nothing hand-written)
# Each RDKit FilterSet -> canonical paper. provenance.ref carries the shipped Reference+Scope verbatim
# PLUS this canonical citation. RDKit 2025.09.2: PAINS_A 16, PAINS_B 55, PAINS_C 409, BRENK 105, NIH 180,
# ZINC 50, CHEMBL 770 (BMS 180, Dundee 105, Glaxo 55, Inpharmatica 91, LINT 57, MLSMR 116, SureChEMBL 166).
# =============================================================================================
_LIABILITY_CANON = {   # FilterSet value (RDKit) -> (canonical reference, evidence_tier, verified)
    "PAINS_A": ("Baell & Holloway, J Med Chem 2010;53:2719-2740 (PMID 20131845) — PAINS filter family A", "T1", True),
    "PAINS_B": ("Baell & Holloway, J Med Chem 2010;53:2719-2740 (PMID 20131845) — PAINS filter family B", "T1", True),
    "PAINS_C": ("Baell & Holloway, J Med Chem 2010;53:2719-2740 (PMID 20131845) — PAINS filter family C", "T1", True),
    "Brenk":   ("Brenk et al., ChemMedChem 2008;3:435-444 (PMID 18064617) — unwanted-fragment alerts", "T1", True),
    "NIH":     ("NIH/MLSMR annotated alerts (Jadhav et al., J Med Chem 2010;53:37; Doveston/Saubern via "
                "P. Walters rd_filters)", "T1", True),
    "ZINC":    ("Irwin & Shoichet, J Chem Inf Model 2005;45:177-182 — ZINC drug-like filters", "T1", True),
    "ChEMBL23_BMS":        ("Pearce et al., J Chem Inf Model 2006;46:1060 — BMS HTS deck exclusion filters (via ChEMBL)", "T1", True),
    "ChEMBL23_Dundee":     ("Brenk et al., ChemMedChem 2008;3:435 (Dundee set, via ChEMBL)", "T1", True),
    "ChEMBL23_Glaxo":      ("Hann et al., J Chem Inf Comput Sci 1999;39:897 — GSK hard filters (via ChEMBL)", "T1", True),
    "ChEMBL23_Inpharmatica":("Inpharmatica unwanted-fragment alerts (ChEMBL structural-alert set; Gaulton et al., "
                             "Nucleic Acids Res 2017;45:D945)", "T2", "unverifiable"),
    "ChEMBL23_LINT":       ("Pfizer LINT lead-likeness alerts (ChEMBL structural-alert set; Gaulton et al., NAR 2017)", "T2", "unverifiable"),
    "ChEMBL23_MLSMR":      ("NIH MLSMR excluded-functionality alerts (ChEMBL structural-alert set; Gaulton et al., NAR 2017)", "T1", True),
    "ChEMBL23_SureChEMBL": ("SureChEMBL non-MedChem-friendly alerts (ChEMBL structural-alert set; Gaulton et al., NAR 2017)", "T2", "unverifiable"),
}
# RDKit FilterCatalogs enum names to load:
_RDKIT_CATALOGS = ["PAINS_A", "PAINS_B", "PAINS_C", "BRENK", "NIH", "ZINC", "CHEMBL"]


def _entry_props(e) -> dict:
    d = {}
    for k in e.GetPropList():
        try:
            d[k] = e.GetProp(k)
        except Exception:
            pass
    return d


def ingest_liability_catalogs() -> list[dict]:
    """INGEST RDKit FilterCatalog as one KB-ready dict per (catalog x FilterSet rule-set).
    Each dict carries: id, statement, n_alerts, source (shipped Reference+Scope + canonical paper), tier, verified.
    Returns [] if RDKit is unavailable (the KB simply reports the liability domain as un-ingested)."""
    try:
        from rdkit.Chem import FilterCatalog
        from rdkit.Chem.FilterCatalog import FilterCatalogParams
    except Exception:
        return []
    by_set: dict[str, dict] = {}
    for cat in _RDKIT_CATALOGS:
        enum = getattr(FilterCatalogParams.FilterCatalogs, cat, None)
        if enum is None:
            continue
        p = FilterCatalogParams(); p.AddCatalog(enum)
        fc = FilterCatalog.FilterCatalog(p)
        for i in range(fc.GetNumEntries()):
            pr = _entry_props(fc.GetEntryWithIdx(i))
            fs = pr.get("FilterSet", cat)
            rec = by_set.setdefault(fs, {"n": 0, "ref": pr.get("Reference", ""), "scope": pr.get("Scope", ""),
                                         "examples": []})
            rec["n"] += 1
            if len(rec["examples"]) < 3 and pr.get("description"):
                rec["examples"].append(pr["description"])
    out = []
    for fs, rec in sorted(by_set.items()):
        canon, tier, verified = _LIABILITY_CANON.get(fs, (None, "T2", "unverifiable"))
        shipped = f"RDKit FilterCatalog FilterSet='{fs}'" + (f"; Scope='{rec['scope']}'" if rec["scope"] else "") \
                  + (f"; Reference={rec['ref']}" if rec["ref"] else "")
        ref = (canon + " | " + shipped) if canon else shipped
        out.append({
            "id": f"liability:{fs}",
            "statement": f"Structural-alert rule-set '{fs}': {rec['n']} published alerts for undesirable/"
                         f"interference substructures (e.g. {', '.join(rec['examples'][:2]) or 'see catalog'}). "
                         f"Any candidate matching an alert is flagged for medicinal-chemistry liability.",
            "n_alerts": rec["n"],
            "source": ref,
            "tier": tier,
            "verified": verified,
            "modality": "small_molecule",
        })
    return out


_SCREENER = None


def screen_liabilities(smiles: str) -> list[dict]:
    """LIVE screener: run the ingested RDKit catalogs over a SMILES, return matched alerts with per-alert
    provenance (description + FilterSet + canonical paper). This is the checker wired as an eval_criterion."""
    global _SCREENER
    try:
        from rdkit import Chem
        from rdkit.Chem import FilterCatalog
        from rdkit.Chem.FilterCatalog import FilterCatalogParams
    except Exception:
        return []
    if _SCREENER is None:
        p = FilterCatalogParams()
        for cat in _RDKIT_CATALOGS:
            enum = getattr(FilterCatalogParams.FilterCatalogs, cat, None)
            if enum is not None:
                p.AddCatalog(enum)
        _SCREENER = FilterCatalog.FilterCatalog(p)
    m = Chem.MolFromSmiles(smiles) if smiles else None
    if m is None:
        return []
    hits = []
    for match in _SCREENER.GetMatches(m):
        pr = _entry_props(match)
        fs = pr.get("FilterSet", "?")
        canon = _LIABILITY_CANON.get(fs, (None,))[0]
        hits.append({"alert": pr.get("description", match.GetDescription()), "rule_set": fs,
                     "source": canon or pr.get("Reference", fs)})
    return hits


# =============================================================================================
# DOMAIN 2 — METAL COORDINATION (encoded published tables; sources cited)
# Geometry / ligand preferences: Harding metal-geometry surveys (Acta Cryst D 1999;55:1432; 2001;57:401;
#   2006;62:678); MetalPDB (Putignano et al., Nucleic Acids Res 2018;46:D459); CheckMyMetal (Zheng et al.,
#   Acta Cryst D 2017;73:223). FF-treatment options: Li & Merz, "Metal Ion Modeling Using Classical
#   Mechanics", Chem Rev 2017;117:1564-1686 (nonbonded / bonded-MCPB / 12-6-4 comparison); MCPB.py
#   (Li & Merz, J Chem Inf Model 2016;56:599); 12-6-4 (Li, Song & Merz, JCTC 2015;11:1645); cationic-dummy
#   CaDA (Duarte et al., J Phys Chem B 2014;118:4351-4362 — octahedral Mn2+/Zn2+/Mg2+/Ca2+).
# =============================================================================================
_FF_CHEMREV = "Li & Merz, Chem Rev 2017;117:1564-1686 (metal-ion classical-mechanics modeling review)"
_FF_MCPB = "Li & Merz, J Chem Inf Model 2016;56:599 (MCPB.py bonded-model builder)"
_FF_1264 = "Li, Song & Merz, J Chem Theory Comput 2015;11:1645 (12-6-4 nonbonded)"
_FF_CADA = "Duarte et al., J Phys Chem B 2014;118:4351-4362 (cationic-dummy CaDA, octahedral)"
_GEOM = "Harding, Acta Cryst D 2006;62:678 + MetalPDB (Putignano et al., NAR 2018;46:D459) + CheckMyMetal (Zheng et al., Acta Cryst D 2017;73:223)"

METAL_COORDINATION = {
    "MG": {"geometry": "octahedral", "coordination_number": 6,
           "residue_prefs": ["Asp(O)", "Glu(O)", "backbone-carbonyl-O", "water", "phosphate-O"],
           "note": "hard cation; O-donors + water; the physiologic integrin-MIDAS cation.",
           "ff_options": [{"model": "nonbonded + 12-6-4", "source": _FF_1264, "verified": "unverifiable"},
                          {"model": "cationic-dummy (CaDA)", "source": _FF_CADA, "verified": True}],
           "source": _GEOM + "; " + _FF_CHEMREV, "tier": "T1", "verified": True},
    "MN": {"geometry": "octahedral", "coordination_number": 6,
           "residue_prefs": ["Asp(O)", "Glu(O)", "His(N)", "backbone-carbonyl-O", "water"],
           "note": "borderline cation; octahedral, tolerates His(N); the integrin-ACTIVATING cation used "
                   "experimentally at MIDAS (physiologic MIDAS metal is Mg2+).",
           "ff_options": [{"model": "cationic-dummy (CaDA)", "source": _FF_CADA, "verified": True},
                          {"model": "nonbonded + 12-6-4", "source": _FF_1264, "verified": "unverifiable"},
                          {"model": "bonded / MCPB.py", "source": _FF_MCPB, "verified": "unverifiable"}],
           "source": _GEOM + "; " + _FF_CADA, "tier": "T1", "verified": True},
    "ZN": {"geometry": "tetrahedral", "coordination_number": 4,
           "residue_prefs": ["His(N)", "Cys(S)", "Asp(O)", "Glu(O)", "water"],
           "note": "borderline-soft; catalytic Zn ~4-coord tetrahedral (His/Cys/Asp), can be 5-coord; "
                   "structural Zn Cys4/His-Cys.",
           "ff_options": [{"model": "bonded / MCPB.py", "source": _FF_MCPB, "verified": "unverifiable"},
                          {"model": "cationic-dummy", "source": "Pang, Proteins 2001;45:183; " + _FF_CADA, "verified": "unverifiable"},
                          {"model": "12-6-4 nonbonded", "source": _FF_1264, "verified": "unverifiable"}],
           "source": _GEOM, "tier": "T1", "verified": True},
    "CA": {"geometry": "variable (6-8; pentagonal-bipyramidal common)", "coordination_number": 7,
           "residue_prefs": ["Asp(O)", "Glu(O)", "backbone-carbonyl-O", "Asn/Gln(O)", "water"],
           "note": "hard cation, O-only, flexible high coordination; EF-hand / ADMIDAS.",
           "ff_options": [{"model": "nonbonded + 12-6-4", "source": _FF_1264, "verified": "unverifiable"}],
           "source": _GEOM, "tier": "T1", "verified": True},
    "FE": {"geometry": "octahedral", "coordination_number": 6,
           "residue_prefs": ["His(N)", "Cys(S)", "Asp(O)", "Glu(O)", "Tyr(O)", "porphyrin"],
           "note": "redox-active; heme vs non-heme; needs bonded/MCPB + ox-state-specific params.",
           "ff_options": [{"model": "bonded / MCPB.py", "source": _FF_MCPB, "verified": "unverifiable"}],
           "source": _GEOM, "tier": "T1", "verified": True},
    "CU": {"geometry": "variable (square-planar/tetragonal 4-6)", "coordination_number": 4,
           "residue_prefs": ["His(N)", "Cys(S)", "Met(S)", "Asp/Glu(O)"],
           "note": "soft; type-1/2/3 Cu; Jahn-Teller distortion for Cu(II).",
           "ff_options": [{"model": "bonded / MCPB.py", "source": _FF_MCPB, "verified": "unverifiable"}],
           "source": _GEOM, "tier": "T1", "verified": True},
    "NI": {"geometry": "octahedral", "coordination_number": 6,
           "residue_prefs": ["His(N)", "Cys(S)", "Asp/Glu(O)"],
           "note": "borderline; often octahedral; urease/hydrogenase.",
           "ff_options": [{"model": "bonded / MCPB.py", "source": _FF_MCPB, "verified": "unverifiable"}],
           "source": _GEOM, "tier": "T1", "verified": True},
}

# =============================================================================================
# DOMAIN 4 — PHARMACOPHORE by TARGET CLASS  (PARTIALLY-CURATED domain: no single clean DB -> curated
# from reviews WITH citations; flag honestly. A specific target is an instance of its class.)
# =============================================================================================
PHARMACOPHORE_CLASS = {
    "integrin-MIDAS": {
        "principle": "RGD-type integrins present an Asp carboxylate that coordinates the divalent metal at the "
                     "MIDAS of the beta I-domain; the Arg engages the alpha-subunit. Subtype SELECTIVITY is set "
                     "by the beta-subunit Specificity-Determining Loops (SDLs) and by residues C-terminal to RGD "
                     "(the RGDLxxL/I motif folding a one-turn helix into the beta6/beta8 pocket).",
        "requires": ["RGD", "Asp->MIDAS-metal coordination"],
        "selectivity_handle": "beta-subunit SDLs + RGD C-terminal motif (RGDLxxL/I for beta6/beta8)",
        "source": "Xiong et al., Science 2002;296:151 (alphaVbeta3-RGD, MIDAS); Dong, Hudson, Lu & Springer, "
                  "Nat Struct Mol Biol 2014;21:1091 (alphaVbeta6/beta8 RGDLxxL + SDL selectivity; PDB 4UM8/4UM9)",
        "tier": "T1", "verified": True},
    "ppi-groove": {
        "principle": "Protein-protein interfaces concentrate binding energy in a few HOT-SPOT residues; effective "
                     "inhibitors are hot-spot mimetics (alpha-helix mimetics/stapled peptides or macrocycles) "
                     "presenting the hot-spot side chains against a shallow groove. Sequence is necessary-not-"
                     "sufficient; a docked/structural pose is the decisive gate.",
        "requires": ["hot-spot side-chain mimicry", "conformational preorganization"],
        "selectivity_handle": "groove shape + hot-spot complementarity (structure-gated)",
        "source": "Clackson & Wells, Science 1995;267:383 (hot spots); Walensky & Bird, J Med Chem 2014;57:6275 "
                  "(stapled-peptide PPI inhibitors)",
        "tier": "T1", "verified": True},
    "protease": {
        "principle": "Engage the catalytic site across S4-S1/S1'-S2' subsites; optional electrophilic warhead "
                     "(reversible/covalent) to the catalytic nucleophile. Selectivity from subsite (esp. S1) fit.",
        "requires": ["catalytic-site engagement", "subsite (S1) fit", "optional warhead"],
        "selectivity_handle": "S1/S2 subsite specificity",
        "source": "Schechter & Berger subsite nomenclature, Biochem Biophys Res Commun 1967;27:157",
        "tier": "T1", "verified": "unverifiable"},
    "kinase": {
        "principle": "ATP-site inhibitors H-bond the hinge (1-3 contacts); type-I bind DFG-in, type-II reach the "
                     "DFG-out back pocket; selectivity from gatekeeper + back-pocket/allosteric contacts.",
        "requires": ["hinge H-bond", "gatekeeper/back-pocket fit"],
        "selectivity_handle": "gatekeeper residue + DFG-in/out + back pocket",
        "source": "Roskoski, Pharmacol Res 2016;103:26-48 (classification of small-molecule kinase inhibitors "
                  "by DFG/hinge binding mode: type-I DFG-in, type-II DFG-out)",
        "tier": "T1", "verified": True},
    "gpcr": {
        "principle": "Orthosteric vs allosteric engagement of the 7TM bundle (e.g. the conserved TM3 aspartate for "
                     "aminergic receptors); allosteric modulators offer subtype selectivity.",
        "requires": ["orthosteric/allosteric pocket engagement"],
        "selectivity_handle": "allosteric site + extracellular-loop contacts",
        "source": "Congreve, de Graaf, Swain & Tate, Cell 2020;181:81 (GPCR SBDD review)",
        "tier": "T1", "verified": "unverifiable"},
}

# =============================================================================================
# DOMAIN 3 — PHYSCHEM / ADMET (standard rule definitions + external predictors to call)
# =============================================================================================
PHYSCHEM = [
    {"id": "ro5", "statement": "Rule of 5 (oral small molecules): MW<=500, logP<=5, HBD<=5, HBA<=10.",
     "modality": "small_molecule", "source": "Lipinski et al., Adv Drug Deliv Rev 1997;23:3 (repr. 2001;46:3)",
     "tier": "T1", "verified": True},
    {"id": "veber", "statement": "Oral bioavailability: rotatable bonds<=10 and PSA<=140 A^2 (or HBD+HBA<=12).",
     "modality": "small_molecule", "source": "Veber et al., J Med Chem 2002;45:2615", "tier": "T1", "verified": True},
    {"id": "bro5", "statement": "Beyond-Rule-of-5 (macrocycles/peptides) occupy oral space outside Ro5; "
     "permeability/solubility must be engineered, not assumed.", "modality": "cyclic_peptide",
     "source": "Doak, Over, Giordanetto & Kihlberg, Chem Biol 2014;21:1115 ('Oral druggable space beyond Ro5')",
     "tier": "T1", "verified": True},
    {"id": "chameleon-permeability", "statement": "Macrocycle passive permeability is a CONFORMATIONAL "
     "('molecular chameleon') property: it tracks the ability to shield polar surface (intramolecular H-bonding, "
     "low 3D-PSA) in a membrane-mimetic vs aqueous environment; static 2D descriptors miss this.",
     "modality": "cyclic_peptide",
     "source": "Rezai et al., JACS 2006;128:14073 (chameleon/IMHB); Over et al., Nat Chem Biol 2016;12:1065 "
               "(bRo5 oral-drug physchem)", "tier": "T1", "verified": True},
    {"id": "external-admet-predictors", "statement": "For quantitative ADMET, call an external predictor and "
     "record provenance: SwissADME (physchem/BOILED-Egg absorption) and ADMETlab 2.0/3.0 (broad ADMET endpoints).",
     "modality": "small_molecule",
     "source": "Daina et al., Sci Rep 2017;7:42717 (SwissADME); Xiong et al., Nucleic Acids Res 2021;49:W5 (ADMETlab 2.0)",
     "tier": "T1", "verified": True},
]

# =============================================================================================
# DOMAIN 5 — MODALITY DESIGN HEURISTICS
# =============================================================================================
MODALITY_HEURISTICS = {
    "cyclic_peptide": [
        {"statement": "Macrocyclization (head-to-tail / disulfide / thioether) rigidifies the backbone, boosts "
         "affinity/selectivity via preorganization, and improves protease resistance.",
         "source": "Driggers, Hale, Lee & Terrett, Nat Rev Drug Discov 2008;7:608-624 (macrocycles in drug discovery)",
         "tier": "T1", "verified": True},
        {"statement": "Backbone N-methylation shields amide NH / promotes intramolecular H-bonds -> raises passive "
         "permeability, but can disrupt binding/geometry; a permeability<->binding tradeoff applied at exposed "
         "(non-interface) NH positions.",
         "source": "Biron, Chatterjee, Ovadia, ... Kessler, Angew Chem Int Ed 2008;47(14):2595-2599 "
                   "(oral bioavailability of peptides by multiple N-methylation)",
         "tier": "T1", "verified": True},
        {"statement": "D-amino acids / backbone modifications confer protease resistance and conformational control "
         "(e.g. D-Pro for beta-turn nucleation).",
         "source": "Chatterjee, Gilon, Hoffman & Kessler, Acc Chem Res 2008;41:1331 (N-methylation/D-aa peptidomimetics)",
         "tier": "T1", "verified": "unverifiable"},
    ],
    "stapled_peptide": [
        {"statement": "Hydrocarbon stapling locks an alpha-helix -> stabilizes the bioactive conformation, raising "
         "affinity, cell penetration, and protease resistance for helical PPI inhibitors.",
         "source": "Walensky & Bird, J Med Chem 2014;57:6275", "tier": "T1", "verified": True},
    ],
}

# =============================================================================================
# DATA SOURCES (where quantitative SAR / permeability come from — pointers, not re-ingested here)
# =============================================================================================
DATA_SOURCES = {
    "affinity": {"statement": "Measured Kd/Ki/IC50/EC50 for SAR come from ChEMBL + BindingDB, merged locally as "
                 "binding_affinity_v1 (28,875 clean cyclic-peptide affinities, incl. PD-L1 434 / αvβ6 227).",
                 "source": "Mendez et al., Nucleic Acids Res 2019;47:D930 (ChEMBL); Gilson et al., NAR 2016;44:D1045 "
                            "(BindingDB); local binding_affinity_v1", "tier": "T1", "verified": True},
    "permeability": {"statement": "Macrocyclic-peptide permeability (PAMPA/Caco-2) + chameleon 3D-PSA descriptors "
                     "come from CycPeptMPDB.", "source": "Li et al., J Chem Inf Model 2023;63:2240 (CycPeptMPDB)",
                     "tier": "T1", "verified": True},
}


# ---------------------------------------- LOOKUPS ----------------------------------------
def metal_rule(ion: Optional[str]) -> Optional[dict]:
    return METAL_COORDINATION.get(ion.upper()) if ion else None


def preferred_ff(ion: Optional[str]) -> Optional[dict]:
    r = metal_rule(ion)
    return r["ff_options"][0] if r and r.get("ff_options") else None


def pharmacophore_class_rule(target_class: Optional[str]) -> Optional[dict]:
    return PHARMACOPHORE_CLASS.get(target_class) if target_class else None


def physchem_for(modality: Optional[str]) -> list[dict]:
    out = []
    for e in PHYSCHEM:
        if e["modality"] == modality or (modality in (None, "small_molecule") and e["modality"] == "small_molecule"):
            out.append(e)
    return out


def modality_heuristics(modality: Optional[str]) -> list[dict]:
    return MODALITY_HEURISTICS.get(modality or "", [])


def domains() -> dict:
    lia = ingest_liability_catalogs()
    return {
        "liability": {"ingested_from": "RDKit FilterCatalog", "rule_sets": len(lia),
                      "total_alerts": sum(e["n_alerts"] for e in lia)},
        "metal_coordination": sorted(METAL_COORDINATION),
        "pharmacophore_class": {"classes": sorted(PHARMACOPHORE_CLASS), "status": "PARTIALLY-CURATED (no single DB)"},
        "physchem": [e["id"] for e in PHYSCHEM],
        "modality_heuristics": sorted(MODALITY_HEURISTICS),
        "data_sources": sorted(DATA_SOURCES),
    }


if __name__ == "__main__":
    import json
    print("GENERAL MED-CHEM KB domains:\n" + json.dumps(domains(), indent=2))
    lia = ingest_liability_catalogs()
    print(f"\nLIABILITY ingested: {len(lia)} rule-sets, {sum(e['n_alerts'] for e in lia)} alerts")
    for e in lia:
        print(f"  {e['id']:28} n={e['n_alerts']:4} verified={str(e['verified']):12} <- {e['source'][:66]}")
    print("\nscreen_liabilities('O=C(O)c1ccccc1N=Nc1ccccc1') ->",
          json.dumps(screen_liabilities("O=C(O)c1ccccc1N=Nc1ccccc1")[:3], indent=2))
