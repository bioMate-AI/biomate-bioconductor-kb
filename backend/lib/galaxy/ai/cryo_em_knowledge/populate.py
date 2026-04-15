"""
Populate cryo_em_protocols, cryo_em_parameters, cryo_em_tools tables.

Data distilled from:
  - docs/cryo_em_skills/00_GENERAL_FRAMEWORK.md
  - docs/cryo_em_skills/01_MFSD2B_preprint.md  (saposin nanodisc)
  - docs/cryo_em_skills/02_VMAT2_nature2023.md  (saposin nanodisc)
  - docs/cryo_em_skills/03_CaV1_2_cell2023.md   (detergent)
  - docs/cryo_em_skills/04_BAX_pore_science2025.md (liposome)
  - docs/cryo_em_skills/05_muOR_cell2022.md      (GPCR-Gi)
  - docs/cryo_em_skills/06_D1_PAM_preprint2025.md (GPCR-Gs)
  - docs/cryo_em_skills/07_spliceosome_multistate.md (RNP)
  - docs/cryo_em_skills/08_symmetric_assembly_capsid.md (capsid)

Running this script is idempotent (INSERT OR REPLACE).
"""

import json
import sqlite3
import sys

DB_PATH = "/home/yzhang/biomate/backend/galaxy_ai_tools.db"

# ─────────────────────────────────────────────────────────────────────────────
# PROTOCOLS — one entry per sample class
# ─────────────────────────────────────────────────────────────────────────────

PROTOCOLS = [
    {
        "sample_class": "saposin_nanodisc",
        "display_name": "Membrane Protein — Saposin Nanodisc (< 60 kDa)",
        "typical_mw_range_kda": "20-60",
        "reconstitution_type": "saposin",
        "collection_params": {
            "pixel_size_angstrom": 0.649,
            "defocus_min_um": -0.8,
            "defocus_max_um": -2.0,
            "total_dose_e_per_A2": 60,
            "frame_count": 50,
            "box_size_rule": "256 px at 0.649 A/pix for ~10 nm nanodisc",
            "magnification": 130000,
            "detector": "K3 counting mode"
        },
        "reconstitution_params": {
            "saposin_type": "Saposin A",
            "lipid_mix": "POPC:POPE:POPG = 3:1:1",
            "lipid_delivery": "0.5% gamma-cyclodextrin aqueous",
            "molar_ratio": "protein:saposin:lipid = 1:10:200",
            "detergent_removal": "SM-2 Bio-Beads, 4C overnight",
            "qc_criterion": "NS-EM round particles ~10 nm diameter",
            "nanodisc_size_nm": 10
        },
        "qc_gates": [
            {"name": "NS-EM nanodisc size", "criterion": "round ~10 nm", "action_if_fail": "redo reconstitution with fresh saposin"},
            {"name": "SEC peak", "criterion": "single symmetric peak", "action_if_fail": "re-purify"},
            {"name": "CTF resolution", "criterion": "< 4.5 A", "action_if_fail": "discard micrograph"},
            {"name": "2D class quality", "criterion": "TM helices visible in top classes", "action_if_fail": "repick, adjust box size"},
            {"name": "FSC", "criterion": "0.143 crossing visible", "action_if_fail": "collect more particles"},
            {"name": "MolProbity", "criterion": "< 1.5", "action_if_fail": "rebuild in Coot"}
        ],
        "picking_strategy": {
            "round1": "crYOLO general model (confidence 0.3)",
            "round2": "Template picker after 2D classification",
            "round3": "TOPAZ trained on project particles (500 manually curated)",
            "box_size_px": 256,
            "expected_picks_per_mic": "100-200",
            "training_needed": True,
            "reason": "Nanodisc shape requires trained picker for high recall"
        },
        "refinement_strategy": {
            "symmetry": "C1",
            "ctf_refinement": "per-particle defocus + beam tilt + trefoil",
            "local_refinement": "focus mask on TM core",
            "expected_resolution_A": "2.7-3.5"
        },
        "model_building": {
            "template_source": "AlphaFold2 prediction (UniProt ID)",
            "pipeline": "AF2 rigid dock -> Coot loop fix -> PHENIX real_space_refine",
            "ligand_handling": "eLBOW CIF for any small molecule, place in Coot",
            "validation": "MolProbity < 1.5, Ramachandran > 97%"
        },
        "use_cases": [
            "Small membrane transporter structure (< 60 kDa TM core)",
            "Lipid transporter mechanism (e.g. S1P, LPCs)",
            "MFS family transporter drug binding",
            "Comparing outward-open vs inward-open conformations"
        ],
        "limitations": [
            "Saposin nanodisc harder to prepare than MSP — requires saposin A expression and refolding",
            "0.649 A/pix requires higher magnification, fewer movies per session",
            "Small particles difficult to pick accurately without TOPAZ training",
            "Resolution ceiling ~2.5 A for < 30 kDa TM cores"
        ],
        "key_principles": [
            "Saposin outperforms MSP for < 60 kDa membrane proteins — wraps tightly, less background",
            "gamma-cyclodextrin enables detergent-free lipid delivery for saposin assembly",
            "0.649 A/pix is mandatory below 80 kDa — 0.83 A/pix undersamplines the particle",
            "TOPAZ training on project-specific particles improves recall 20-40% over general model",
            "NS-EM QC is a hard gate before cryo-EM — round 10 nm particles required",
            "Three-picker strategy (blob + template + TOPAZ) is best practice for nanodisc samples"
        ],
        "tool_requirements": [
            {"tool": "crYOLO", "step": "particle_picking_round1", "status": "have"},
            {"tool": "TOPAZ", "step": "particle_picking_round3", "status": "partial", "note": "general model only, training needed"},
            {"tool": "CryoSPARC", "step": "2D_3D_refine", "status": "have"},
            {"tool": "PHENIX", "step": "real_space_refine", "status": "have"},
            {"tool": "AlphaFold2", "step": "initial_model", "status": "have"},
            {"tool": "Coot", "step": "model_building", "status": "missing"},
            {"tool": "DeepEMhancer", "step": "post_processing", "status": "partial", "note": "Docker built, not in pipeline"}
        ],
        "reference_papers": [
            {"title": "MFSD2B S1P transporter", "journal": "bioRxiv", "year": 2026, "doi": "10.64898/..."},
            {"title": "VMAT2 dual-mechanism inhibition", "journal": "Nature", "year": 2023, "doi": "10.1038/s41586-023-06328-6"}
        ]
    },

    {
        "sample_class": "msp_nanodisc_gpcr",
        "display_name": "GPCR — G Protein Complex in MSP Nanodisc",
        "typical_mw_range_kda": "100-150",
        "reconstitution_type": "msp",
        "collection_params": {
            "pixel_size_angstrom": 0.83,
            "defocus_min_um": -0.8,
            "defocus_max_um": -2.0,
            "total_dose_e_per_A2": 50,
            "frame_count": 50,
            "box_size_rule": "320 px at 0.83 A/pix for ~120 kDa complex",
            "note": "Tighter defocus range than large complexes — small particle"
        },
        "reconstitution_params": {
            "msp_type": "MSP1D1DeltaH5 (smaller disc for GPCRs)",
            "lipid_mix": "POPC:POPG:POPE = 3:1:1",
            "stabilizer": "scFv16 (Gi) or Nb35/scFv16 (Gs)",
            "nucleotide_removal": "apyrase 0.02 U/mL, 2hr 25C",
            "assembly_order": ["nanodisc_reconstitution", "agonist_addition", "G_protein_coupling", "apyrase", "scFv16", "SEC"],
            "qc_criterion": "NS-EM round ~12-14 nm particles, SDS-PAGE 4 bands"
        },
        "qc_gates": [
            {"name": "NS-EM particle size", "criterion": "round ~12-14 nm", "action_if_fail": "reassemble complex, check apyrase"},
            {"name": "SDS-PAGE", "criterion": "4 bands (GPCR, Ga, Gb, scFv16)", "action_if_fail": "adjust component ratios"},
            {"name": "Functional assay", "criterion": "BRET or cAMP EC50 confirms agonist activity", "action_if_fail": "re-confirm agonist concentration"},
            {"name": "2D class quality", "criterion": "TM helices + G protein density visible", "action_if_fail": "more classification rounds"},
            {"name": "CTF resolution", "criterion": "< 4.5 A", "action_if_fail": "discard micrograph"},
            {"name": "Local refine TM core", "criterion": "< 3.0 A after focused refinement", "action_if_fail": "more particles"}
        ],
        "picking_strategy": {
            "round1": "crYOLO general model",
            "round2": "TOPAZ trained on project nanodisc-GPCR particles",
            "box_size_px": 320,
            "training_needed": True,
            "note": "GPCR-Gi in nanodisc looks similar to membrane transporter nanodisc"
        },
        "refinement_strategy": {
            "symmetry": "C1",
            "ctf_refinement": "per-particle defocus + beam tilt (CRITICAL for GPCR)",
            "local_refinement": "two masks: (1) TM core, (2) G protein ras domain",
            "expected_resolution_TM_A": "2.7-3.0",
            "expected_resolution_Gprotein_A": "3.2-4.0",
            "note": "Report both resolutions separately"
        },
        "model_building": {
            "template_source": "GPCR: known crystal structure or AF2; G protein: PDB 6CMO or similar",
            "pipeline": "rigid dock each subunit -> Coot loop fix -> PHENIX with NCS restraints",
            "ligand_handling": "eLBOW CIF for agonist/drug, place in Coot, check occupancy > 0.7",
            "key_analysis": "TM6 displacement vs inactive reference, Ga5 helix engagement angle"
        },
        "use_cases": [
            "Agonist/antagonist mechanism for any class A GPCR",
            "Biased agonism structural basis (morphine vs fentanyl type studies)",
            "Multi-PAM cooperativity on GPCR",
            "Gs vs Gi coupling comparison for same receptor"
        ],
        "limitations": [
            "Complex assembly takes 3-5 days — most time-consuming sample type",
            "scFv16 must be expressed separately in E. coli Origami2",
            "Apyrase step is critical — omitting it collapses complex yield 10x",
            "G protein ras domain resolution always lower than TM core — inherent flexibility",
            "BRET/cAMP functional validation required before cryo-EM session"
        ],
        "key_principles": [
            "MSP1D1DeltaH5 (not MSP1D1) — smaller disc reduces lipid flexibility for GPCRs",
            "scFv16 is mandatory stabilizer for Gi-coupled GPCRs — without it complex yield drops 10x",
            "Apyrase removes GDP from Ga — nucleotide-free state required for stable ternary complex",
            "Assembly must be stepwise: nanodisc first, then agonist, then G protein, then scFv16",
            "NS-EM is a hard gate: round 12-14 nm particles required before cryo-EM",
            "Always report two resolutions: TM core and G protein domain separately",
            "TM6 outward displacement > 10 A = active state; > 12 A = full agonist",
            "Ballesteros-Weinstein numbering enables cross-GPCR comparison"
        ],
        "tool_requirements": [
            {"tool": "crYOLO", "step": "picking_round1", "status": "have"},
            {"tool": "TOPAZ", "step": "picking_round2", "status": "partial", "note": "training needed"},
            {"tool": "CryoSPARC", "step": "2D_3D_local_refine", "status": "have"},
            {"tool": "PHENIX", "step": "real_space_refine", "status": "have"},
            {"tool": "Coot", "step": "model_building", "status": "missing"},
            {"tool": "scFv16", "step": "sample_prep_stabilizer", "status": "missing", "note": "user must express"},
            {"tool": "apyrase", "step": "sample_prep_nucleotide_removal", "status": "missing", "note": "user protocol"}
        ],
        "reference_papers": [
            {"title": "mu-OR Gi complex morphine/fentanyl", "journal": "Cell", "year": 2022, "doi": "10.1016/j.cell.2022.06.017"},
            {"title": "D1R multi-PAM cooperativity", "journal": "bioRxiv", "year": 2025, "doi": "10.1101/2025"}
        ]
    },

    {
        "sample_class": "detergent_ion_channel",
        "display_name": "Membrane Ion Channel — Detergent (> 200 kDa Complex)",
        "typical_mw_range_kda": "200-600",
        "reconstitution_type": "detergent",
        "collection_params": {
            "pixel_size_angstrom": 0.83,
            "defocus_min_um": -1.0,
            "defocus_max_um": -2.5,
            "total_dose_e_per_A2": 50,
            "frame_count": 50,
            "box_size_rule": "320-400 px at 0.83 A/pix; use 400 px for > 400 kDa",
            "preferred_detergent": "GDN (glyco-diosgenin) 0.02% — mild, monodisperse"
        },
        "reconstitution_params": {
            "detergent": "GDN 0.02% or DDM 0.02% + CHS 0.004%",
            "purification": "FLAG/His affinity -> SEC Superose 6",
            "drug_addition": "10-100 uM, DMSO < 1%, 30-60 min on ice before grid",
            "qc_criterion": "Single SEC peak, SDS-PAGE bands for all subunits"
        },
        "qc_gates": [
            {"name": "SEC peak", "criterion": "single symmetric, correct MW", "action_if_fail": "re-purify, check detergent"},
            {"name": "CTF resolution", "criterion": "< 4.5 A", "action_if_fail": "discard micrograph"},
            {"name": "2D class quality", "criterion": "TM topology visible in top classes", "action_if_fail": "more picks or new grid"},
            {"name": "Preferred orientation check", "criterion": "< 60% in any one 2D class", "action_if_fail": "add 0.05% OG, tilt stage 30 degrees"},
            {"name": "Drug density", "criterion": "> 4 sigma in difference map", "action_if_fail": "increase drug concentration or occupancy time"}
        ],
        "picking_strategy": {
            "round1": "crYOLO general model",
            "round2": "Template picker from first dataset (use for all subsequent drug conditions)",
            "box_size_px": 320,
            "training_needed": False,
            "multi_condition_note": "Train template on first dataset, apply to all drug conditions for consistency"
        },
        "refinement_strategy": {
            "symmetry": "C1 default; check 2D classes for symmetry before applying",
            "ctf_refinement": "per-particle defocus + beam tilt",
            "local_refinement": "TM core separately for drug binding analysis",
            "3dva": "Recommended for ion channels — multiple gating states coexist",
            "expected_resolution_A": "2.6-3.2"
        },
        "model_building": {
            "template_source": "Known crystal structure of same family (e.g. CaV1.1 for CaV1.2) or AF2",
            "pipeline": "rigid dock -> Coot -> PHENIX; eLBOW for each drug ligand",
            "drug_comparison": "Superpose both structures on TM1-3; calculate difference map; measure TM displacement",
            "multi_drug_note": "Collect apo reference first; all drug datasets vs same apo for difference maps"
        },
        "use_cases": [
            "Multi-drug pharmacology atlas (N drugs + 1 apo reference)",
            "Ion channel gating mechanism",
            "Drug binding site identification and comparison",
            "Voltage-gated channel state-dependent drug access (use-dependence mechanism)"
        ],
        "limitations": [
            "GDN is expensive (~$500/g) but required for stability",
            "Large complexes (> 400 kDa) need deep defocus; more particles for same resolution",
            "Drug difference maps require identical processing parameters for apo and drug datasets",
            "Preferred orientation common for channels — requires stage tilt or detergent optimization"
        ],
        "key_principles": [
            "GDN preserves lipid annulus better than DDM for > 200 kDa ion channel complexes",
            "Multi-drug atlas: collect apo reference + N drug datasets with identical parameters",
            "Drug difference map: normalize both maps to same scale before subtracting",
            "Template picking from dataset 1 applied to all subsequent conditions ensures consistency",
            "3DVA before final refinement — ion channels have multiple gating states in one sample",
            "Drug density must be at > 4 sigma in difference map to be reliably placed",
            "Fenestration drug access: blockers enter laterally through TM helix fenestrations when channel opens"
        ],
        "tool_requirements": [
            {"tool": "CryoSPARC", "step": "2D_3D_refine_3DVA", "status": "have"},
            {"tool": "crYOLO", "step": "picking", "status": "have"},
            {"tool": "PHENIX", "step": "real_space_refine", "status": "have"},
            {"tool": "Coot", "step": "model_building", "status": "missing"},
            {"tool": "drug_difference_map", "step": "drug_analysis", "status": "have", "note": "scripts/drug_difference_map.py"}
        ],
        "reference_papers": [
            {"title": "CaV1.2 structural pharmacology", "journal": "Cell", "year": 2023, "doi": "10.1016/j.cell.2023.08.002"}
        ]
    },

    {
        "sample_class": "liposome_pore_forming",
        "display_name": "Pore-Forming Protein — Liposome Reconstitution",
        "typical_mw_range_kda": "100-500",
        "reconstitution_type": "liposome",
        "collection_params": {
            "pixel_size_angstrom": 0.83,
            "defocus_min_um": -1.0,
            "defocus_max_um": -2.5,
            "total_dose_e_per_A2": 50,
            "frame_count": 50,
            "box_size_rule": "400 px at 0.83 A/pix for arc/ring shape",
            "spa_path": "DDM extract pore from liposomes then standard SPA",
            "cryo_et_path": "Direct vitrification of liposomes, 1.37 A/pix"
        },
        "reconstitution_params": {
            "lipid_mix_omm": "DOPC:DOPE:CL = 4:3:1 (OMM mimic for BAX)",
            "lipid_mix_pm": "DOPC:DOPE:Chol = 2:1:1 (PM mimic)",
            "suv_preparation": "Dry lipid film -> hydrate -> freeze-thaw 10x -> extrude 100nm membrane",
            "suv_qc": "DLS: PDI < 0.1, size 90-110 nm",
            "pore_activation": "protein + activator (e.g. cBID) + liposomes, 37C 30-60min",
            "functional_validation": "ANTS/DPX lysis assay > 50% required before cryo-EM",
            "ddm_extraction": "1% DDM 30min 4C -> SEC -> collect pore fraction"
        },
        "qc_gates": [
            {"name": "Liposome size", "criterion": "DLS PDI < 0.1, 90-110 nm", "action_if_fail": "re-extrude with fresh membrane"},
            {"name": "Lysis assay ANTS/DPX", "criterion": "> 50% lysis vs Triton control", "action_if_fail": "STOP — pore not formed, do not proceed to cryo-EM"},
            {"name": "NS-EM of extracted pore", "criterion": "ring/arc structures visible", "action_if_fail": "DDM extraction failed, try higher DDM or longer time"},
            {"name": "2D classes", "criterion": "arc/ring shapes visible", "action_if_fail": "TOPAZ training on arc-shaped particles mandatory"},
            {"name": "Oligomeric state", "criterion": "consistent ring/arc size (e.g. octamer)", "action_if_fail": "3D classify to separate assembly states"}
        ],
        "picking_strategy": {
            "round1": "blob picker (initial, many false positives for arcs)",
            "round2": "TOPAZ trained on confirmed arc-shaped 2D classes",
            "box_size_px": 400,
            "training_needed": True,
            "reason": "Arc/crescent shape not handled by circular blob picker — TOPAZ mandatory"
        },
        "refinement_strategy": {
            "symmetry": "C1 (pore arc is asymmetric)",
            "multi_body": "Recommended: 4 rigid bodies (one per dimer) for BAX-type octamers",
            "expected_resolution_global_A": "3.0-3.5",
            "expected_resolution_per_dimer_A": "2.7-3.0 after local refine"
        },
        "model_building": {
            "template_source": "Monomer PDB structure (e.g. BAX PDB 1F16)",
            "pipeline": "dock N copies -> NCS restraints -> PHENIX; ISOLDE for clash resolution in oligomers",
            "validation": "PISA buried surface per dimer interface; MolProbity < 2.0"
        },
        "use_cases": [
            "Apoptotic pore structure (BAX, BCLX)",
            "Gasdermin pore (pyroptosis)",
            "MLKL pore (necroptosis)",
            "Perforin/granzyme pore (immune)",
            "Any protein that inserts into membranes upon activation"
        ],
        "limitations": [
            "Functional validation (lysis assay) is mandatory — structural study of inactive protein is invalid",
            "Arc/crescent shapes require TOPAZ training — standard blob picker misses most particles",
            "DDM extraction changes native pore environment — cryo-ET on liposomes recommended as companion",
            "Oligomeric assembly state heterogeneous — expect multiple 3D classes (monomer, dimer, pore)"
        ],
        "key_principles": [
            "Lysis assay > 50% is a hard gate — NEVER proceed to cryo-EM without functional confirmation",
            "Cardiolipin is obligatory for BAX-family pores — OMM lipid composition required",
            "TOPAZ training on arc-shaped particles is mandatory — blob picker systematically misses arcs",
            "Two EM approaches: SPA (atomic resolution) + cryo-ET (native context) — both recommended",
            "RELION 3D multi-body: divide pore into N dimers as rigid bodies for better resolution",
            "ISOLDE resolves steric clashes in oligomers more efficiently than manual Coot editing"
        ],
        "tool_requirements": [
            {"tool": "TOPAZ", "step": "picking", "status": "partial", "note": "training required on arc particles"},
            {"tool": "CryoSPARC", "step": "2D_3D", "status": "have"},
            {"tool": "RELION_multibody", "step": "multi_body_refine", "status": "partial", "note": "RELION available but multi-body guidance missing"},
            {"tool": "ISOLDE", "step": "model_building_oligomer", "status": "missing"},
            {"tool": "PHENIX", "step": "real_space_refine_NCS", "status": "have"},
            {"tool": "cryo_et_full_pipeline", "step": "in_liposome_context", "status": "have"}
        ],
        "reference_papers": [
            {"title": "BAX pore formation", "journal": "Science", "year": 2025}
        ]
    },

    {
        "sample_class": "rna_protein_endogenous",
        "display_name": "Large RNA-Protein Complex — Endogenous Purification",
        "typical_mw_range_kda": "500-2000",
        "reconstitution_type": "endogenous",
        "collection_params": {
            "pixel_size_angstrom": 1.06,
            "defocus_min_um": -1.5,
            "defocus_max_um": -3.0,
            "total_dose_e_per_A2": 45,
            "frame_count": 50,
            "box_size_rule": "400-512 px at 1.06 A/pix for > 500 kDa complex"
        },
        "reconstitution_params": {
            "source": "HeLa S3 nuclear extract (50L suspension culture) or equivalent",
            "stalling_method": "Target-specific inhibitors or helicase addition",
            "fractionation": "10-30% linear glycerol gradient, 200000xg, 12-16hr SW40Ti",
            "fractions": "0.5 mL per fraction, ~24 total; spliceosome at ~40-50S",
            "detection": "dot blot anti-SmB antibody or equivalent spliceosomal marker",
            "qc_criterion": "silver stain shows complex band pattern (>50 subunits); Northern blot verifies snRNAs"
        },
        "qc_gates": [
            {"name": "Glycerol gradient fraction", "criterion": "target complex peaks at expected S value", "action_if_fail": "re-centrifuge, check inhibitor concentration"},
            {"name": "Silver stain", "criterion": "multiple bands visible (>10 for spliceosome)", "action_if_fail": "re-fraction, check cell culture"},
            {"name": "Northern blot snRNAs", "criterion": "U2/U5/U6 bands present", "action_if_fail": "complex not assembled, re-stall"},
            {"name": "NS-EM", "criterion": "irregular ~20-30 nm particles visible", "action_if_fail": "concentration issue"},
            {"name": "2D class quality", "criterion": "multiple distinct 2D classes (heterogeneous expected)", "action_if_fail": "more particles, deeper classification"}
        ],
        "picking_strategy": {
            "round1": "crYOLO general model (large box)",
            "round2": "Template from first 3D class",
            "box_size_px": 512,
            "training_needed": False,
            "note": "Large particle easy to pick; challenge is sorting states, not picking"
        },
        "refinement_strategy": {
            "symmetry": "C1",
            "classification_depth": "8-12 classes in round1; 3DVA on intact complex; K-means cluster along components",
            "multi_body": "3-6 rigid bodies (e.g. U1/U2/U4-U6/U5 snRNPs for spliceosome)",
            "expected_resolution_per_state_A": "3.5-5.0",
            "note": "Resolution limited by conformational averaging, not particle count"
        },
        "model_building": {
            "template_source": "Known crystal structures of each module (snRNPs, RNA helicases) from PDB",
            "pipeline": "Dock each module independently -> RNA fit with ERRASER -> PHENIX with RNA restraints",
            "note": "Do not use AF2 for entire complex — too many chains; use per-domain AF2 only for novel subunits"
        },
        "use_cases": [
            "Spliceosome assembly intermediates (B, Bact, B*, C complexes)",
            "Ribosome biogenesis factors",
            "Exosome and RNA surveillance complexes",
            "Nuclear pore complex subcomplex structures"
        ],
        "limitations": [
            "50L HeLa culture required — major cell biology resource commitment",
            "Resolution capped at 3.5-5 A by conformational heterogeneity",
            "Each state requires separate 3D classification — one dataset yields multiple papers",
            "RNA density interpretation requires specialist knowledge (ERRASER)"
        ],
        "key_principles": [
            "Glycerol gradient replaces affinity column — enriches by size + shape, not tag",
            "One dataset yields 5-6 simultaneous structures via multi-state classification",
            "3DVA is the primary tool — more value than collecting more data",
            "Resolution expectation must be recalibrated: 3.5-5 A is world-class for > 500 kDa flexible complex",
            "Stalling at a defined state is essential — inhibitor or helicase addition required"
        ],
        "tool_requirements": [
            {"tool": "CryoSPARC_3DVA", "step": "multi_state_classification", "status": "have"},
            {"tool": "RELION_multibody", "step": "flexible_module_refine", "status": "partial"},
            {"tool": "PHENIX_RNA", "step": "RNA_restraints", "status": "partial", "note": "ERRASER not integrated"},
            {"tool": "Coot", "step": "model_building", "status": "missing"}
        ],
        "reference_papers": [
            {"title": "Spliceosome activation B to Bact", "journal": "Nature Communications", "year": 2024, "doi": "10.1038/s41467-024-50785-0"}
        ]
    },

    {
        "sample_class": "symmetric_assembly",
        "display_name": "Symmetric Assembly — Viral Capsid / Ring ATPase",
        "typical_mw_range_kda": "1000-100000",
        "reconstitution_type": "none",
        "collection_params": {
            "pixel_size_angstrom": 0.83,
            "defocus_min_um": -0.5,
            "defocus_max_um": -2.0,
            "total_dose_e_per_A2": 60,
            "frame_count": 50,
            "box_size_rule": "box = particle diameter x 1.5 / pixel_size",
            "note": "Higher dose OK — stable assemblies tolerate 60 e/A2"
        },
        "reconstitution_params": {
            "source": "recombinant (E. coli or Sf9) or native cell isolation",
            "native_isolation": "cells -> freeze-thaw x3 -> 100000xg 2hr pellet -> sucrose gradient",
            "qc_criterion": "DLS ~32 nm for T=4 HBV; NS-EM shows ring structures"
        },
        "qc_gates": [
            {"name": "DLS size", "criterion": "monodisperse, expected diameter", "action_if_fail": "re-purify"},
            {"name": "NS-EM", "criterion": "ring/icosahedral particles visible", "action_if_fail": "concentration issue"},
            {"name": "2D class symmetry", "criterion": "5-fold, 3-fold, 2-fold views all present", "action_if_fail": "preferred orientation — add OG or tilt stage"},
            {"name": "C1 ab initio", "criterion": "symmetric-looking structure before imposing symmetry", "action_if_fail": "do NOT impose wrong symmetry"},
            {"name": "FSC gain on symmetry", "criterion": "> 0.5 A improvement vs C1", "action_if_fail": "wrong symmetry assigned"}
        ],
        "picking_strategy": {
            "round1": "crYOLO or blob picker (large, easy to pick)",
            "box_size_rule": "box = particle_diameter_A * 1.5 / pixel_size",
            "training_needed": False,
            "note": "Preferred orientation is main challenge, not picking"
        },
        "refinement_strategy": {
            "symmetry": "Determine from 2D classes before imposing (I1/O/T/D/C)",
            "symmetry_expansion": "For asymmetric internal cargo: expand by symmetry -> signal subtract shell -> focused 3D classify",
            "expected_resolution_A": "2.5-3.5 for capsid shell",
            "effective_particle_boost": "T=4 capsid: each particle = 240x effective views after I1"
        },
        "model_building": {
            "template_source": "Monomer from PDB or AF2",
            "pipeline": "Dock monomer into ASU -> expand by NCS -> refine ASU only",
            "asymmetric_unit": "ASU = 1/symmetry_order of full assembly",
            "internal_cargo": "Difference map inside shell for lipid/DNA/RNA identification"
        },
        "use_cases": [
            "Viral capsid structure (HBV, AAV, phage)",
            "Ring ATPase mechanism (AAA+ family)",
            "Proteasome conformational states",
            "Symmetric enzyme complexes"
        ],
        "limitations": [
            "Preferred orientation kills resolution for symmetric particles — must actively counter",
            "Asymmetric features (portal, packaged genome) destroyed by symmetry averaging",
            "Native cell-isolated capsids have PTM heterogeneity limiting resolution"
        ],
        "key_principles": [
            "Always start C1 — verify symmetry from 2D classes before imposing",
            "Symmetry expansion x N gives effectively N-fold more particles — very resolution-efficient",
            "Asymmetric features require symmetry expansion + signal subtraction + focused 3D classify",
            "Preferred orientation: add 0.1% OG or tilt stage 30 degrees if > 60% in one 2D class"
        ],
        "tool_requirements": [
            {"tool": "CryoSPARC_symex", "step": "symmetry_expansion", "status": "have"},
            {"tool": "CryoSPARC", "step": "2D_3D_refine", "status": "have"},
            {"tool": "PHENIX_NCS", "step": "ASU_refine", "status": "have"},
            {"tool": "Coot", "step": "model_building", "status": "missing"}
        ],
        "reference_papers": [
            {"title": "HBV capsids from human cells", "journal": "Structure", "year": 2026, "doi": "10.1016/j.str.2025.11.005"}
        ]
    }
]


# ─────────────────────────────────────────────────────────────────────────────
# FLAT PARAMETER LOOKUP TABLE
# Query: SELECT value FROM cryo_em_parameters WHERE context=? AND parameter=?
# ─────────────────────────────────────────────────────────────────────────────

PARAMETERS = [
    # MW-based pixel size rules
    ("mw_lt50",      "pixel_size_angstrom",  "0.649",    "angstrom",  "< 50 kDa needs high sampling"),
    ("mw_50_100",    "pixel_size_angstrom",  "0.649",    "angstrom",  "< 100 kDa still benefits from 0.649"),
    ("mw_100_300",   "pixel_size_angstrom",  "0.83",     "angstrom",  "Standard range"),
    ("mw_300_600",   "pixel_size_angstrom",  "0.83",     "angstrom",  "Standard range"),
    ("mw_600_1500",  "pixel_size_angstrom",  "1.06",     "angstrom",  "Large complex, lower mag"),
    ("mw_gt1500",    "pixel_size_angstrom",  "1.30",     "angstrom",  "Very large, viral/cellular scale"),

    # Box size rules
    ("mw_50_100",    "box_size_px",          "256",      "pixels",    "at 0.649 A/pix for ~10 nm particle"),
    ("mw_100_300",   "box_size_px",          "256",      "pixels",    "at 0.83 A/pix"),
    ("mw_300_600",   "box_size_px",          "320",      "pixels",    "at 0.83 A/pix for ~15 nm"),
    ("mw_600_1500",  "box_size_px",          "400",      "pixels",    "at 1.06 A/pix"),

    # Defocus ranges
    ("mw_lt300",     "defocus_min_um",       "-0.8",     "um",        "Tight range for small particles"),
    ("mw_lt300",     "defocus_max_um",       "-2.0",     "um",        ""),
    ("mw_300_600",   "defocus_min_um",       "-1.0",     "um",        ""),
    ("mw_300_600",   "defocus_max_um",       "-2.5",     "um",        ""),
    ("mw_gt600",     "defocus_min_um",       "-1.5",     "um",        "Deeper defocus for large complex"),
    ("mw_gt600",     "defocus_max_um",       "-3.0",     "um",        ""),

    # Total dose
    ("standard",         "total_dose_e_per_A2",  "50",   "e/A2",      "Standard for most samples"),
    ("saposin_nanodisc", "total_dose_e_per_A2",  "60",   "e/A2",      "Small particle — more dose"),
    ("cryo_et",          "total_dose_e_per_A2",  "120",  "e/A2",      "Split across ~41 tilts"),
    ("radiation_sensitive", "total_dose_e_per_A2", "40", "e/A2",      "Reduce for sensitive samples"),

    # Sample-type pixel sizes
    ("saposin_nanodisc",  "pixel_size_angstrom", "0.649", "angstrom", "Small particle mandatory"),
    ("gpcr_complex",      "pixel_size_angstrom", "0.83",  "angstrom", "Standard for ~120 kDa complex"),
    ("ion_channel_gdn",   "pixel_size_angstrom", "0.83",  "angstrom", "Standard for 200-600 kDa"),
    ("liposome_pore",     "pixel_size_angstrom", "0.83",  "angstrom", "Standard SPA after DDM extract"),
    ("rna_protein",       "pixel_size_angstrom", "1.06",  "angstrom", "Large complex > 500 kDa"),
    ("cryo_et",           "pixel_size_angstrom", "1.37",  "angstrom", "Tilt series, lower magnification"),

    # Particle count targets
    ("target_lt3A",   "min_particles",   "200000",  "count",  "> 200K for < 3 A"),
    ("target_3_3p5A", "min_particles",   "50000",   "count",  "50K-200K for 3-3.5 A"),
    ("target_3p5_4A", "min_particles",   "20000",   "count",  "20K-50K for 3.5-4 A"),
    ("target_4_5A",   "min_particles",   "5000",    "count",  "5K-20K for 4-5 A"),
    ("symmetric_T4",  "effective_particles_multiplier", "240", "x", "T=4 capsid: 240x after I1"),

    # QC thresholds (universal)
    ("universal",  "fsc_criterion",              "0.143", "",       "Gold-standard, always"),
    ("universal",  "molprobity_max",             "2.0",   "",       "< 2.0 required; < 1.5 excellent"),
    ("universal",  "ramachandran_favored_min",   "97",    "percent", "< 95% requires explanation"),
    ("universal",  "ctf_fom_min",                "0.1",   "",       "Discard micrographs below"),
    ("universal",  "ctf_resolution_max_A",       "4.5",   "angstrom", "Discard if worse"),
    ("universal",  "motion_total_max_A",         "50",    "angstrom", "Discard if more"),
    ("universal",  "2d_class_min_fraction",      "60",    "percent",  "Of picks should show secondary structure"),

    # Drug/ligand analysis
    ("drug_binding",   "difference_map_threshold_sigma", "3.0", "sigma", "Min for reliable drug density"),
    ("drug_binding",   "ligand_density_min_sigma",       "4.0", "sigma", "Min for ligand placement"),
    ("drug_binding",   "occupancy_min",                  "0.7", "",      "< 0.7 = uncertain occupancy"),
    ("drug_binding",   "drug_contact_distance_A",        "4.0", "angstrom", "Residues within = binding site"),

    # Reconstitution
    ("saposin_nanodisc",   "lipid_molar_ratio",        "POPC:POPE:POPG 3:1:1", "",  "Typical for membrane transporters"),
    ("saposin_nanodisc",   "protein_saposin_lipid_ratio", "1:10:200",          "",  "Molar ratio for reconstitution"),
    ("msp_gpcr",           "lipid_molar_ratio",        "POPC:POPG:POPE 3:1:1",  "", "GPCR nanodisc"),
    ("omm_liposome",       "lipid_molar_ratio",        "DOPC:DOPE:CL 4:3:1",   "", "OMM mimic for BAX"),
    ("suv_extrusion",      "pore_size_nm",             "100",  "nm",   "Standard extrusion for ~100nm SUV"),
    ("suv_qc",             "pdi_max",                  "0.1",  "",     "DLS polydispersity index"),
    ("suv_qc",             "size_min_nm",              "90",   "nm",   "Lower bound"),
    ("suv_qc",             "size_max_nm",              "110",  "nm",   "Upper bound"),
]


# ─────────────────────────────────────────────────────────────────────────────
# TOOLS TABLE
# ─────────────────────────────────────────────────────────────────────────────

TOOLS = [
    {
        "tool_name": "CryoSPARC",
        "tool_category": "full_spa_pipeline",
        "biomate_status": "have",
        "container_image": None,
        "version": "v5",
        "use_when": ["SPA pipeline", "2D classification", "ab initio reconstruction", "homogeneous refinement", "non-uniform refinement", "3DVA", "local refinement", "CTF refinement", "local resolution"],
        "key_parameters": {"symmetry": "C1 default", "ctf_refine_depth": "per-particle + beam tilt + trefoil for < 3A", "non_uniform": "recommended over homogeneous for final map"},
        "alternatives": ["RELION"],
        "biomate_gap_notes": None
    },
    {
        "tool_name": "TOPAZ",
        "tool_category": "particle_picking",
        "biomate_status": "partial",
        "container_image": None,
        "version": "0.2.5",
        "use_when": ["nanodisc samples", "arc/crescent shaped particles", "low-contrast particles", "when crYOLO general model misses > 30% of particles"],
        "key_parameters": {"training_particles": "500 manually curated minimum", "model": "resnet8 default", "radius": "match particle radius in pixels"},
        "alternatives": ["crYOLO", "CryoSPARC template picker"],
        "biomate_gap_notes": "General model available; training workflow on user data not yet in BioMate pipeline"
    },
    {
        "tool_name": "Coot",
        "tool_category": "model_building",
        "biomate_status": "missing",
        "container_image": None,
        "version": "0.9+",
        "use_when": ["loop remodeling", "ligand placement", "manual sidechain fixing", "register correction", "multi-chain oligomeric fitting"],
        "key_parameters": {"real_space_refine_zone": "5 residue window", "fit_residues_to_map": "sigma 1.0-1.5"},
        "alternatives": ["ISOLDE (for strained oligomers)"],
        "biomate_gap_notes": "P1 priority gap — needed between AF2 dock and PHENIX refine for all studies"
    },
    {
        "tool_name": "DeepEMhancer",
        "tool_category": "post_processing",
        "biomate_status": "partial",
        "container_image": "biomate/cryo-em-tools:1.0",
        "version": "latest",
        "use_when": ["heterogeneous local resolution maps", "when B-factor sharpening produces noise artifacts", "maps with resolution range > 1.5 A across protein"],
        "key_parameters": {"model": "tight (< 4A) | wide (3-6A) | highRes (< 3A)", "normalization": "use half-maps for best results"},
        "alternatives": ["B-factor sharpening (CryoSPARC auto)", "LocScale"],
        "biomate_gap_notes": "Docker built; Nextflow module written; not yet wired into main SPA pipeline as optional step"
    },
    {
        "tool_name": "ISOLDE",
        "tool_category": "model_building",
        "biomate_status": "missing",
        "container_image": None,
        "version": "1.4",
        "use_when": ["strained oligomers (> 4 chains)", "high MolProbity clashscore after PHENIX refine", "flexible loops with density but poor geometry"],
        "key_parameters": {"temperature": "100K restraining MD", "map_weight": "increase for low-resolution regions"},
        "alternatives": ["Coot real-space refine (slower for large complexes)"],
        "biomate_gap_notes": "ChimeraX plugin — needs ChimeraX headless integration. P2 priority."
    },
    {
        "tool_name": "RELION_multibody",
        "tool_category": "refinement",
        "biomate_status": "partial",
        "container_image": None,
        "version": "4.0",
        "use_when": ["flexible multi-domain complexes", "pore-forming oligomers", "large RNPs with mobile modules", "when global refinement resolution plateaus despite many particles"],
        "key_parameters": {"n_bodies": "3-6 recommended", "body_definition": "each = independently folded domain", "rotation_allowed": "5-10 degrees between bodies"},
        "alternatives": ["CryoSPARC 3DVA (for continuous motion)", "focused classification"],
        "biomate_gap_notes": "RELION available; multi-body specific guidance and body mask generation not in BioMate workflow"
    },
    {
        "tool_name": "cryo_et_full_pipeline",
        "tool_category": "cryo_et",
        "biomate_status": "have",
        "container_image": None,
        "version": "1.0",
        "use_when": ["tilt series cryo-ET", "subtomogram averaging", "in-membrane pore structures", "in-cell structural biology"],
        "key_parameters": {"tilt_range": "-60 to +60 degrees", "tilt_increment": "3 degrees", "total_dose": "100-120 e/A2 per series", "alignment": "AreTomo2 default or IMOD", "reconstruction": "WBP default or SIRT"},
        "alternatives": ["dynamo (MATLAB-based STA)", "emClarity"],
        "biomate_gap_notes": "Pipeline complete. Missing: cryo-FIB milling sample prep guidance for in-cell work"
    },
    {
        "tool_name": "drug_difference_map",
        "tool_category": "analysis",
        "biomate_status": "have",
        "container_image": "biomate/cryo-em-tools:1.0",
        "version": "1.0",
        "use_when": ["drug binding site identification", "comparing drug-bound vs apo", "multi-drug atlas studies", "PAM allosteric site mapping"],
        "key_parameters": {"threshold_sigma": "3.0 for protein, 4.0 for drug placement", "normalization": "normalize both maps to same intensity scale first", "occupancy_min": "0.7"},
        "alternatives": ["ChimeraX volumesubtract (manual)"],
        "biomate_gap_notes": "Script exists (scripts/drug_difference_map.py); Nextflow module written; not yet registered as searchable workflow"
    }
]


def populate(db_path: str = DB_PATH):
    import sqlite3, json
    conn = sqlite3.connect(db_path)
    try:
        # Protocols
        for p in PROTOCOLS:
            conn.execute("""
                INSERT OR REPLACE INTO cryo_em_protocols
                (sample_class, display_name, typical_mw_range_kda, reconstitution_type,
                 collection_params, reconstitution_params, qc_gates, picking_strategy,
                 refinement_strategy, model_building, use_cases, limitations, key_principles,
                 tool_requirements, reference_papers, updated_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,datetime('now'))
            """, (
                p["sample_class"], p["display_name"],
                p.get("typical_mw_range_kda"), p.get("reconstitution_type"),
                json.dumps(p["collection_params"]),
                json.dumps(p.get("reconstitution_params")),
                json.dumps(p["qc_gates"]),
                json.dumps(p["picking_strategy"]),
                json.dumps(p["refinement_strategy"]),
                json.dumps(p["model_building"]),
                json.dumps(p["use_cases"]),
                json.dumps(p["limitations"]),
                json.dumps(p["key_principles"]),
                json.dumps(p["tool_requirements"]),
                json.dumps(p.get("reference_papers")),
            ))
        print(f"Inserted {len(PROTOCOLS)} protocol rows")

        # Parameters
        for ctx, param, val, unit, rationale in PARAMETERS:
            conn.execute("""
                INSERT OR REPLACE INTO cryo_em_parameters (context, parameter, value, unit, rationale)
                VALUES (?,?,?,?,?)
            """, (ctx, param, val, unit, rationale))
        print(f"Inserted {len(PARAMETERS)} parameter rows")

        # Tools
        for t in TOOLS:
            conn.execute("""
                INSERT OR REPLACE INTO cryo_em_tools
                (tool_name, tool_category, biomate_status, container_image, version,
                 use_when, key_parameters, alternatives, biomate_gap_notes)
                VALUES (?,?,?,?,?,?,?,?,?)
            """, (
                t["tool_name"], t["tool_category"], t["biomate_status"],
                t.get("container_image"), t.get("version"),
                json.dumps(t["use_when"]),
                json.dumps(t.get("key_parameters")),
                json.dumps(t.get("alternatives")),
                t.get("biomate_gap_notes"),
            ))
        print(f"Inserted {len(TOOLS)} tool rows")

        conn.commit()
        print("Population complete.")
    except Exception as e:
        conn.rollback()
        raise e
    finally:
        conn.close()


if __name__ == "__main__":
    db = sys.argv[1] if len(sys.argv) > 1 else DB_PATH
    populate(db)
