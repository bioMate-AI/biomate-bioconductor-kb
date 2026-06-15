"""
Nextflow QC Gate Handler

Monitors Nextflow trace file for process completions and triggers QC validation.
Emits SSE events when QC gates are triggered.
"""


# Python 3.9 compat: PEP 604 union syntax in annotations below requires this.
from __future__ import annotations
import json
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Any, Callable, Optional

try:
    from galaxy.jobs.parameter_suggester import get_suggester_for_domain
    SUGGESTER_AVAILABLE = True
except ImportError:
    SUGGESTER_AVAILABLE = False

log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# QC threshold governance constants (Phase 1 — per-invocation overrides)
# ---------------------------------------------------------------------------

# Layer 0: Red lines — absolute bounds enforced even when a user provides an
# override. An override that would cross a red line is clamped to the bound,
# logged as a warning, and recorded in the audit log.
# Format: {metric_key: {"bound": float, "direction": "min"|"max", "rationale": str}}
QC_RED_LINES: Dict[str, Any] = {
    "reads_surviving_pct": {
        "bound": 50.0, "direction": "min",
        "rationale": "> 50% loss = adapter-dominated library; downstream analysis is invalid",
    },
    "fit_quality": {
        "bound": 0.5, "direction": "min",
        "rationale": "CTF estimation completely failed; particle picking results are invalid",
    },
    "mito_fraction_pct": {
        "bound": 80.0, "direction": "max",
        "rationale": "Dead-cell lysates, not transcriptomes; results are biologically meaningless",
    },
    "alignment_rate": {
        "bound": 5.0, "direction": "min",
        "rationale": "< 5% alignment = species/sample swap; halt unconditionally",
    },
}

# Layer 1: GOLD thresholds — mandated by ENCODE4 or GATK Best Practices.
# Metrics in this set cannot be relaxed via qc_overrides. Changes require a
# platform-level code review with a new evidence citation.
QC_GOLD_METRICS: frozenset = frozenset({
    "mapped_pct",       # GATK Best Practices: FLAGSTAT mapped ≥ 70%
    "tss_enrichment",   # ENCODE4 ATAC-seq 2022: ≥ 5 acceptable, ≥ 7 ideal
    "nrf_score",        # ENCODE4 ATAC-seq 2022: ≥ 0.9
})

# Layer 3: Named profiles — curated sets of Layer-2 overrides for well-characterised
# assay contexts. Each profile is a dict of {metric_key: threshold_value} using
# the same keys accepted by qc_overrides. Profiles are read-only and versioned;
# users may supply explicit qc_overrides on top of a profile (explicit takes precedence).
#
# Profile format:
#   description:  str — human-readable summary for the API /api/qc/profiles endpoint
#   domain_hint:  str — primary workflow domain (informational only)
#   overrides:    Dict[str, float] — threshold overrides applied when profile is selected
#   references:   List[str] — primary literature / guideline citations
QC_NAMED_PROFILES: Dict[str, Dict[str, Any]] = {
    # ---------------------------------------------------------------
    # RNA-seq
    # ---------------------------------------------------------------
    "rnaseq_polya_standard": {
        "description": "Standard polyA-selected RNA-seq (default). No adjustments from platform defaults.",
        "domain_hint": "rnaseq",
        "overrides": {},
        "references": ["nf-core/rnaseq v3.14 defaults"],
    },
    "rnaseq_ribodepleted": {
        "description": (
            "Total RNA with ribosomal depletion (RiboZero / RiboMinus). "
            "Ribo-depletion removes large rRNA fractions, producing more intronic reads "
            "that may not align to a spliced transcriptome reference — lowering effective "
            "alignment rate by 10–20 pp compared to polyA libraries."
        ),
        "domain_hint": "rnaseq",
        "overrides": {
            "alignment_rate": 50.0,      # vs default 70%  (Zhao et al. 2020, RNA Biol)
            "reads_surviving_pct": 65.0, # vs default 70%
            "assigned_reads_pct": 40.0,  # vs default 50%  (intronic reads miss splice-junction counts)
        },
        "references": ["Zhao S et al. 2020 RNA Biol 17(8):1105-1118"],
    },
    "rnaseq_ffpe": {
        "description": (
            "FFPE-preserved tissue RNA-seq. RNA is highly fragmented (median fragment 100–200 bp), "
            "resulting in lower alignment rates, reduced Q30 scores, and more trimming failures. "
            "Standard thresholds generate systematic false-positive gates on valid FFPE data."
        ),
        "domain_hint": "rnaseq",
        "overrides": {
            "alignment_rate": 45.0,      # vs default 70%  (Sinicropi et al. 2012)
            "reads_surviving_pct": 60.0, # vs default 70%
            "q30_pct": 65.0,             # vs default 75%
        },
        "references": ["Sinicropi D et al. 2012 PLoS ONE 7(5):e38396"],
    },
    "rnaseq_single_nucleus": {
        "description": (
            "Single-nucleus RNA-seq (snRNA-seq). Intronic reads dominate — alignment to a "
            "spliced mRNA reference is fundamentally lower than cytoplasmic RNA-seq. "
            "Duplicate rate check is suppressed: nuclear RNA is rare, so PCR amplification "
            "is necessary and duplicates do not indicate library quality problems."
        ),
        "domain_hint": "rnaseq",
        "overrides": {
            "alignment_rate": 50.0,   # 10x Genomics snRNA-seq Guide v2.0
            # duplicate_pct suppressed via domain-aware skip — not a named-profile concern
        },
        "references": ["10x Genomics snRNA-seq Reagent Kit User Guide v2.0 (2023)"],
    },
    "rnaseq_nonmodel_organism": {
        "description": (
            "Non-model organism RNA-seq with an incomplete or draft genome/annotation. "
            "Unannotated genes produce unmapped reads and inflate 'unassigned' counts "
            "in feature counting. Thresholds are relaxed; interpretation requires care."
        ),
        "domain_hint": "rnaseq",
        "overrides": {
            "alignment_rate": 40.0,   # [BRONZE] no formal standard; community practice
            "assigned_reads_pct": 30.0,
        },
        "references": ["[BRONZE] community practice — no formal guideline"],
    },

    # ---------------------------------------------------------------
    # DNA-seq / WGS / WES
    # ---------------------------------------------------------------
    "wgs_germline_standard": {
        "description": "Standard germline WGS (default). 30X minimum coverage per GATK Best Practices.",
        "domain_hint": "wgs",
        "overrides": {},
        "references": ["GATK Best Practices — Germline SNP/Indel calling (2023)"],
    },
    "wgs_germline_lowpass": {
        "description": (
            "Low-pass WGS (0.5–10X) for population genetics, imputation, and polygenic "
            "score studies. 4X minimum is the empirical floor for reliable imputation "
            "with modern reference panels (TOPMed / 1000G)."
        ),
        "domain_hint": "wgs",
        "overrides": {
            "mean_coverage": 4.0,    # Rubinacci et al. 2021, Nat Genet
            "duplicate_pct": 60.0,  # PCR amplification of shallow libraries is expected
        },
        "references": ["Rubinacci S et al. 2021 Nat Genet 53:120-126 (UK Biobank)"],
    },
    "wgs_somatic_tumor_only": {
        "description": (
            "Somatic tumor-only WGS without a matched normal. Higher coverage is required "
            "to detect low-VAF mutations and distinguish somatic from germline variants. "
            "80X is the GATK Mutect2 recommendation for tumor-only calling."
        ),
        "domain_hint": "wgs",
        "overrides": {
            "mean_coverage": 80.0,
            "duplicate_pct": 50.0,  # tumor libraries often have elevated PCR duplication
        },
        "references": ["GATK Mutect2 Best Practices — Tumor-Only (2023)"],
    },
    "wgs_ffpe": {
        "description": (
            "FFPE-derived WGS. FFPE artifacts (C→T and G→A transitions) require higher "
            "depth to filter reliably, but FFPE PCR bias substantially increases duplicate "
            "rates — a 65% duplicate threshold is supported by Robbe et al. 2018."
        ),
        "domain_hint": "wgs",
        "overrides": {
            "mean_coverage": 30.0,  # same as germline; more depth is better but not always achievable
            "duplicate_pct": 65.0,  # Robbe et al. 2018, Nat Med 24:1555
        },
        "references": ["Robbe P et al. 2018 Nat Med 24:1555-1563"],
    },
    "wes_research": {
        "description": (
            "Research-grade whole-exome sequencing. 50X is sufficient for most germline "
            "variant discovery studies; clinical applications require wes_clinical_germline (80X)."
        ),
        "domain_hint": "wes",
        "overrides": {
            "mean_coverage": 50.0,  # nf-core/sarek v3 defaults for WES
        },
        "references": ["nf-core/sarek v3 WES defaults"],
    },
    "wes_clinical_germline": {
        "description": (
            "Clinical-grade WES for germline diagnostic reporting. 80X minimum is the "
            "ACMG 2016 technical standard for NGS-based clinical diagnostics."
        ),
        "domain_hint": "wes",
        "overrides": {
            "mean_coverage": 80.0,  # ACMG 2016 NGS Technical Standards
        },
        "references": ["ACMG/AMP 2016 Standards and Guidelines for NGS Diagnostics"],
    },

    # ---------------------------------------------------------------
    # Single-cell RNA-seq
    # ---------------------------------------------------------------
    "scrna_standard": {
        "description": "Standard single-cell RNA-seq (10x Genomics Chromium, default).",
        "domain_hint": "scrna_seq",
        "overrides": {},
        "references": ["10x Genomics Cell Ranger v7 defaults"],
    },
    "scrna_cardiac": {
        "description": (
            "Single-cell RNA-seq from cardiac or skeletal muscle tissue. "
            "Cardiomyocytes are rich in mitochondria — a mito fraction of 30–40% "
            "is biologically expected and does NOT indicate dead/damaged cells. "
            "The standard 20% gate produces high false-positive rates in cardiac studies."
        ),
        "domain_hint": "scrna_seq",
        "overrides": {
            "mito_fraction_pct": 40.0,        # vs default 20%  (Simonson et al. 2023)
            "mito_fraction_pct_warning": 25.0, # warn above 25% (advisory)
        },
        "references": [
            "Simonson B et al. 2023 Circ Res 132(9):1174-1193",
            "Kuppe C et al. 2022 Nature 605(7909):319-326 (cardiac cell atlas)",
        ],
    },
    "scrna_neuronal": {
        "description": (
            "Single-cell RNA-seq from brain / neuronal tissue. "
            "Neurons have elevated mitochondrial content relative to non-neural tissues; "
            "30% mito is an appropriate permissive gate. Median genes per cell may be "
            "lower for inhibitory interneurons (narrower transcriptome)."
        ),
        "domain_hint": "scrna_seq",
        "overrides": {
            "mito_fraction_pct": 30.0,         # vs default 20%
            "mito_fraction_pct_warning": 20.0,  # same as default hard gate (advisory sooner)
            "median_genes_per_cell": 300,        # vs default 500 — interneurons transcriptomically narrow
        },
        "references": [
            "[BRONZE] Allen Brain Atlas scRNA-seq QC guidelines (community practice)",
            "Bakken TE et al. 2021 Nature 598:86-102 (Human Brain Cell Atlas)",
        ],
    },
    "scrna_perturbation": {
        "description": (
            "Single-cell RNA-seq with CRISPR perturbation (Perturb-seq, CROP-seq, CRISPRi screens). "
            "Adds guide library coverage, transfection efficiency, and doublet detection gates "
            "on top of standard scRNA-seq thresholds."
        ),
        "domain_hint": "scrna_seq",
        "overrides": {
            "guide_library_coverage_pct": 70.0,
            "transfection_efficiency_pct": 30.0,
            "max_doublet_fraction_pct": 10.0,
        },
        "references": [
            "Replogle JM et al. 2022 Cell 185(14):2559-2575 (Perturb-seq genome-wide)",
            "Datlinger P et al. 2021 Nat Methods 18(6):688-693 (CROP-seq updated)",
            "Norman TM et al. 2019 Science 365(6455):786-793 (CRISPRi Perturb-seq)",
            "[SILVER] 70% guide coverage: Replogle et al. 2022 Cell Supp Methods",
        ],
    },

    # ---------------------------------------------------------------
    # Metagenomics
    # ---------------------------------------------------------------
    "metagenomics_human_gut": {
        "description": (
            "Human gut metagenomics with a comprehensive database (Kraken2 Standard or RefSeq). "
            "The gut microbiome is well-characterised — 50% classification is the HMP "
            "empirical floor for Illumina data."
        ),
        "domain_hint": "metagenomics",
        "overrides": {
            "classified_pct_critical": 50.0,  # vs default 30%  (HMP Consortium 2012)
            "classified_pct_warning": 60.0,   # tighter than default (same)
        },
        "references": ["HMP Consortium 2012 Nature 486:207-214"],
    },
    "metagenomics_soil": {
        "description": (
            "Soil metagenomics — high microbial 'dark matter' fraction. "
            "Even with a comprehensive database, soil samples routinely classify "
            "5–40% of reads. Warning threshold is set at 8% (investigation if lower); "
            "critical gate is suppressed to 3%."
        ),
        "domain_hint": "metagenomics",
        "overrides": {
            "classified_pct_critical": 3.0,   # suppressed — soil dark matter is expected
            "classified_pct_warning": 8.0,    # only investigate if < 8%
        },
        "references": [
            "Bahram M et al. 2018 Nature 560(7717):233-237",
            "Delgado-Baquerizo M et al. 2018 Science 359(6373):320-325",
        ],
    },
    "metagenomics_marine": {
        "description": (
            "Marine metagenomics — reference databases cover ocean microbiota poorly. "
            "Open-ocean samples commonly classify 10–50% of reads depending on depth, "
            "season, and geographic location. Critical gate suppressed to 4%; "
            "warning threshold at 10%."
        ),
        "domain_hint": "metagenomics",
        "overrides": {
            "classified_pct_critical": 4.0,
            "classified_pct_warning": 10.0,
        },
        "references": ["Sunagawa S et al. 2015 Science 348(6237):1261359 (TARA Oceans)"],
    },
    "metagenomics_clinical_pathogen": {
        "description": (
            "Clinical metagenomics for pathogen detection (bloodstream infection, CSF). "
            "Samples should be dominated by human reads (which are not classified by "
            "Kraken2 without a human database entry) or by the pathogen. "
            "Very low classification (<60%) is unusual and warrants investigation."
        ),
        "domain_hint": "metagenomics",
        "overrides": {
            "classified_pct_critical": 60.0,
            "classified_pct_warning": 70.0,
        },
        "references": ["[BRONZE] IDSA clinical metagenomics guidance (2024)"],
    },

    # ---------------------------------------------------------------
    # Cryo-EM
    # ---------------------------------------------------------------
    "cryoem_spa_purified": {
        "description": "Standard single-particle analysis of purified protein complexes (default).",
        "domain_hint": "cryo_em",
        "overrides": {},
        "references": ["EMPIAR deposition standards; EMDB validation report (2024)"],
    },
    "cryoem_spa_membrane": {
        "description": (
            "Single-particle cryo-EM of membrane proteins (GPCRs, channels, transporters). "
            "Membrane proteins embedded in detergent micelles or nanodiscs exhibit higher "
            "beam-induced motion than soluble complexes. 80Å drift threshold is appropriate."
        ),
        "domain_hint": "cryo_em",
        "overrides": {
            "total_drift_angstrom": 80.0,   # vs default 50Å
            "fit_quality": 0.65,            # vs default 0.7 (detergent scatter reduces signal)
        },
        "references": ["[BRONZE] Membrane protein cryo-EM community practice (2024)"],
    },
    "cryoem_spa_phase_plate": {
        "description": (
            "Single-particle cryo-EM with Volta Phase Plate (VPP). "
            "Phase plate experiments use much lower defocus (near-Gaussian transfer at 0.2–0.8 μm underfocus); "
            "CTF fit quality thresholds are relaxed because VPP CTF fits have inherently lower CC scores. "
            "Phase shift advisory gates are activated (depleted < 0.2 rad; overcharged > 1.5 rad)."
        ),
        "domain_hint": "cryo_em",
        "overrides": {
            "fit_quality": 0.65,            # vs default 0.7 — VPP CTF fits are noisier
            "avg_phase_shift_rad_min": 0.2, # advisory: VPP depleted below this
            "avg_phase_shift_rad_max": 1.5, # advisory: VPP over-charged above this
        },
        "references": [
            "[BRONZE] Danev & Bharat 2018 Trends Cell Biol — phase shift 0.4–0.8π rad optimal",
            "[BRONZE] CryoSPARC VPP tutorial (2023) — CTF fit quality relaxed for VPP data",
        ],
    },
    "cryoem_spa_standard": {
        "description": (
            "Standard single-particle analysis with default gates (alias for cryoem_spa_purified). "
            "Suitable for well-behaved soluble complexes without special sample considerations."
        ),
        "domain_hint": "cryo_em",
        "overrides": {},
        "references": ["EMPIAR deposition standards; EMDB validation report (2024)"],
    },
    "cryoem_spa_lowdose": {
        "description": (
            "Low-dose single-particle cryo-EM using minimal electron dose per frame. "
            "Optimized for beam-sensitive samples (e.g., RNA complexes, small proteins <100 kDa). "
            "Total drift and correlation thresholds are relaxed to accommodate low-SNR micrographs."
        ),
        "domain_hint": "cryo_em",
        "overrides": {
            "total_drift_angstrom": 70.0,   # relaxed: low-dose means higher shot noise → more drift
            "fit_quality": 0.60,            # relaxed for low-SNR CTF estimates
            "correlation_score": 0.40,      # relaxed: low dose reduces particle correlation
        },
        "references": [
            "[BRONZE] Low-dose cryo-EM community practice; Henderson et al. 2012 Structure",
            "[BRONZE] CryoSPARC low-dose guide (2024)",
        ],
    },
    "cryoem_tomo_in_situ": {
        "description": (
            "Cryo-electron tomography of cellular lamellae prepared by FIB-SEM milling. "
            "In-situ cryo-ET has much higher drift (100–200Å) due to lamella thickness, "
            "carbon contamination, and beam-induced charging."
        ),
        "domain_hint": "cryo_em",
        "overrides": {
            "total_drift_angstrom": 150.0,  # in-situ lamellae: high drift is expected
            "fit_quality": 0.5,             # red-line floor — cannot be lowered further
            "correlation_score": 0.3,       # vs default 0.5 (thick lamellae attenuate signal)
        },
        "references": ["[BRONZE] FIB-SEM cryo-ET community practice; Bharat & Bharat 2024"],
    },
    # ---------------------------------------------------------------
    # Proteomics (LC-MS/MS)
    # ---------------------------------------------------------------
    "proteomics_standard": {
        "description": (
            "Standard label-free DDA proteomics of cell lysate (default). "
            "Applies GOLD PSM/protein FDR gate (Elias & Gygi 2007) and "
            "SILVER missed cleavage / CV gates (EuBIC 2018 community standards). "
            "Use for standard bottom-up LC-MS/MS protein identification."
        ),
        "domain_hint": "proteomics",
        "overrides": {},
        "references": [
            "[GOLD] Elias & Gygi 2007, Nature Methods — PSM/protein FDR < 1%",
            "[SILVER] EuBIC 2018 community standards — missed cleavage < 20%, CV < 20%",
        ],
    },
    "proteomics_phospho": {
        "description": (
            "Phosphopeptide enrichment proteomics (TiO2, IMAC, Fe-NTA). "
            "PSM count is reduced by design after enrichment; phosphosite localization "
            "score > 0.75 is the primary quality indicator (Beausoleil et al. 2006). "
            "CV gate relaxed to 25% (enrichment adds technical variance). "
            "Missed cleavage gate relaxed to 30% (phosphopeptides resist tryptic digestion "
            "at pSer/pThr/pTyr sites)."
        ),
        "domain_hint": "proteomics",
        "overrides": {
            "psm_count": 500,              # vs default 1000 — enrichment reduces PSM count
            "missed_cleavage_pct": 30.0,   # vs default 20.0 — phosphopeptides resist digestion
            "cv_pct": 25.0,                # vs default 20.0 — enrichment adds technical variance
        },
        "references": [
            "[SILVER] Beausoleil et al. 2006, Nature Biotechnology — localization score > 0.75",
            "[BRONZE] EuBIC 2018 phosphoproteomics community practice",
        ],
    },
    "proteomics_plasma_biomarker": {
        "description": (
            "Depleted plasma DIA/DDA proteomics for biomarker discovery. "
            "Tighter CV gate (< 15%) required for biomarker-grade reproducibility "
            "(Geyer et al. 2017, Cell Systems). Missing value fraction gate applied "
            "(< 30% missing per protein). Lower protein FDR thresholds remain GOLD."
        ),
        "domain_hint": "proteomics",
        "overrides": {
            "cv_pct": 15.0,             # vs default 20.0 — biomarker-grade reproducibility
            "missing_value_pct": 30.0,  # explicit gate: < 30% missing values per protein
        },
        "references": [
            "[SILVER] Geyer et al. 2017, Cell Systems — plasma DIA proteomics CV standards",
            "[SILVER] EuBIC 2018 — depleted plasma QC community practice",
        ],
    },
    "proteomics_chemoproteomics": {
        "description": (
            "Affinity proteomics / chemoproteomics pulldown (ABPP, drug bead pulldown). "
            "Enrichment ratio gate (prey/input > 3×) is the primary quality indicator. "
            "Protein FDR gate remains GOLD (Elias & Gygi 2007). PSM count gate relaxed "
            "(pulldown reduces total protein coverage compared to whole lysate input)."
        ),
        "domain_hint": "proteomics",
        "overrides": {
            "psm_count": 200,              # vs default 1000 — pulldown reduces proteome coverage
        },
        "references": [
            "[GOLD] Elias & Gygi 2007 — protein FDR < 1% (unchanged)",
            "[SILVER] ABPP community practice — enrichment ratio > 3× input proteome",
        ],
    },

    # ── Compound structure / cheminformatics profiles ────────────────────────
    "compound_druglike": {
        "description": (
            "Standard drug-like compound library QC applying Lipinski's Rule of Five "
            "(Ro5): MW ≤ 500 Da, logP ≤ 5, HBD ≤ 5, HBA ≤ 10. "
            "Tighter MW gate than the default 900 Da. Appropriate for oral small-molecule "
            "drug discovery campaigns."
        ),
        "domain_hint": "cheminformatics",
        "overrides": {
            "compound_mw_limit": 500.0,    # Lipinski Ro5 vs default 900 Da
            "logp_limit": 5.0,
            "hbd_limit": 5,
            "hba_limit": 10,
        },
        "references": [
            "[GOLD] Lipinski et al. (2001) Adv Drug Deliv Rev — Rule of Five",
            "[SILVER] Veber et al. (2002) J Med Chem — oral bioavailability descriptors",
        ],
    },
    "compound_natural_product": {
        "description": (
            "Natural product and natural-product-inspired compound QC. "
            "Relaxed MW gate (≤ 1000 Da) to accommodate macrolides, terpenes, and "
            "glycosylated scaffolds. No logP limit (natural products span a wide range). "
            "Ro5 violations are expected and flagged as advisory only."
        ),
        "domain_hint": "cheminformatics",
        "overrides": {
            "compound_mw_limit": 1000.0,   # accommodate macrolides, terpenes
            "logp_limit": None,            # no limit — NPs span wide logP range
        },
        "references": [
            "[SILVER] Newman & Cragg (2020) J Nat Prod — natural products in drug discovery",
            "[BRONZE] Rodrigues et al. (2016) J Med Chem — NP-likeness beyond Ro5",
        ],
    },
    "compound_peptidomimetic": {
        "description": (
            "Peptidomimetic and stapled peptide compound QC. "
            "MW gate relaxed to ≤ 900 Da; higher HBD/HBA counts accepted. "
            "Undefined stereocenters are flagged with higher priority "
            "(stereochemistry is critical for peptide backbone activity)."
        ),
        "domain_hint": "cheminformatics",
        "overrides": {
            "compound_mw_limit": 900.0,    # default — peptidomimetics can be large
            "hbd_limit": 10,               # relaxed from Ro5 (5) — peptide bonds donate
            "hba_limit": 15,               # relaxed from Ro5 (10)
        },
        "references": [
            "[SILVER] Giordanetto & Kihlberg (2014) J Med Chem — beyond Ro5 for peptides",
            "[BRONZE] Doak et al. (2016) J Med Chem — macrocycle oral bioavailability",
        ],
    },

    # ── ADMET safety profiles (drug-dev / autoloop-wired) ───────────────────
    # Source of truth for thresholds: backend/experiments/admet_autoloop/qc_evaluator.py
    # These profiles surface the autoloop's internal QC catalog through the
    # central /api/qc/profiles endpoint so users and the param-prefill router
    # can select them by name. Overrides here mirror QC_PROFILES exactly.
    "admet_standard": {
        "description": (
            "Standard ADMET safety screen for oral small-molecule discovery. "
            "Applies ICH S7B hERG IC50 ≥ 10 µM, DILI probability ≤ 0.5 (Lammert 2010), "
            "Ames mutagenicity probability ≤ 0.5 (Kazius 2005), and Lipinski Ro5 "
            "(MW ≤ 500 Da, logP ≤ 5). TPSA ≤ 140 Å² for general oral absorption."
        ),
        "domain_hint": "admet",
        "overrides": {
            "herg_ic50_threshold_uM": 10.0,
            "dili_probability_max": 0.5,
            "dili_risk_level_max": "medium",
            "ames_probability_max": 0.5,
            "logp_max": 5.0,
            "mw_max_da": 500.0,
            "tpsa_max_A2": 140.0,
        },
        "references": [
            "[GOLD] ICH S7B (2005) — hERG IC50 ≥ 30× Cmax safety margin (Redfern 2003)",
            "[GOLD] Lammert C et al. (2010) Hepatology 51:615-620 — DILI probability",
            "[GOLD] Kazius J et al. (2005) J Med Chem 48:312-320 — Ames structural alerts",
            "[GOLD] Lipinski CA et al. (2001) Adv Drug Deliv Rev 46:3-26 — Rule of Five",
        ],
    },
    "admet_cns": {
        "description": (
            "CNS-penetrant compound ADMET safety screen — stricter than admet_standard "
            "to account for BBB-crossing liabilities. Tighter DILI/Ames cutoffs, smaller "
            "MW (≤ 450 Da), lower logP (≤ 4), and TPSA ≤ 90 Å² for BBB penetration "
            "(Hitchcock & Pennington 2006)."
        ),
        "domain_hint": "admet",
        "overrides": {
            "herg_ic50_threshold_uM": 10.0,
            "dili_probability_max": 0.4,
            "dili_risk_level_max": "low",
            "ames_probability_max": 0.3,
            "logp_max": 4.0,
            "mw_max_da": 450.0,
            "tpsa_max_A2": 90.0,
        },
        "references": [
            "[SILVER] Hitchcock SA & Pennington LD (2006) J Med Chem 49:7559-7583 — BBB TPSA",
            "[SILVER] Wager TT et al. (2010) ACS Chem Neurosci 1:435-449 — CNS MPO score",
        ],
    },
    "admet_oncology": {
        "description": (
            "Oncology ADMET profile — tolerates higher off-target toxicity burden given "
            "the narrow therapeutic window and life-threatening indication context. "
            "Stricter hERG (IC50 ≥ 5 µM) because of higher cardiotoxic kinase-inhibitor "
            "co-administration; relaxed DILI/Ames/MW gates to accommodate kinase-inhibitor "
            "and antibody-drug-conjugate small-molecule warheads."
        ),
        "domain_hint": "admet",
        "overrides": {
            "herg_ic50_threshold_uM": 5.0,
            "dili_probability_max": 0.6,
            "dili_risk_level_max": "high",
            "ames_probability_max": 0.6,
            "logp_max": 6.0,
            "mw_max_da": 700.0,
            "tpsa_max_A2": 180.0,
        },
        "references": [
            "[SILVER] FDA Oncology Center of Excellence — Project Optimus (2023) dose optimization",
            "[BRONZE] DeGoey DA et al. (2018) J Med Chem 61:2636-2651 — beyond Ro5 for oncology",
        ],
    },

    # ── Pharmacogenomics (PGx) profiles ─────────────────────────────────────
    "pgx_clinical": {
        "description": (
            "Clinical pharmacogenomics (PGx) WGS QC — CPIC-compliant. "
            "Requires ≥ 30× coverage on each PGx gene (CYP2D6, CYP2C19, CYP3A4, "
            "DPYD, TPMT, NUDT15, SLCO1B1, UGT1A1) to support reliable star allele "
            "assignment and CPIC-grade dosing recommendations. "
            "Coverage below 30× produces unreliable diplotype calls even in 30× WGS "
            "libraries due to GC bias (CYP2D6 is particularly GC-rich)."
        ),
        "domain_hint": "pharmacogenomics",
        "overrides": {
            "pgx_min_coverage": 30,        # CPIC guideline minimum
        },
        "references": [
            "[GOLD] CPIC guidelines (cpicpgx.org) — 30× minimum for tier 1 genes",
            "[GOLD] GATK Best Practices — VQSR PASS rate > 95%",
            "[SILVER] PharmVar — CYP2D6 copy number detection requirements",
        ],
    },
    "pgx_research": {
        "description": (
            "Research-grade pharmacogenomics WGS QC. "
            "Accepts ≥ 15× per-gene coverage with low-confidence calls flagged as "
            "advisory. Suitable for population studies and discovery cohorts where "
            "CPIC clinical-grade precision is not required. "
            "Star allele assignments at 15–29× should be treated as provisional."
        ),
        "domain_hint": "pharmacogenomics",
        "overrides": {
            "pgx_min_coverage": 15,        # advisory confidence at 15-29×
        },
        "references": [
            "[SILVER] CPIC guidelines — 15× minimum for tier 2 research use",
        ],
    },

    # ── Virtual Cell QC profiles ─────────────────────────────────────────
    "cipa_ind_submission": {
        "description": (
            "CiPA Tier 2 in silico cardiac safety QC for IND submission. "
            "Applies FDA/ICH S7B thresholds: qNET < −30 pC/pF → HIGH TdP risk (halt); "
            "APD90 prolongation > 30% → INTERMEDIATE escalation advisory; "
            "hERG safety margin < 30× Cmax → automatic escalation regardless of qNET. "
            "All three checks must pass (LOW or INTERMEDIATE with margin ≥ 30×) before "
            "the cardiac safety section of the IND CMC package can be signed off. "
            "Regulatory basis: ICH S7B (2021), FDA CiPA initiative, Dutta et al. 2017."
        ),
        "domain_hint": "drug_discovery",
        "overrides": {
            "cipa_qnet_high_risk_threshold":   -30.0,   # pC/pF; > -30 = HIGH TdP risk (halt)
            "cipa_qnet_intermediate_threshold": -40.0,  # pC/pF; -40 to -30 = INTERMEDIATE
            "cipa_apd90_prolongation_max_pct":   30.0,  # % change above baseline; > 30% = advisory
            "cipa_herg_safety_margin_min":        30.0,  # ×Cmax; < 30× = escalation flag
            "cipa_ead_probability_halt":           0.7,  # EAD probability; > 0.7 = halt
        },
        "references": [
            "[GOLD] ICH S7B (2021) + E14/S7B Q&A — CiPA framework Tier 2",
            "[GOLD] Dutta et al. 2017 Front Physiol 8:616 — qNET validation thresholds",
            "[SILVER] Lancaster & Sobie 2016 JPET 358(3) — APD sensitivity coefficients",
            "[SILVER] FDA CiPA initiative (fda.gov/media/cipa)",
        ],
    },
    "cipa_preclinical_screen": {
        "description": (
            "Preclinical CiPA cardiac screen — relaxed thresholds for early-stage "
            "lead optimization screening where hits are expected to have hERG liability. "
            "Flags rather than halts on qNET > −30 pC/pF. Suitable for SAR rounds "
            "where the goal is to rank-order compounds, not pass/fail for IND. "
            "Use cipa_ind_submission profile when generating IND package."
        ),
        "domain_hint": "drug_discovery",
        "overrides": {
            "cipa_qnet_high_risk_threshold":   -20.0,   # more permissive; advisory only
            "cipa_apd90_prolongation_max_pct":   50.0,
            "cipa_herg_safety_margin_min":        10.0,  # early-stage: 10× flag
            "cipa_ead_probability_halt":           0.9,
        },
        "references": [
            "[SILVER] ICH S7B — preclinical context; screening not IND submission",
        ],
    },

    # ── Disease-state PBPK profiles ──────────────────────────────────────────
    "pbpk_disease_state_ind": {
        "description": (
            "IND/NDA-grade disease-state PBPK QC. Flags AUC_ratio > 2× (dose adjustment "
            "labelling trigger) as advisory and AUC_ratio > 5× as HALT (contraindicated). "
            "Thresholds directly from FDA Guidance on PK in Renal Impairment (2010) and "
            "FDA Guidance on PK in Hepatic Impairment (2003). "
            "Validated against 6 FDA-published drug-impairment pairs, 10.6% MAE. "
            "See docs/20260429_PHARMACOLOGY_BENCHMARK_RESULTS.md."
        ),
        "domain_hint": "drug_discovery",
        "overrides": {},  # thresholds match FDA guidance exactly — no override needed
        "references": [
            "[GOLD] FDA Guidance: PK in Patients with Impaired Renal Function (2010)",
            "[GOLD] FDA Guidance: PK in Patients with Impaired Hepatic Function (2003)",
            "[GOLD] ICH E7 Studies in Support of Special Populations (1993/2010)",
            "[SILVER] Nolin TD et al. Adv Chronic Kidney Dis 2010; 17(5):395-405 — CLr scaling",
            "[SILVER] Wilkinson GR Drug Metab Dispos 2005; 33:276 — well-stirred model",
        ],
    },

    # ── Biomarker enrichment profiles ────────────────────────────────────────
    "biomarker_enrichment_phase2": {
        "description": (
            "Phase II/III biomarker enrichment QC: flags ER < 2× (FDA 2019 minimum) "
            "and bias-corrected sensitivity < 0.75 as advisories. "
            "Validated against BRIM-3 BRAF V600E structure (Chapman NEJM 2011): "
            "ER=33.2× recovered, 77.8% Phase III size reduction, 0 FDR false positives. "
            "See docs/20260429_PHARMACOLOGY_BENCHMARK_RESULTS.md."
        ),
        "domain_hint": "drug_discovery",
        "overrides": {
            "be_min_enrichment_ratio": 2.0,   # FDA 2019 minimum meaningful threshold
            "be_min_bc_sensitivity":   0.75,  # Sargent 2005 JNCI clinical utility threshold
        },
        "references": [
            "[GOLD] FDA Enrichment Strategies for Clinical Trials Guidance (2019)",
            "[GOLD] Chapman PB et al. NEJM 2011; 364:2507 — BRIM-3 BRAF V600E landmark",
            "[SILVER] Sargent DJ et al. JNCI 2005; 97:1209 — predictive biomarker framework",
            "[SILVER] Simon R Cancer Biomarkers 2010; 8:1 — biomarker-driven trial design",
            "[BRONZE] Youden WJ Cancer 1950; 3:32 — J-statistic optimal cut-point",
            "[SILVER] Benjamini Y & Hochberg Y JRSS-B 1995; 57:289 — FDR control",
        ],
    },

    # ── Polymorph stability profiles ─────────────────────────────────────────
    "polymorph_ind_submission": {
        "description": (
            "IND/NDA polymorph screening QC per ICH Q6A §3.1.1.5. "
            "HIGH-tier compounds (score ≥ 6/10) trigger mandatory XRPD/DSC screening. "
            "HIGH hygroscopicity flags controlled-storage requirement. "
            "HIGH photostability flags ICH Q1B Option 1 photostability study. "
            "Validated: ritonavir 9.5 HIGH (CMC crisis 1998), carbamazepine 4.0 MEDIUM. "
            "See docs/20260429_PHARMACOLOGY_BENCHMARK_RESULTS.md."
        ),
        "domain_hint": "drug_discovery",
        "overrides": {},  # ICH Q6A thresholds are regulatory — no override
        "references": [
            "[GOLD] ICH Q6A (1999) §3.1.1.5 — Polymorphism acceptance criteria",
            "[GOLD] ICH Q1A(R2) (2003) — Stability Testing of New Drug Substances",
            "[GOLD] ICH Q1B (1996) — Photostability Testing",
            "[SILVER] Fleming NM et al. Org Process Res Dev 2010; 14:975 — heuristic scoring",
            "[SILVER] Blagden N & Davey RJ Chem Soc Rev 2003; 32:495 — polymorph risk",
            "[BRONZE] Brittain HG Polymorphism in Pharmaceutical Solids 2009 — solid-state",
        ],
    },

    # ── PBPK simulation QC profiles ──────────────────────────────────────────
    "pbpk_ind_submission": {
        "description": (
            "PBPK QC gates for IND/NDA submission-grade simulations. "
            "Requires a valid absorption-distribution-elimination profile: "
            "Tmax must occur before 80% of the simulation window (no end-of-sim peak); "
            "a terminal decline phase must be present; systemic clearance must exceed "
            "0.01 L/h; and terminal half-life must be estimable. "
            "Regulatory basis: EMA PBPK Guideline EMA/CHMP/900052/2019; "
            "FDA PBPK Guidance for Industry 2018."
        ),
        "domain_hint": "drug_discovery",
        "overrides": {
            "pbpk_tmax_fraction_max": 0.80,   # Tmax must occur in first 80% of sim window
            "pbpk_cl_min_L_h":        0.01,   # minimum plausible CL for a small molecule
        },
        "references": [
            "[GOLD] EMA PBPK Guideline EMA/CHMP/900052/2019",
            "[GOLD] FDA PBPK Guidance for Industry 2018",
            "[GOLD] Willmann S et al. J Med Chem 2003; 46(12):2355-2368",
            "[SILVER] Davies B & Morris T. Pharm Res 1993; 10(7):1093-1095 — species CL",
        ],
    },

    "pbpk_screening": {
        "description": (
            "PBPK QC gates for early-stage screening simulations. "
            "Advisory-only (no halts) — suitable for lead optimisation rounds "
            "where model parameter uncertainty is expected. "
            "Flags missing elimination (Tmax > 90% of sim window) and CL < 0.001 L/h. "
            "Use pbpk_ind_submission for regulatory-grade runs."
        ),
        "domain_hint": "drug_discovery",
        "overrides": {
            "pbpk_tmax_fraction_max": 0.90,   # more permissive — flag only near-end peaks
            "pbpk_cl_min_L_h":        0.001,  # allow very low CL in early screening
        },
        "references": [
            "[SILVER] EMA PBPK Guideline EMA/CHMP/900052/2019 — context of use",
        ],
    },
    "tgi_oncology_solid_tumor": {
        "description": (
            "TGI model QC for solid tumor preclinical-to-clinical translation. "
            "Applies Claret et al. 2009 (J Clin Oncol) OS prediction thresholds: "
            "TGI < 40% → poor OS prognosis (halt — dose insufficient); "
            "TGI 40–70% → stable disease (advisory); TGI > 70% → favourable. "
            "RECIST: best response ≤ −30% (PR) required for advancement advisory. "
            "Tumor penetration factor < 0.3 triggers spatial heterogeneity advisory."
        ),
        "domain_hint": "drug_discovery",
        "overrides": {
            "tgi_pct_halt":                    40.0,   # < 40% = dose insufficient (halt)
            "tgi_pct_advisory":                70.0,   # 40–70% = advisory (SD range)
            "recist_pr_threshold_pct":        -30.0,   # < −30% change = PR
            "tumor_penetration_min":            0.3,   # < 0.3 = spatial advisory
            "ttp_days_min":                    60.0,   # TTP < 60 days = progressive disease
        },
        "references": [
            "[GOLD] Claret et al. 2009 J Clin Oncol 27:4103 — TGI→OS relationship",
            "[SILVER] Simeoni et al. 2004 Cancer Res 64:1094 — TGI ODE model",
            "[SILVER] RECIST v1.1 (Eisenhauer 2009) — response criteria",
        ],
    },
    "virtual_patient_pta_standard": {
        "description": (
            "Virtual patient cohort QC for dose optimization — standard adult population. "
            "FDA 2019 Population PK Guidance thresholds: PTA (% target attainment) must "
            "reach ≥ 80% in the general population and ≥ 70% in key special populations "
            "(renal impaired CrCl < 60, hepatic impaired Child-Pugh B/C, elderly > 65). "
            "IIV CV > 60% on clearance triggers high-variability advisory — dose "
            "individualization or TDM may be required per FDA guidance."
        ),
        "domain_hint": "pharmacology",
        "overrides": {
            "pta_general_population_min":   0.80,   # ≥ 80% general PTA required
            "pta_special_population_min":   0.70,   # ≥ 70% renal/hepatic/elderly
            "iiv_cl_cv_max":                0.60,   # > 60% CV = high variability advisory
            "iiv_vd_cv_max":                0.50,
            "auc_variability_fold_max":     5.0,    # AUC P95/P5 fold > 5 = dose review
        },
        "references": [
            "[GOLD] FDA 2019 Population PK Guidance (fda.gov)",
            "[SILVER] Sheiner & Ludden 1992 Clin Pharmacokinet (PopPK principles)",
            "[SILVER] Brendel et al. 2006 J Pharmacokinet Pharmacodyn (VPC)",
        ],
    },
    "metabolic_flux_dili_strict": {
        "description": (
            "Strict DILI metabolic FBA QC for IND-enabling toxicology package. "
            "Halts if composite DILI score > 0.6 (Aleo et al. 2017 HIGH tier); "
            "requires mitochondrial liability < 0.5 and steatosis risk < 0.4 per "
            "FDA DILI guidance. ROS index > 0.5 (significant oxidative stress) "
            "triggers ICH M7 genotoxicity advisory. ATP impairment > 40% = halt. "
            "Regulatory basis: FDA 2023 draft DILI guidance; Aleo 2017 benchmark."
        ),
        "domain_hint": "drug_discovery",
        "overrides": {
            "dili_score_halt":              0.60,   # > 0.6 = HIGH DILI → halt
            "dili_score_advisory":          0.35,   # 0.35–0.6 = INTERMEDIATE → advisory
            "mito_liability_max":           0.50,
            "steatosis_risk_max":           0.40,
            "cholestasis_risk_max":         0.40,
            "ros_index_advisory":           0.50,   # > 0.5 = oxidative stress advisory
            "atp_impairment_pct_halt":     40.0,   # > 40% ATP loss = halt
        },
        "references": [
            "[GOLD] Aleo et al. 2017 Chem Res Toxicol 30:1789 — mitDILI classification",
            "[SILVER] FDA 2023 draft DILI guidance",
            "[SILVER] Dykens & Will 2007 Drug Discov Today 12(17):777",
        ],
    },
}


class NextflowQCGateHandler:
    """
    Handles QC gate checking for Nextflow workflow processes.

    Monitors process completion events and:
    1. Calculates QC metrics for completed processes
    2. Compares against quality thresholds
    3. Emits SSE events when QC gates are triggered
    """

    def __init__(
        self,
        invocation_id: str,
        work_dir: Path,
        sse_callback: Callable[[str, Dict[str, Any]], None],
        app: Any,
        workflow_domain: str = "cryo_em",
        current_parameters: Optional[Dict[str, Any]] = None,
        qc_overrides: Optional[Dict[str, Any]] = None,
        qc_profile: Optional[str] = None,
        s3_outdir: Optional[str] = None,
    ):
        """
        Initialize QC gate handler.

        Args:
            invocation_id: Workflow invocation ID
            work_dir: Nextflow work directory
            sse_callback: Callback for emitting SSE events - signature: (event_type, data)
            app: Galaxy app instance
            workflow_domain: Domain of the workflow (e.g., 'cryo_em', 'rnaseq')
            current_parameters: Current workflow parameters
            qc_overrides: Per-invocation threshold overrides dict (Phase 1).
                GOLD metrics and red-line bounds cannot be overridden.
                Explicit overrides take precedence over profile defaults.
                Example: {"alignment_rate": 50.0, "reads_surviving_pct": 65.0}
            qc_profile: Named QC profile (Phase 2 — Layer 3).
                Profile overrides are applied first; explicit qc_overrides values
                take precedence over any value defined in the profile.
                Example: "rnaseq_ribodepleted"
        """
        self.invocation_id = invocation_id
        self.work_dir = work_dir
        self.sse_callback = sse_callback
        self.app = app
        self.workflow_domain = workflow_domain
        self.current_parameters = current_parameters or {}
        self.active_profile = qc_profile  # None if not using a named profile
        # S3 published output directory — set for Batch runs so _calculate_qc_metrics
        # can read published report JSON files instead of non-existent local task dirs.
        self.s3_outdir: Optional[str] = s3_outdir.rstrip("/") if s3_outdir else None

        # Merge profile overrides (lower precedence) with explicit overrides (higher precedence).
        # Merge order: profile → explicit overrides (right-hand-side wins on key collision)
        profile_overrides = self.get_profile_overrides(qc_profile) if qc_profile else {}
        explicit_overrides = qc_overrides or {}
        self.qc_overrides: Dict[str, Any] = {**profile_overrides, **explicit_overrides}

        # Track which processes have been checked
        self.checked_processes = set()

        # US-6.2: In-memory QC event log — all gate + warning events for this invocation.
        # Each entry: {"type": "gate"|"warning", "process_name", "timestamp",
        #               "metrics", "failures"|"warnings", "suggestions"}
        self.qc_event_log: list = []

        # Write an audit record at initialisation when overrides are active
        if self.qc_overrides or self.active_profile:
            self._write_audit_log_entry("initialized", {})
            if self.active_profile:
                log.info(
                    f"[QC Profile] Invocation {invocation_id}: "
                    f"named profile '{self.active_profile}' active "
                    f"({len(profile_overrides)} base overrides) + "
                    f"{len(explicit_overrides)} explicit overrides"
                )
            else:
                log.info(
                    f"[QC Override] Invocation {invocation_id}: "
                    f"{len(self.qc_overrides)} threshold override(s) active: "
                    f"{list(self.qc_overrides.keys())}"
                )

        # Initialize parameter suggester
        self.parameter_suggester = None
        if SUGGESTER_AVAILABLE:
            try:
                self.parameter_suggester = get_suggester_for_domain(workflow_domain, log)
                log.info(f"[QC Gate] Parameter suggester initialized for domain: {workflow_domain}")
            except Exception as e:
                log.warning(f"[QC Gate] Failed to initialize parameter suggester: {e}")

    # ------------------------------------------------------------------
    # QC override support (Phase 1)
    # ------------------------------------------------------------------

    @classmethod
    def validate_qc_overrides(cls, overrides: Dict[str, Any]) -> "tuple[bool, list]":
        """
        Validate user-provided QC overrides before persisting them.

        Returns:
            (valid: bool, errors: list[str])
        """
        errors = []
        for metric, value in overrides.items():
            if metric in QC_GOLD_METRICS:
                errors.append(
                    f"Cannot override GOLD metric '{metric}' — it is mandated by "
                    f"ENCODE4/GATK Best Practices and is not user-configurable. "
                    f"Contact your platform administrator to change it."
                )
            try:
                float(value)
            except (TypeError, ValueError):
                errors.append(
                    f"Override value for '{metric}' must be numeric, got: {value!r}"
                )
        return len(errors) == 0, errors

    @classmethod
    def validate_qc_profile(cls, profile_name: str) -> "tuple[bool, list]":
        """
        Validate that a named QC profile exists.

        Returns:
            (valid: bool, errors: list[str])
        """
        if profile_name not in QC_NAMED_PROFILES:
            known = sorted(QC_NAMED_PROFILES.keys())
            return False, [
                f"Unknown QC profile '{profile_name}'. "
                f"Known profiles: {', '.join(known)}"
            ]
        return True, []

    @classmethod
    def get_profile_overrides(cls, profile_name: str) -> Dict[str, Any]:
        """
        Return the threshold overrides for a named QC profile.

        Returns an empty dict for unknown profiles (caller should validate first).
        """
        profile = QC_NAMED_PROFILES.get(profile_name, {})
        return dict(profile.get("overrides", {}))

    @classmethod
    def list_profiles(cls) -> list:
        """
        Return a list of all named profiles with their metadata for the API endpoint.
        """
        return [
            {
                "id": name,
                "description": profile["description"],
                "domain_hint": profile.get("domain_hint", "unknown"),
                "overrides": profile.get("overrides", {}),
                "references": profile.get("references", []),
            }
            for name, profile in QC_NAMED_PROFILES.items()
        ]

    @classmethod
    def infer_qc_profile(cls, nextflow_path: str) -> "Optional[str]":
        """
        Auto-select a QC profile name from the Nextflow workflow path.
        Returns None if no profile can be inferred (caller uses platform defaults).
        """
        p = nextflow_path.lower()

        def _has(*keywords: str) -> bool:
            return any(k in p for k in keywords)

        # Drug discovery / compound
        if _has("admet", "docking", "pharmacokinetics", "nca", "toxicity", "drug"):
            return "compound_druglike"

        # Cryo-EM — check BEFORE genomics to avoid 'em' false matches
        if _has("cryoem", "cryo_em", "cryosparc", "relion", "ctf"):
            if _has("tomo", "tomography"):
                return "cryoem_tomo_in_situ"
            if _has("phase_plate", "vpp"):
                return "cryoem_spa_phase_plate"
            if _has("membrane", "lipid"):
                return "cryoem_spa_membrane"
            return "cryoem_spa_purified"

        # Somatic (must check BEFORE germline / wgs)
        if _has("somatic", "mutect", "tumor_normal", "cancer"):
            return "wgs_somatic_tumor_only"

        # WGS germline
        if _has("germline", "haplotypecaller", "deepvariant", "wgs"):
            if _has("lowpass", "low_pass", "lcwgs"):
                return "wgs_germline_lowpass"
            return "wgs_germline_standard"

        # WES
        if _has("wes", "exome", "exome_seq"):
            return "wes_research"

        # RNA-seq
        if _has("rnaseq", "rna_seq", "salmon", "star_align", "deseq", "featurecounts"):
            if _has("ffpe"):
                return "rnaseq_ffpe"
            if _has("snrna", "single_nucleus", "snuc"):
                return "rnaseq_single_nucleus"
            if _has("ribodepleted", "ribo_depletion"):
                return "rnaseq_ribodepleted"
            return "rnaseq_polya_standard"

        # scRNA-seq
        if _has("scrna", "scrnaseq", "cellranger", "seurat", "scanpy", "sc_rna"):
            if _has("perturb", "crispr"):
                return "scrna_perturbation"
            return "scrna_standard"

        # Proteomics
        if _has("proteomics", "maxquant", "diann", "spectronaut"):
            if _has("phospho"):
                return "proteomics_phospho"
            return "proteomics_standard"

        # Metagenomics
        if _has("metagenomics", "kraken", "metaphlan", "qiime", "16s"):
            return "metagenomics_human_gut"

        # Pharmacogenomics
        if _has("pgx", "pharmacogenomics"):
            return "pgx_research"

        return None

    def _get_threshold(self, metric: str, default: float) -> float:
        """
        Return the effective threshold for a metric, applying any user override.

        Lookup order (highest precedence first):
          1. GOLD check  — override silently ignored; returns *default*
          2. qc_overrides[metric] — applied if present and numeric
          3. Red-line clamp — override value clamped if it would cross a hard bound
          4. *default* — returned when no override is configured

        Args:
            metric:  Metric key (same keys used in qc_overrides dict)
            default: The platform-default threshold value
        """
        if not self.qc_overrides or metric not in self.qc_overrides:
            return default

        # GOLD metrics: override not permitted
        if metric in QC_GOLD_METRICS:
            log.warning(
                f"[QC Override] Ignoring override for GOLD metric '{metric}' "
                f"(ENCODE4/GATK mandated — not user-configurable)"
            )
            return default

        try:
            override_val = float(self.qc_overrides[metric])
        except (TypeError, ValueError):
            log.warning(
                f"[QC Override] Invalid override value for '{metric}': "
                f"{self.qc_overrides[metric]!r} — using default {default}"
            )
            return default

        # Red-line clamp
        if metric in QC_RED_LINES:
            rl = QC_RED_LINES[metric]
            if rl["direction"] == "min" and override_val < rl["bound"]:
                log.warning(
                    f"[QC Override] '{metric}' override {override_val} crosses red-line "
                    f"floor {rl['bound']} — clamped. Rationale: {rl['rationale']}"
                )
                override_val = rl["bound"]
            elif rl["direction"] == "max" and override_val > rl["bound"]:
                log.warning(
                    f"[QC Override] '{metric}' override {override_val} crosses red-line "
                    f"ceiling {rl['bound']} — clamped. Rationale: {rl['rationale']}"
                )
                override_val = rl["bound"]

        return override_val

    # Mapping: metric name → (yaml_domain, yaml_gate_name, advisory_or_fail).
    # Limited to the 4 modifier-aware gates added in Track 1 step 1
    # (docs/20260615_QC_GATE_INVENTORY_AND_PLAN.md). When a metric appears
    # here AND no explicit user override exists, the threshold is resolved
    # from qc_evidence.yaml modifiers using the active context. Other metrics
    # continue through the legacy default path.
    _MODIFIER_AWARE_METRICS: Dict[str, tuple] = {
        # (yaml_domain, yaml_gate_name, "advisory_min" or "fail_min")
        "herg_safety_margin_x":     ("ich_s7",         "ich_s7b_herg_margin",       "fail_min"),
        "eta_shrinkage_pct_max":    ("nlmixr2_poppk",  "nlmixr2_eta_shrinkage",     "fail_min"),
        "ofv_delta_max":            ("nlmixr2_poppk",  "nlmixr2_ofv_stability",     "fail_min"),
        "auc_extrap_pct_max":       ("nca_pk",         "nca_auc_extrap",            "fail_min"),
    }

    def _get_threshold_with_context(
        self,
        metric: str,
        default: float,
        context: Optional[Dict[str, Any]] = None,
    ) -> float:
        """
        Variant of _get_threshold that consults qc_evidence.yaml's modifiers
        block when no explicit user override exists. Falls through to the
        legacy _get_threshold flow when:
          - metric is not in _MODIFIER_AWARE_METRICS, OR
          - context is None / no axes match, OR
          - explicit user override already wins (handled by _get_threshold).

        `context` is a dict like {"indication_class": "chronic_cns"} or
        {"sampling_density": "sparse", "downstream_use": "vpc_only"}. Built
        from invocation metadata + the active QC profile; see
        _build_modifier_context() for the canonical translation.
        """
        # Explicit override + GOLD-metric protection short-circuit first —
        # users opt in to those paths explicitly.
        if self.qc_overrides and metric in self.qc_overrides:
            return self._get_threshold(metric, default)

        mapping = self._MODIFIER_AWARE_METRICS.get(metric)
        if mapping is None or not context:
            return default

        domain, gate_name, tier_key = mapping
        try:
            from galaxy.ai.retrievers.qc_evidence import resolve_thresholds
        except Exception:
            return default
        adv, fai = resolve_thresholds(
            domain, gate_name, context,
            default_advisory=default if tier_key == "advisory_min" else None,
            default_fail=default if tier_key == "fail_min" else None,
        )
        resolved = adv if tier_key == "advisory_min" else fai
        return float(resolved) if resolved is not None else default

    def _build_modifier_context(self) -> Dict[str, Any]:
        """
        Build the context dict for resolve_thresholds() from the invocation's
        currently-known metadata. Right now sources the active QC profile
        only; future plumbing (invocation submission API → trace monitor
        constructor) can attach indication / phase / sampling density etc.
        """
        ctx: Dict[str, Any] = {}
        # Profile → indication-class mapping (matches the YAML axis names).
        # compound_druglike is BioMate's general drug-discovery profile.
        profile_to_indication = {
            "compound_druglike":     "general",
            "antibiotic_screen":     "antibiotic_short_course",
            "oncology_screen":       "oncology_lifesaving",
            "cns_chronic":           "chronic_cns",
            "cardiac_chronic":       "chronic_cardiac",
        }
        if self.active_profile in profile_to_indication:
            ctx["indication_class"] = profile_to_indication[self.active_profile]
        # Phase modifier: profile names ending in '_regulatory' bump to that tier.
        if self.active_profile and self.active_profile.endswith("_regulatory"):
            ctx["phase"] = "regulatory"
        return ctx

    def _write_audit_log_entry(self, event_type: str, applied_overrides: Dict[str, Any]) -> None:
        """
        Append one JSONL record to work_dir/qc_overrides_audit.jsonl.

        The file is created on first write; each line is a self-contained JSON object
        so entries can be read incrementally without loading the whole file.
        """
        import json as _json
        audit_path = self.work_dir / "qc_overrides_audit.jsonl"
        entry: Dict[str, Any] = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "invocation_id": self.invocation_id,
            "event_type": event_type,
            "active_profile": self.active_profile,
            "configured_overrides": dict(self.qc_overrides),
            "applied_overrides": applied_overrides,
        }
        try:
            with open(audit_path, "a") as fh:
                fh.write(_json.dumps(entry) + "\n")
        except Exception as exc:
            log.warning(f"[QC Override] Failed to write audit log to {audit_path}: {exc}")

    def handle_process_completion(
        self,
        task_id: str,
        process_name: str,
        process_hash: str,
        status: str
    ):
        """
        Handle completion of a Nextflow process.

        Args:
            task_id: Nextflow task ID
            process_name: Name of the process
            process_hash: Process hash
            status: Completion status (COMPLETED, FAILED, etc.)
        """
        # Skip if already checked
        check_key = f"{process_name}:{task_id}"
        if check_key in self.checked_processes:
            return

        self.checked_processes.add(check_key)

        log.info(f"[QC Gate] Process completed: {process_name} (task {task_id}, status {status})")

        # Only check QC for successfully completed processes
        if status != "COMPLETED":
            log.debug(f"[QC Gate] Skipping QC check for non-completed process: {status}")
            return

        # Calculate QC metrics for this process
        qc_metrics = self._calculate_qc_metrics(process_name, task_id, process_hash)

        if not qc_metrics:
            log.debug(f"[QC Gate] No QC metrics calculated for {process_name}")
            return

        # Check if QC thresholds are met
        qc_passed, all_failures = self._check_qc_thresholds(process_name, qc_metrics)

        # Separate hard (blocking) failures from advisory informational items
        blocking_failures = [f for f in all_failures if not f.get("advisory", False)]
        advisory_items = [f for f in all_failures if f.get("advisory", False)]

        # Emit SSE event based on whether hard (blocking) failures exist
        if not qc_passed:
            log.warning(f"[QC Gate] TRIGGERED for {process_name}: {blocking_failures}")
            # Pass all_failures (blocking + advisory) so the gate modal can display full context.
            # Frontend distinguishes advisory items via the advisory=True flag for different styling.
            self._emit_qc_gate_event(process_name, qc_metrics, all_failures)
        else:
            log.info(f"[QC Gate] PASSED for {process_name}")
            # When no hard failures: advisory items + near-threshold warnings surface via warning event
            near_threshold = self._check_qc_warnings(process_name, qc_metrics)
            all_warnings = advisory_items + near_threshold
            if all_warnings:
                log.info(f"[QC Gate] Near-threshold/advisory warnings for {process_name}: {len(all_warnings)}")
                self._emit_qc_warning_event(process_name, qc_metrics, all_warnings)

        # ── Auto-loop enriched evaluation (drug discovery domains) ─────────────
        # Runs in addition to the existing QC gate system.  Produces autoloop_*
        # SSE events with per-gate rationale and literature citations.
        # Failures are non-blocking here — the bridge calls fail-open.
        try:
            from experiments.autoloop_bridge import evaluate_and_emit
            evaluate_and_emit(
                process_name=process_name,
                raw_metrics=qc_metrics,
                invocation_id=self.invocation_id,
                sse_callback=self.sse_callback,
                qc_profile=self.active_profile,
            )
        except ImportError:
            pass  # bridge not installed — skip silently
        except Exception as _al_exc:
            log.debug(f"[AutoLoop] Non-fatal evaluation error for {process_name}: {_al_exc}")

        # ── Gate-only evidence emission (HTS / ICH-S5 / ICH-S7 / BOIN / ───
        # allometric / IVIVE / OpenFE / p0_pkpd / pocket_detection /
        # aizynthfinder). Emits autoloop_gate_results SSE events for the
        # 10 QC-but-no-autoloop domains so their gates render with the
        # same hover-tooltip evidence as the auto-loop domains.
        try:
            from galaxy.ai.retrievers.qc_gate_emit import emit_gate_only_event
            emit_gate_only_event(
                process_name=process_name,
                qc_metrics=qc_metrics,
                sse_callback=self.sse_callback,
                invocation_id=self.invocation_id,
            )
        except Exception:
            pass  # fail-safe: never block the existing QC pipeline

    def _calculate_qc_metrics(
        self,
        process_name: str,
        task_id: str,
        process_hash: str
    ) -> Optional[Dict[str, Any]]:
        """
        Calculate QC metrics for a completed process.

        Attempts to extract real metrics from Nextflow work-directory output files.
        Returns None (no gate triggered) when real data cannot be read, so that
        missing-output does not silently produce fake pass/fail results.
        """
        # Build the per-task work subdirectory path from the process hash.
        # Nextflow creates:  work_dir/<ab>/<full_hash>/  for trace hash "ab/shortprefix"
        # The trace file truncates the hash — glob for the matching subdirectory.
        if process_hash and "/" in process_hash:
            prefix, rest = process_hash.split("/", 1)
            prefix_dir = self.work_dir / prefix
            if prefix_dir.is_dir():
                # Find subdirectory whose name starts with the abbreviated rest
                matches = sorted(prefix_dir.glob(f"{rest}*"))
                task_work_dir = matches[0] if matches else (prefix_dir / rest)
            else:
                task_work_dir = prefix_dir / rest
        else:
            task_work_dir = self.work_dir

        process_upper = process_name.upper()

        # For Batch runs, prefer S3-published reports. The old condition was
        #   `s3_outdir and not task_work_dir.is_dir()`,
        # but that skipped S3 whenever process_hash was empty (some workflows
        # configure trace.fields without "hash" — observed pocket_detection on
        # 2026-06-09) because task_work_dir then defaults to self.work_dir
        # which DOES exist locally. Symptom: "[QC Gate] No QC metrics
        # calculated" right after a clean COMPLETED event, no [QC-S3] line.
        # Try S3 first whenever s3_outdir is set; fall through to local
        # parsers only if S3 returned nothing.
        if self.s3_outdir:
            s3_metrics = self._read_s3_report_metrics(process_upper)
            if s3_metrics is not None:
                return s3_metrics

        # --- Cryo-EM ---
        if "MOTION_CORRECTION" in process_upper:
            return self._parse_motion_correction_metrics(task_work_dir)
        elif "CTF_ESTIMATION" in process_upper or "CTF_ESTIMATE" in process_upper:
            return self._parse_ctf_metrics(task_work_dir)
        elif "PARTICLE_PICKING" in process_upper or "PICKING" in process_upper:
            return self._parse_picking_metrics(task_work_dir)
        elif any(k in process_upper for k in ("CLASSIFY_2D", "CLASS_2D", "2D_CLASSIFICATION",
                                               "2DCLASSIFICATION")):
            return self._parse_2d_classification_metrics(task_work_dir)
        elif any(k in process_upper for k in ("HOMOGENEOUS_REFINEMENT", "NONUNIFORM_REFINEMENT",
                                               "HETEROGENEOUS_REFINEMENT", "VALIDATION_FSC",
                                               "LOCAL_CTF_REFINEMENT", "AB_INITIO")):
            return self._parse_refinement_metrics(task_work_dir)
        elif any(k in process_upper for k in ("SHARPEN", "CTF_REFINE_SHARPEN",
                                               "POSTPROCESS", "POSTPROCESSING")):
            return self._parse_sharpening_metrics(task_work_dir)
        elif any(k in process_upper for k in ("MOLPROBITY", "EMRINGER", "MODEL_QUALITY", "MODEL_VALIDATION", "ALPHAFOLD_FIT")):
            return self._parse_model_quality_metrics(task_work_dir)
        elif any(k in process_upper for k in ("LOCAL_RESOLUTION", "LOCALRES",
                                               "MONORES", "RESMAP")):
            return self._parse_local_resolution_metrics(task_work_dir)

        # --- RNA-seq / general sequencing quality ---
        elif any(k in process_upper for k in ("FASTQC", "MULTIQC")):
            return self._parse_fastqc_metrics(task_work_dir)
        elif any(k in process_upper for k in ("FASTP", "TRIMGALORE", "TRIMMOMATIC", "BBDUK")):
            return self._parse_trimming_metrics(task_work_dir)
        elif any(k in process_upper for k in ("STAR_ALIGN", "STAR_GENOME", "HISAT2_ALIGN",
                                               "HISAT2", "BOWTIE2_ALIGN", "BOWTIE2")):
            return self._parse_alignment_metrics(task_work_dir)
        elif any(k in process_upper for k in ("FEATURECOUNTS", "SUBREAD", "HTSEQ")):
            return self._parse_featurecounts_metrics(task_work_dir)
        elif any(k in process_upper for k in ("SALMON_QUANT", "SALMON", "KALLISTO")):
            return self._parse_salmon_metrics(task_work_dir)

        # --- DNA-seq / variant calling ---
        elif any(k in process_upper for k in ("FLAGSTAT", "SAMTOOLS_FLAGSTAT", "SAMTOOLS_STATS")):
            return self._parse_flagstat_metrics(task_work_dir)
        elif any(k in process_upper for k in ("MARKDUPLICATES", "PICARD_MARKDUP",
                                               "MARKDUP", "GATK_MARKDUP")):
            return self._parse_picard_dup_metrics(task_work_dir)
        elif any(k in process_upper for k in ("BWA_MEM", "BWA_MEM2", "BWAMEM")):
            return self._parse_alignment_metrics(task_work_dir)
        elif any(k in process_upper for k in ("MOSDEPTH", "SAMTOOLS_COVERAGE",
                                               "GATK_COVERAGE", "PICARD_WGS")):
            return self._parse_coverage_metrics(task_work_dir)

        # --- CRISPR screen / Perturb-seq guide library ---
        elif any(k in process_upper for k in ("MAGECK_COUNT", "MAGECK_MLE", "MAGECK_TEST", "CRISPRRESSO", "GUIDE_ASSIGN", "PERTURB_SEQ")):
            return self._parse_guide_library_metrics(task_work_dir)

        # --- Single-cell RNA-seq ---
        elif any(k in process_upper for k in ("CELLRANGER_COUNT", "CELLRANGER",
                                               "STARSOLO", "ALEVIN")):
            return self._parse_singlecell_metrics(task_work_dir)

        # --- ChIP-seq / ATAC-seq ---
        elif any(k in process_upper for k in ("MACS2", "MACS3", "CALLPEAK")):
            return self._parse_peakcalling_metrics(task_work_dir)
        elif any(k in process_upper for k in ("ATAC_QC", "TSS_ENRICH", "ATAC_PEAK",
                                               "DEEPTOOLS_PLOTFINGERPRINT", "PLOTFINGERPRINT")):
            return self._parse_atac_metrics(task_work_dir)

        # --- Metagenomics ---
        elif any(k in process_upper for k in ("KRAKEN2", "KRAKEN", "BRACKEN",
                                               "METAPHLAN", "KAIJU")):
            return self._parse_metagenomics_metrics(task_work_dir)

        # --- Proteomics (LC-MS/MS) ---
        elif any(k in process_upper for k in ("MAXQUANT", "MAXQUANT_SEARCH",
                                               "MAXQUANT_ANDROMEDA")):
            return self._parse_maxquant_metrics(task_work_dir)
        elif any(k in process_upper for k in ("DIANN", "DIANN_CONVERT", "SPECTRONAUT",
                                               "DIANN_SEARCH")):
            return self._parse_diann_metrics(task_work_dir)
        elif any(k in process_upper for k in ("PULLDOWN_QC", "CHEMOPROTEOMICS_QC",
                                               "ENRICHMENT_QC", "PULLDOWN_ANALYSIS",
                                               "CHEMOPROTEOMICS_PULLDOWN", "ABPP_PULLDOWN",
                                               "ABPP", "PULLDOWN")):
            return self._parse_pulldown_metrics(task_work_dir)

        # --- Disease-state PBPK (renal/hepatic impairment dosing) ---
        elif any(k in process_upper for k in ("PBPK_DISEASE_STATE", "DISEASE_STATE_PK",
                                               "RENAL_IMPAIRMENT_PBPK", "HEPATIC_IMPAIRMENT_PBPK")):
            return self._parse_disease_state_results(task_work_dir)

        # --- Biomarker patient enrichment (predictive enrichment, Phase III design) ---
        elif any(k in process_upper for k in ("BIOMARKER_PATIENT_ENRICHMENT",
                                               "PREDICTIVE_ENRICHMENT", "BIOMARKER_ENRICHMENT")):
            return self._parse_biomarker_enrichment_results(task_work_dir)

        # --- Polymorph stability screening (solid-state risk, ICH Q6A) ---
        elif any(k in process_upper for k in ("POLYMORPH_STABILITY_SCREENING",
                                               "POLYMORPH_SCREENING", "CRYSTAL_FORM_SCREEN",
                                               "SOLID_STATE_SCREEN")):
            return self._parse_polymorph_stability_results(task_work_dir)

        # --- Cheminformatics / compound structure QC ---
        elif any(k in process_upper for k in ("SMILES_QC", "COMPOUND_QC", "STRUCTURE_QC",
                                               "ADMET_PRECHECK", "DOCKING_PRECHECK")):
            return self._parse_smiles_metrics(task_work_dir)

        # --- ADMET toxicity safety gates (hERG, DILI, Ames, ClinTox) ---
        elif any(k in process_upper for k in ("ADMET_TOXICITY", "HERG_SCREEN", "DILI_SCREEN",
                                               "TOXICITY_SCREEN", "ADMET_PRED",
                                               "PREDICT_ADMET", "ADMET_SAFETY")):
            return self._parse_admet_toxicity_metrics(task_work_dir)

        # --- CYP DDI risk assessment (R1/R2 inhibition flags) ---
        elif any(k in process_upper for k in ("CYP_INHIBITION", "DDI_RISK_ASSESSMENT",
                                               "CYP_PANEL", "DDI_RISK", "DDI_ASSESSMENT",
                                               "CYP_DDI", "DDI_REPORT")):
            return self._parse_cyp_ddi_results(task_work_dir)

        # --- Pharmacogenomics CYP gene coverage (sequencing depth, not DDI) ---
        elif any(k in process_upper for k in ("PGX_COVERAGE", "CYP_COVERAGE",
                                               "PHARMACOGENOMICS_QC", "PGX_QC")):
            return self._parse_pgx_coverage_metrics(task_work_dir)

        # --- PBPK simulation (PK-Sim, BioMate native, Simcyp fallback) ---
        elif any(k in process_upper for k in ("PK_SIM", "PKSIM", "PBPK_SIMULATION",
                                               "PBPK_SIM", "NCA_ANALYSIS",
                                               "PK_REPORT", "GENERATE_PK_REPORT")):
            return self._parse_pbpk_results(task_work_dir)

        # --- Non-compartmental analysis (PKNCA) ---
        elif any(k in process_upper for k in ("NCA_PKNCA", "NONCOMPARTMENTAL", "PKNCA")):
            return self._parse_nca_results(task_work_dir)

        # --- Population pharmacokinetics (nlmixr2 / SAEM) ---
        elif any(k in process_upper for k in ("NLMIXR2", "POPULATION_PK",
                                               "POP_PK", "POPPK", "POPK")):
            return self._parse_nlmixr2_results(task_work_dir)

        # --- IVIVE hepatic clearance scaling ---
        elif any(k in process_upper for k in ("IVIVE", "HEPATIC_CLEARANCE",
                                               "IVIVE_HEPATIC", "CLEARANCE_SCALING")):
            return self._parse_ivive_results(task_work_dir)

        # --- Molecular docking ---
        elif any(k in process_upper for k in ("MOLECULAR_DOCKING", "DOCKING",
                                               "AUTODOCK", "VINA", "GLIDE")):
            return self._parse_docking_results(task_work_dir)

        # --- QSAR modelling ---
        elif any(k in process_upper for k in ("QSAR_RF_MODEL", "QSAR_MODEL", "QSAR",
                                               "CHEMPROP", "DEEPCHEM")):
            return self._parse_qsar_results(task_work_dir)

        else:
            # ── Generic gate-only fallback (2026-05-27) ─────────────────
            # When no domain-specific parser matched, look for a
            # qc_metrics.json artifact in the task work dir. This is the
            # entry point for the 20+ gate-only domains whose main.nf
            # already writes qc_metrics.json but for which no dedicated
            # parser exists above. Without this, handle_process_completion
            # early-returns and emit_gate_only_event never runs.
            for candidate in ("qc_metrics.json", "qc.json", "qc_report.json"):
                p = Path(task_work_dir) / candidate
                if p.is_file():
                    try:
                        import json as _json
                        with open(p) as _f:
                            blob = _json.load(_f)
                        if isinstance(blob, dict) and blob:
                            return blob
                    except Exception:
                        continue
            return None

    # ── S3 published report reader ────────────────────────────────────────────
    # For AWS Batch runs, task work dirs are on S3. Our pipeline publishes
    # structured JSON report files to s3_outdir that contain the same metrics
    # the local parsers extract. This method reads those published files.

    # Maps process name keywords → (s3_step_prefix, report_glob_pattern)
    _S3_REPORT_PATHS: Dict[str, tuple] = {
        "MOTION_CORRECTION": ("02_motion_correction", "motion_report_*.json"),
        "CTF_ESTIMATION":    ("03_ctf_estimation",    "ctf_report_*.json"),
        "CTF_ESTIMATE":      ("03_ctf_estimation",    "ctf_report_*.json"),
        "BLOB_PICKER":       ("05_blob_picker",       "picking_report_*.json"),
        "PARTICLE_PICKING":  ("05_blob_picker",       "picking_report_*.json"),
        "JUNK_DETECTOR":     ("06_junk_detector",     "junk_report.json"),
        "INSPECT_PICKS":     ("07_inspect_picks_round1", "inspect_report.json"),
        "EXTRACT":           ("08_extract_round1",    "extract_report_*.json"),
        "CLASSIFY_2D":       ("09_classify_2d_round1", "class2d_report_*.json"),
        "CLASS_2D":          ("09_classify_2d_round1", "class2d_report_*.json"),
        "SELECT_2D":         ("10_select_2d_round1",  "selection_report.json"),
        "AB_INITIO":         ("16_ab_initio",         "ab_initio_report_*.json"),
        "HOMOGENEOUS_REFINEMENT": ("17_homogeneous_refinement", "refinement_report_*.json"),
        "NONUNIFORM_REFINEMENT":  ("21_non_uniform_refinement", "nu_refinement_report.json"),
        "VALIDATION_FSC":    ("19_validation_fsc",   "validation_report.json"),
        # RNA-seq / nf-core: MultiQC aggregates these → read multiqc_data JSON
        "STAR_ALIGN":        ("star", "Log.final.out"),
        "FASTQC":            ("fastqc", "*_fastqc_data.json"),
        "FASTP":             ("fastp", "*.json"),
        "FEATURECOUNTS":     ("featurecounts", "*.summary"),
        "SALMON":            ("salmon", "lib_format_counts.json"),
        "SAMTOOLS_FLAGSTAT": ("samtools", "*.flagstat"),
        # Gate-only workflows that publish qc_metrics.json directly under
        # <publishDir>/<meta.id>/. Wildcard "*" matches any meta.id value.
        # Add per workflow as each gains a real qc_metrics.json emission
        # (see docs/20260607_QC_EVIDENCE_AUDIT_PASS_2.md for the
        # corresponding gate provenance grading).
        "HTS_PLATE_QC_HIT_CALLING":  ("*", "qc_metrics.json"),  # HTS Z' (Zhang 1999, GOLD)
        "ALLOMETRIC_SCALING":        ("*", "qc_metrics.json"),  # R² (FDA 2005 FIH, SILVER — value is operational)
        "DART_IN_SILICO_PREDICTION": ("*", "qc_metrics.json"),  # ICH S5R3 margin ≥10× Cmax (GOLD)
        "ICH_S7A_ASSESS_CV":         ("*", "qc_metrics.json"),  # ICH S7B hERG ≥10× free Cmax (GOLD)
        "DRUGGABILITY_QC_GATE":      ("*", "qc_metrics.json"),  # fpocket druggability ≥0.5 (GOLD, Le Guilloux 2009)
        "RETROSYNTHESIS_REPORT":     ("*", "qc_metrics.json"),  # aizynthfinder ≥1 solved route (GOLD, Genheden 2020)
        "P0_PKPD_SEMAGLUTIDE":       ("*", "qc_metrics.json"),  # semaglutide wk30 Δweight ∈ [-6,+3] kg (GOLD, Overgaard 2019)
        "CLINICAL_TRIAL_SIMULATION": ("*", "qc_metrics.json"),  # BOIN MTD DLT≤φ (GOLD, Liu & Yuan 2015)
        "BOLTZ_SUMMARISE_RESULTS":   ("*", "qc_metrics.json"),  # Boltz pLDDT ≥70 / PAE ≤8Å (GOLD, Jumper 2021)
        "LNP_FORMULATION_OPTIMIZATION": ("*", "qc_metrics.json"),  # LNP z-avg 60-120 nm (SILVER, CLT range)
        "ANTIBODY_DEVELOPABILITY":   ("*", "qc_metrics.json"),  # TAP total CDR 43-63 (GOLD, Raybould 2019)
        "SIRNA_OFFTARGET_ANALYSIS":  ("*", "qc_metrics.json"),  # ΔdG asymmetry ≥0.5 (GOLD, Khvorova 2003)
        "NLMIXR2_POPULATION_PK":     ("*", "qc_metrics.json"),  # η-shrinkage <20% (GOLD, Savic & Karlsson 2007)
        "BIOMARKER_PATIENT_ENRICHMENT": ("*", "qc_metrics.json"),  # prev 0.10-0.50 (SILVER, FDA 2019), EF≥1.5 (BRONZE)
        "IVIVE_HEPATIC_CLEARANCE":   ("*", "qc_metrics.json"),  # ivive_fold_error ≤ 2 (GOLD, Obach 1999)
        "PREDICT_ADMET_PROPERTIES":  ("*", "qc_metrics.json"),  # hERG ≥10μM (GOLD, Redfern 2003) / Ames neg (SILVER, Kazius 2005) / DILI
        "DDI_RISK_ASSESSMENT":       ("*", "qc_metrics.json"),  # FDA 2020 DDI R1/R2 INVESTIGATE/CLINICAL_STUDY (GOLD)
        "NCA_PKNCA_ANALYSIS":        ("*", "qc_metrics.json"),  # auc_extrap_pct_max ≤ 20% (GOLD, FDA 2003 BA/BE)
        "PBPK_SIMULATION":           ("*", "qc_metrics.json"),  # tmax_fraction ≤ 0.8 (SILVER, FDA 2018 PBPK)
        "GENOTOXICITY_AMES_PREDICTION": ("*", "qc_metrics.json"),  # Ames clean = 0 POSITIVE / 0 SUSPECT (SILVER, Kazius 2005 / ICH S2R1)
    }

    def _read_s3_report_metrics(self, process_upper: str) -> Optional[Dict[str, Any]]:
        """
        Read QC metrics from published S3 report files.
        Returns a metrics dict compatible with _check_qc_thresholds, or None if not found.
        """
        if not self.s3_outdir:
            return None

        try:
            import boto3 as _boto3
            import json as _json
            import fnmatch as _fnmatch

            s3 = _boto3.client("s3", region_name=__import__("os").environ.get("AWS_DEFAULT_REGION", "us-west-2"))
            parts = self.s3_outdir[5:].split("/", 1)
            bucket = parts[0]
            prefix_base = parts[1].rstrip("/") if len(parts) > 1 else ""

            # Find matching step prefix and report pattern
            step_prefix = None
            report_pattern = None
            for keyword, (step, pattern) in self._S3_REPORT_PATHS.items():
                if keyword in process_upper:
                    step_prefix = step
                    report_pattern = pattern
                    break

            if not step_prefix:
                return None

            # List objects under s3_outdir/step_prefix/
            # Wildcard "*" step_prefix means "match any first-level subdir"
            # (gate-only workflows like HTS publish to <outdir>/${meta.id}/
            # where meta.id varies; we don't know it until we list).
            if step_prefix == "*":
                search_prefix = f"{prefix_base}/" if prefix_base else ""
            else:
                search_prefix = f"{prefix_base}/{step_prefix}/" if prefix_base else f"{step_prefix}/"
            resp = s3.list_objects_v2(Bucket=bucket, Prefix=search_prefix)
            report_objects = [
                obj["Key"] for obj in resp.get("Contents", [])
                if _fnmatch.fnmatch(obj["Key"].split("/")[-1], report_pattern)
            ]

            if not report_objects:
                log.info("[QC-S3] No report found for %s at s3://%s/%s%s",
                         process_upper, bucket, search_prefix, report_pattern)
                return None
            log.info("[QC-S3] Reading report for %s from s3://%s/%s",
                     process_upper, bucket, report_objects[-1])

            # Read the first matching report (take most recent by key name)
            report_objects.sort()
            key = report_objects[-1]
            obj = s3.get_object(Bucket=bucket, Key=key)
            data = _json.loads(obj["Body"].read().decode("utf-8"))

            # Convert JSON report to QC metrics dict
            return self._report_json_to_metrics(process_upper, data)

        except Exception as _e:
            log.warning("[QC-S3] Error reading S3 report for %s: %s", process_upper, _e)
            return None

    def _report_json_to_metrics(self, process_upper: str, data: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Convert a published pipeline JSON report to a QC metrics dict."""
        metrics: Dict[str, Any] = {}

        if "MOTION_CORRECTION" in process_upper:
            if "avg_total_motion_A" in data:
                metrics["total_drift_angstrom"] = data["avg_total_motion_A"]
            if "per_micrograph_motion_A" in data:
                arr = data["per_micrograph_motion_A"]
                if arr:
                    import statistics as _st
                    metrics.setdefault("total_drift_angstrom", round(_st.mean(arr), 2))
            if "num_micrographs" in data:
                metrics["n_micrographs"] = data["num_micrographs"]

        elif "CTF_ESTIMATION" in process_upper or "CTF_ESTIMATE" in process_upper:
            if "avg_fit_quality" in data:
                metrics["fit_quality"] = data["avg_fit_quality"]
            elif "avg_ctf_fit_to_A" in data:
                fit_a = float(data["avg_ctf_fit_to_A"])
                metrics["fit_quality"] = round(max(0.0, 1.0 - fit_a / 10.0), 3)
            if "avg_defocus_A" in data:
                metrics["defocus_u_angstrom"] = data["avg_defocus_A"]
                metrics["defocus_out_of_range"] = not (1000 <= data["avg_defocus_A"] <= 100000)
            if "avg_astigmatism_A" in data:
                metrics["astigmatism_angstrom"] = data["avg_astigmatism_A"]
            if "per_micrograph_defocus_A" in data:
                arr = data["per_micrograph_defocus_A"]
                if arr:
                    import statistics as _st
                    metrics.setdefault("defocus_u_angstrom", round(_st.mean(arr), 0))

        elif any(k in process_upper for k in ("PICKING", "BLOB_PICKER")):
            if "num_particles" in data:
                metrics["particles_picked"] = data["num_particles"]
            if "num_micrographs" in data and data["num_micrographs"] > 0:
                metrics["particle_density_per_micrograph"] = round(
                    data.get("num_particles", 0) / data["num_micrographs"], 1)

        elif any(k in process_upper for k in ("CLASSIFY_2D", "CLASS_2D")):
            if "num_particles" in data:
                metrics["particles_2d_classified"] = data["num_particles"]
            if "junk_class_fraction" in data:
                metrics["junk_class_fraction"] = data["junk_class_fraction"]
                metrics["good_class_fraction"] = round(1.0 - data["junk_class_fraction"], 3)

        elif any(k in process_upper for k in ("STAR_ALIGN",)):
            # Parse STAR Log.final.out: "Uniquely mapped reads %" line
            log_text = data.get("_raw_text", "")
            for line in log_text.splitlines():
                if "Uniquely mapped reads %" in line:
                    try:
                        metrics["alignment_rate"] = float(line.split("|")[-1].strip().rstrip("%"))
                    except (ValueError, IndexError):
                        pass

        elif "FASTQC" in process_upper:
            if "basic_statistics" in data:
                total = data.get("basic_statistics", {}).get("Total Sequences", 0)
                if total:
                    metrics["total_reads"] = total

        elif "FASTP" in process_upper:
            summary = data.get("summary", {})
            if "after_filtering" in summary and "before_filtering" in summary:
                after = summary["after_filtering"].get("total_reads", 0)
                before = summary["before_filtering"].get("total_reads", 1)
                if before > 0:
                    metrics["reads_surviving_pct"] = round(after / before * 100, 1)

        elif "SAMTOOLS_FLAGSTAT" in process_upper or "FLAGSTAT" in process_upper:
            raw = data.get("_raw_text", "")
            for line in raw.splitlines():
                if "mapped (" in line and "%" in line:
                    try:
                        pct_str = line.split("(")[1].split("%")[0].strip()
                        metrics["mapped_pct"] = float(pct_str.lstrip("+").strip())
                    except (IndexError, ValueError):
                        pass

        # Gate-only domains (HTS, ICH-S5/S7, BOIN, allometric, IVIVE, OpenFE,
        # p0_pkpd, pocket_detection, aizynthfinder) emit qc_metrics.json with
        # keys that already match gate thresholds (z_prime, signal_window, etc).
        # Pass scalars through if no domain-specific case populated metrics.
        if not metrics and any(k in process_upper for k in self._S3_REPORT_PATHS):
            for k, v in data.items():
                if isinstance(v, (int, float, bool, str)):
                    metrics[k] = v

        return metrics if metrics else None

    def _parse_motion_correction_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse motion correction log files (MotionCor2 / RELION Motioncorr output).
        Falls back to None when files are absent so the QC gate is not triggered.
        """
        metrics: Dict[str, Any] = {}

        # MotionCor2 writes a *_DW.log or *_Full.log with per-frame shifts
        log_files = list(task_work_dir.glob("*.log")) + list(task_work_dir.glob("*_motion.txt"))
        for log_file in log_files:
            try:
                text = log_file.read_text(errors="replace")
                # Total drift: look for "Total motion:" or "Global drift:"
                for line in text.splitlines():
                    line_lower = line.lower()
                    if "total motion" in line_lower or "global drift" in line_lower:
                        parts = line.split()
                        for p in parts:
                            try:
                                val = float(p)
                                if 0 < val < 500:  # plausible angstrom value
                                    metrics["total_drift_angstrom"] = val
                                    break
                            except ValueError:
                                pass
                    elif "correlation" in line_lower or "score" in line_lower:
                        parts = line.split()
                        for p in parts:
                            try:
                                val = float(p)
                                if 0.0 <= val <= 1.0:
                                    metrics.setdefault("correlation_score", val)
                                    break
                            except ValueError:
                                pass
            except OSError:
                continue

        if not metrics:
            # No readable output — do not trigger the QC gate
            log.debug(f"[QC] No motion correction metrics found in {task_work_dir}")
            return None

        if "total_drift_angstrom" in metrics:
            n_frames = metrics.get("n_frames", 40)
            metrics.setdefault(
                "drift_per_frame_angstrom",
                round(metrics["total_drift_angstrom"] / max(n_frames, 1), 2)
            )
        return metrics

    def _parse_ctf_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse CTF estimation output.

        Primary sources (tried in order):
        1. micrographs_ctf.cs — CryoSPARC per-micrograph JSON (SPA pipeline).
           Key fields: defocus_u_angstroms, astigmatism_angstroms, ctf_cross_correlation.
        2. ctf_report.json — SPA pipeline summary JSON.
        3. *.txt / *_ctf.log — CTFFIND4 / Gctf text format.

        Note on scale: CryoSPARC ctf_cross_correlation is typically 0.05-0.20 for good
        micrographs; CTFFIND4 fit_score is 0-1 with 0.7 as the pass threshold.  The two
        metrics are stored under different keys so gates are calibrated separately.
        """
        metrics: Dict[str, Any] = {}

        # --- CryoSPARC .cs JSON (per-micrograph array) ---
        for cs_file in (list(task_work_dir.glob("micrographs_ctf.cs"))
                        + list(task_work_dir.glob("**/micrographs_ctf.cs"))):
            try:
                data = json.loads(cs_file.read_text(errors="replace"))
                mics = data.get("micrographs", [])
                if not mics:
                    continue

                def _mean(key):
                    vals = [m[key] for m in mics if isinstance(m.get(key), (int, float))]
                    return round(sum(vals) / len(vals), 4) if vals else None

                du = _mean("defocus_u_angstroms")
                dv = _mean("defocus_v_angstroms")
                astig = _mean("astigmatism_angstroms")
                cc = _mean("ctf_cross_correlation")

                if du is not None:
                    metrics["defocus_u_angstrom"] = du
                if dv is not None:
                    metrics["defocus_v_angstrom"] = dv
                if astig is not None:
                    metrics["astigmatism_angstrom"] = round(astig, 1)
                # ctf_cross_correlation is NOT the same scale as CTFFIND4 fit_score;
                # stored under its own key so gates use the correct threshold.
                if cc is not None:
                    metrics["ctf_cross_correlation"] = cc
                if metrics:
                    log.debug(f"[QC] CTF (CryoSPARC cs): defocus={du} Å, CC={cc}")
                    return metrics
            except (OSError, json.JSONDecodeError, KeyError):
                continue

        # --- CryoSPARC summary JSON (ctf_report.json) ---
        for json_file in (list(task_work_dir.glob("ctf_report.json"))
                          + list(task_work_dir.glob("**/ctf_report.json"))):
            try:
                data = json.loads(json_file.read_text(errors="replace"))
                avg_defocus = data.get("avg_defocus_angstroms")
                if avg_defocus is not None:
                    try:
                        metrics["defocus_u_angstrom"] = float(avg_defocus)
                    except (ValueError, TypeError):
                        pass
                # Phase plate data (emitted when params.phase_plate=true in SPA pipeline)
                phase_shift = data.get("avg_phase_shift_rad")
                if phase_shift is not None:
                    try:
                        metrics["avg_phase_shift_rad"] = float(phase_shift)
                    except (ValueError, TypeError):
                        pass
                # Also check degrees form and convert (VPP hardware often reports in degrees)
                phase_shift_deg = data.get("avg_phase_shift_degrees")
                if phase_shift_deg is not None and "avg_phase_shift_rad" not in metrics:
                    import math as _math
                    try:
                        metrics["avg_phase_shift_rad"] = round(
                            float(phase_shift_deg) * _math.pi / 180.0, 4
                        )
                    except (ValueError, TypeError):
                        pass
                if metrics:
                    log.debug(
                        f"[QC] CTF (ctf_report.json): avg_defocus={avg_defocus} Å, "
                        f"phase_shift={metrics.get('avg_phase_shift_rad')} rad"
                    )
                    return metrics
            except (OSError, json.JSONDecodeError):
                continue

        # CTFFIND4 diagnostic output: each data line has
        # DefocusU  DefocusV  Astigmatism_angle  PhaseShift  FitScore
        # Multi-micrograph files have one result per line — scan from last to
        # first so that a bad final line does not silently discard valid data.
        for txt_file in list(task_work_dir.glob("*.txt")) + list(task_work_dir.glob("*_ctf.log")):
            try:
                lines = [l for l in txt_file.read_text(errors="replace").splitlines() if l.strip()]
                valid_result: Dict[str, Any] = {}
                oor_fallback: Dict[str, Any] = {}
                for line in reversed(lines):
                    parts = line.split()
                    if len(parts) >= 5:
                        try:
                            defocus_u = float(parts[0])
                            defocus_v = float(parts[1])
                            astig = abs(defocus_u - defocus_v)
                            fit_score = float(parts[4])
                            if 1000 < defocus_u < 100000:  # plausible angstrom
                                valid_result["defocus_u_angstrom"] = defocus_u
                                valid_result["defocus_v_angstrom"] = defocus_v
                                valid_result["astigmatism_angstrom"] = round(astig, 1)
                                valid_result["fit_quality"] = min(1.0, max(0.0, fit_score))
                                break  # Found valid in-range; stop scanning
                            elif defocus_u > 0 and not oor_fallback:
                                # Record OOR as fallback; keep scanning for valid in-range line
                                oor_fallback["defocus_u_angstrom"] = defocus_u
                                oor_fallback["defocus_v_angstrom"] = defocus_v
                                oor_fallback["astigmatism_angstrom"] = round(astig, 1)
                                oor_fallback["fit_quality"] = min(1.0, max(0.0, fit_score))
                                oor_fallback["defocus_out_of_range"] = True
                                oor_fallback["defocus_direction"] = "below" if defocus_u <= 1000 else "above"
                        except ValueError:
                            pass
                metrics.update(valid_result or oor_fallback)
                if metrics:
                    break
            except OSError:
                continue

        if not metrics:
            log.debug(f"[QC] No CTF metrics found in {task_work_dir}")
            return None

        return metrics

    def _parse_picking_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse particle picking output (STAR files / crYOLO JSON).
        Falls back to None when files are absent.
        """
        metrics: Dict[str, Any] = {}

        # Count coordinates in STAR or box files
        coordinate_files = (
            list(task_work_dir.glob("*.star"))
            + list(task_work_dir.glob("*.box"))
            + list(task_work_dir.glob("*.coords"))
        )

        total_particles = 0
        n_micrographs = 0
        for coord_file in coordinate_files:
            try:
                lines = [l for l in coord_file.read_text(errors="replace").splitlines()
                         if l.strip() and not l.startswith("_") and not l.startswith("#")]
                count = len([l for l in lines if l[0].isdigit() or l[0] == '-'])
                if count > 0:
                    total_particles += count
                    n_micrographs += 1
            except OSError:
                continue

        if total_particles == 0 and n_micrographs == 0:
            log.debug(f"[QC] No picking metrics found in {task_work_dir}")
            return None

        metrics["particles_picked"] = total_particles
        if n_micrographs > 0:
            metrics["particle_density_per_micrograph"] = round(
                total_particles / n_micrographs, 1
            )
        # Duplicate fraction requires NMS data — not available here, default to 0
        metrics["duplicate_fraction"] = 0.0
        return metrics

    # ------------------------------------------------------------------
    # RNA-seq / sequencing quality parsers
    # ------------------------------------------------------------------

    def _parse_fastqc_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse FastQC summary.txt or fastqc_data.txt.
        Returns per-base quality, GC%, adapter contamination flag.
        """
        metrics: Dict[str, Any] = {}

        # FastQC writes summary.txt with PASS/WARN/FAIL per module
        for summary_file in list(task_work_dir.glob("*/summary.txt")) + list(task_work_dir.glob("summary.txt")):
            try:
                lines = summary_file.read_text(errors="replace").splitlines()
                failed_modules = [l.split("\t")[1] for l in lines if l.startswith("FAIL")]
                warned_modules = [l.split("\t")[1] for l in lines if l.startswith("WARN")]
                if failed_modules or warned_modules:
                    metrics["failed_modules"] = failed_modules
                    metrics["warned_modules"] = warned_modules
                    metrics["module_failures"] = len(failed_modules)
            except OSError:
                continue

        # FastQC data: look for %GC and basic stats
        for data_file in list(task_work_dir.glob("*/fastqc_data.txt")) + list(task_work_dir.glob("fastqc_data.txt")):
            try:
                text = data_file.read_text(errors="replace")
                for line in text.splitlines():
                    if line.startswith("%GC"):
                        try:
                            metrics["gc_content_pct"] = float(line.split("\t")[1])
                        except (ValueError, IndexError):
                            pass
                    elif "Total Sequences" in line:
                        try:
                            metrics["total_sequences"] = int(line.split("\t")[1])
                        except (ValueError, IndexError):
                            pass
            except OSError:
                continue

        # MultiQC JSON aggregation
        for mq_file in list(task_work_dir.glob("multiqc_data.json")) + list(task_work_dir.glob("**/multiqc_data.json")):
            try:
                import json as _json
                mq = _json.loads(mq_file.read_text(errors="replace"))
                general = mq.get("report_general_stats_data", [{}])
                if general and isinstance(general, list):
                    sample = next(iter(general[0].values()), {}) if general[0] else {}
                    if "percent_gc" in sample:
                        metrics.setdefault("gc_content_pct", sample["percent_gc"])
                    if "avg_sequence_length" in sample:
                        metrics["avg_read_length"] = sample["avg_sequence_length"]
            except Exception:
                continue

        if not metrics:
            return None
        return metrics

    def _parse_trimming_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse FASTP JSON, Trimmomatic log, TrimGalore log.
        Key metric: fraction of reads surviving trimming.
        """
        metrics: Dict[str, Any] = {}

        # FASTP writes fastp.json
        for fp_file in list(task_work_dir.glob("*.json")) + list(task_work_dir.glob("fastp.json")):
            try:
                import json as _json
                data = _json.loads(fp_file.read_text(errors="replace"))
                filt = data.get("filtering_result", {})
                summary = data.get("summary", {})
                total_in = summary.get("before_filtering", {}).get("total_reads", 0)
                passed = filt.get("passed_filter_reads", 0)
                if total_in > 0:
                    metrics["reads_surviving_pct"] = round(100.0 * passed / total_in, 2)
                    metrics["total_reads_in"] = total_in
                    q30 = summary.get("before_filtering", {}).get("q30_rate", None)
                    if q30 is not None:
                        metrics["q30_pct"] = round(q30 * 100, 2)
                break
            except Exception:
                continue

        # Trimmomatic log: "Input Read Pairs: X Surviving: Y (Z%)"
        if not metrics:
            for log_file in list(task_work_dir.glob("*.log")) + list(task_work_dir.glob("*.txt")):
                try:
                    text = log_file.read_text(errors="replace")
                    for line in text.splitlines():
                        line_lower = line.lower()
                        if "surviving" in line_lower and "%" in line:
                            import re as _re
                            m = _re.search(r"(\d+\.?\d*)\s*%", line)
                            if m:
                                metrics["reads_surviving_pct"] = float(m.group(1))
                                break
                    if metrics:
                        break
                except OSError:
                    continue

        if not metrics:
            return None
        return metrics

    def _parse_alignment_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse STAR Log.final.out, HISAT2/Bowtie2/BWA log.
        Key metric: overall alignment rate.
        """
        metrics: Dict[str, Any] = {}

        # STAR: Log.final.out
        for log_file in list(task_work_dir.glob("*Log.final.out")) + list(task_work_dir.glob("Log.final.out")):
            try:
                text = log_file.read_text(errors="replace")
                for line in text.splitlines():
                    if "Uniquely mapped reads %" in line:
                        try:
                            metrics["uniquely_mapped_pct"] = float(line.split("|")[1].strip().rstrip("%"))
                        except (ValueError, IndexError):
                            pass
                    elif "% of reads mapped to multiple loci" in line:
                        try:
                            multi = float(line.split("|")[1].strip().rstrip("%"))
                            uniq = metrics.get("uniquely_mapped_pct", 0)
                            metrics["alignment_rate"] = round(uniq + multi, 2)
                        except (ValueError, IndexError):
                            pass
                    elif "Number of input reads" in line:
                        try:
                            metrics["total_reads"] = int(line.split("|")[1].strip())
                        except (ValueError, IndexError):
                            pass
                # If STAR log provided uniquely_mapped_pct but no multi-loci line,
                # use uniquely_mapped_pct as the alignment_rate fallback so the
                # threshold check always has a comparable metric regardless of
                # whether the log was truncated.
                if "uniquely_mapped_pct" in metrics and "alignment_rate" not in metrics:
                    metrics["alignment_rate"] = metrics["uniquely_mapped_pct"]
                if metrics:
                    break
            except OSError:
                continue

        # HISAT2/Bowtie2/BWA: look for "X% overall alignment rate" in .log
        if "alignment_rate" not in metrics:
            import re as _re
            for log_file in list(task_work_dir.glob("*.log")) + list(task_work_dir.glob("*.txt")):
                try:
                    text = log_file.read_text(errors="replace")
                    m = _re.search(r"(\d+\.?\d+)%\s+overall alignment rate", text)
                    if m:
                        metrics["alignment_rate"] = float(m.group(1))
                        break
                    # BWA: "X reads aligned" pattern not standard — check samtools flagstat fallback
                except OSError:
                    continue

        if not metrics:
            return None
        return metrics

    def _parse_featurecounts_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse featureCounts *.summary file.
        Key metric: assigned reads fraction.
        """
        metrics: Dict[str, Any] = {}

        for summary_file in list(task_work_dir.glob("*.summary")) + list(task_work_dir.glob("*featureCounts*")):
            try:
                lines = summary_file.read_text(errors="replace").splitlines()
                assigned = unassigned = 0
                for line in lines:
                    parts = line.split("\t")
                    if len(parts) < 2:
                        continue
                    try:
                        val = int(parts[1])
                    except ValueError:
                        continue
                    if "Assigned" == parts[0]:
                        assigned = val
                    elif parts[0].startswith("Unassigned"):
                        unassigned += val
                total = assigned + unassigned
                if total > 0:
                    metrics["assigned_reads_pct"] = round(100.0 * assigned / total, 2)
                    metrics["assigned_reads"] = assigned
                    break
            except OSError:
                continue

        if not metrics:
            return None
        return metrics

    def _parse_salmon_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse Salmon aux_info/alevin_meta_info.json or cmd_info.json.
        Key metric: mapping rate.
        """
        metrics: Dict[str, Any] = {}
        import json as _json

        for meta_file in (
            list(task_work_dir.glob("aux_info/alevin_meta_info.json"))
            + list(task_work_dir.glob("aux_info/meta_info.json"))
            + list(task_work_dir.glob("*.json"))
        ):
            try:
                data = _json.loads(meta_file.read_text(errors="replace"))
                if "percent_mapped" in data:
                    metrics["mapping_rate"] = data["percent_mapped"]
                    break
                elif "mapping_rate" in data:
                    rate = data["mapping_rate"]
                    metrics["mapping_rate"] = float(str(rate).rstrip("%"))
                    break
            except Exception:
                continue

        if not metrics:
            return None
        return metrics

    # ------------------------------------------------------------------
    # DNA-seq parsers
    # ------------------------------------------------------------------

    def _parse_flagstat_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse samtools flagstat output.
        Key metrics: mapped%, duplicate%.
        """
        metrics: Dict[str, Any] = {}
        import re as _re

        for flag_file in (
            list(task_work_dir.glob("*.flagstat"))
            + list(task_work_dir.glob("*.txt"))
            + list(task_work_dir.glob("flagstat*"))
        ):
            try:
                text = flag_file.read_text(errors="replace")
                total_m = _re.search(r"(\d+) \+ \d+ in total", text)
                mapped_m = _re.search(r"(\d+) \+ \d+ mapped \((\d+\.?\d*)%", text)
                dup_m = _re.search(r"(\d+) \+ \d+ duplicates", text)
                if total_m and mapped_m:
                    metrics["mapped_pct"] = float(mapped_m.group(2))
                    metrics["total_reads"] = int(total_m.group(1))
                    if dup_m:
                        total = metrics["total_reads"]
                        dups = int(dup_m.group(1))
                        if total > 0:
                            metrics["duplicate_pct"] = round(100.0 * dups / total, 2)
                    break
            except OSError:
                continue

        if not metrics:
            return None
        return metrics

    def _parse_picard_dup_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse Picard MarkDuplicates metrics file.
        Key metric: PERCENT_DUPLICATION.
        """
        metrics: Dict[str, Any] = {}

        for metrics_file in (
            list(task_work_dir.glob("*.metrics"))
            + list(task_work_dir.glob("*.dup_metrics"))
            + list(task_work_dir.glob("*.txt"))
        ):
            try:
                lines = metrics_file.read_text(errors="replace").splitlines()
                header_idx = next((i for i, l in enumerate(lines)
                                   if "PERCENT_DUPLICATION" in l), None)
                if header_idx is not None and header_idx + 1 < len(lines):
                    headers = lines[header_idx].split("\t")
                    values = lines[header_idx + 1].split("\t")
                    data = dict(zip(headers, values))
                    if "PERCENT_DUPLICATION" in data:
                        dup_val = float(data["PERCENT_DUPLICATION"])
                        metrics["duplicate_pct"] = round(dup_val * 100, 2)
                    if "ESTIMATED_LIBRARY_SIZE" in data and data["ESTIMATED_LIBRARY_SIZE"]:
                        try:
                            metrics["estimated_library_size"] = int(float(data["ESTIMATED_LIBRARY_SIZE"]))
                        except ValueError:
                            pass
                    break
            except (OSError, StopIteration, ValueError):
                continue

        if not metrics:
            return None
        return metrics

    # ------------------------------------------------------------------
    # Coverage depth (mosdepth / samtools coverage / Picard WgsMetrics)
    # ------------------------------------------------------------------

    def _parse_coverage_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse coverage depth from mosdepth summary, samtools coverage, or Picard WgsMetrics.
        Key metric: mean_coverage (X depth over genome).
        source: GATK Best Practices — WGS ≥ 30X; WES ≥ 100X
        """
        metrics: Dict[str, Any] = {}
        import re as _re

        # mosdepth summary: <chrom>\t<length>\t<bases>\t<mean>\t<min>\t<max>
        # Last line is "total" which has genome-wide mean coverage
        for summary_file in (
            list(task_work_dir.glob("*.mosdepth.summary.txt"))
            + list(task_work_dir.glob("*summary.txt"))
        ):
            try:
                lines = summary_file.read_text(errors="replace").splitlines()
                for line in reversed(lines):
                    # Use startswith("total\t") to avoid false matches on contig names like "total_rRNA"
                    if line.startswith("total\t"):
                        parts = line.split("\t")
                        if len(parts) >= 4:
                            try:
                                # mosdepth summary: chrom, length, bases, mean, min, max
                                metrics["mean_coverage"] = float(parts[3])
                                break
                            except ValueError:
                                pass
                if metrics:
                    break
            except OSError:
                continue

        # Picard WgsMetrics: look for MEAN_COVERAGE column
        for metrics_file in (
            list(task_work_dir.glob("*.wgs_metrics"))
            + list(task_work_dir.glob("*wgs_metrics.txt"))
        ):
            try:
                lines = metrics_file.read_text(errors="replace").splitlines()
                header_idx = next((i for i, l in enumerate(lines)
                                   if "MEAN_COVERAGE" in l), None)
                if header_idx is not None and header_idx + 1 < len(lines):
                    headers = lines[header_idx].split("\t")
                    values = lines[header_idx + 1].split("\t")
                    data = dict(zip(headers, values))
                    if "MEAN_COVERAGE" in data:
                        try:
                            metrics["mean_coverage"] = float(data["MEAN_COVERAGE"])
                        except ValueError:
                            pass
                if metrics:
                    break
            except (OSError, StopIteration):
                continue

        if not metrics:
            return None
        return metrics

    # ------------------------------------------------------------------
    # Single-cell parser
    # ------------------------------------------------------------------

    def _parse_singlecell_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse CellRanger metrics_summary.csv or STARsolo Summary.csv.
        Key metrics: cells detected, median genes per cell, mapping rate.
        """
        metrics: Dict[str, Any] = {}
        import csv as _csv
        import io as _io

        for csv_file in (
            list(task_work_dir.glob("metrics_summary.csv"))
            + list(task_work_dir.glob("**/metrics_summary.csv"))
            + list(task_work_dir.glob("Summary.csv"))
        ):
            try:
                text = csv_file.read_text(errors="replace")
                reader = _csv.DictReader(_io.StringIO(text))
                for row in reader:
                    # CellRanger uses comma-separated keys with % and , in values
                    def _clean(v: str) -> str:
                        return v.replace(",", "").replace("%", "").strip()
                    if "Estimated Number of Cells" in row:
                        try:
                            metrics["cells_detected"] = int(_clean(row["Estimated Number of Cells"]))
                        except ValueError:
                            pass
                    if "Median Genes per Cell" in row:
                        try:
                            metrics["median_genes_per_cell"] = int(_clean(row["Median Genes per Cell"]))
                        except ValueError:
                            pass
                    if "Reads Mapped to Genome" in row:
                        try:
                            metrics["mapping_rate"] = float(_clean(row["Reads Mapped to Genome"]))
                        except ValueError:
                            pass
                    # CellRanger v7+: mitochondrial reads fraction
                    # source: Luecken & Theis (2019) Mol Syst Biol; > 20% indicates dead/damaged cells
                    for mito_col in ("Fraction Mitochondrial Reads",
                                     "Reads Mapped to Mitochondrial Genome",
                                     "Mitochondrial Fraction"):
                        if mito_col in row:
                            try:
                                val = float(_clean(row[mito_col]))
                                # CellRanger reports as fraction (0–1); convert to pct
                                metrics["mito_fraction_pct"] = val * 100.0 if val <= 1.0 else val
                            except ValueError:
                                pass
                            break
                    break  # first row only
                if metrics:
                    break
            except (OSError, Exception):
                continue

        if not metrics:
            return None
        return metrics

    def _parse_guide_library_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """Parse MAGeCK count or Perturb-seq guide library assignment statistics."""
        metrics: Dict[str, Any] = {}
        for fname in (
            "mageck_count_summary.json",
            "guide_library_summary.json",
            "perturbseq_qc.json",
            "guide_assignment.json",
            "crispr_screen_qc.json",
        ):
            for p in (
                list(task_work_dir.glob(fname))
                + list(task_work_dir.glob(f"**/{fname}"))
            ):
                try:
                    data = json.loads(p.read_text(errors="replace"))
                    for key in ("guide_library_coverage_pct", "guide_coverage_pct", "pct_cells_assigned"):
                        if key in data:
                            metrics["guide_library_coverage_pct"] = float(data[key])
                            break
                    for key in ("transfection_efficiency_pct", "transduction_efficiency_pct", "pct_transduced"):
                        if key in data:
                            metrics["transfection_efficiency_pct"] = float(data[key])
                            break
                    for key in ("doublet_fraction_pct", "predicted_doublet_rate", "doublet_rate"):
                        if key in data:
                            val = float(data[key])
                            metrics["doublet_fraction_pct"] = val * 100.0 if val <= 1.0 else val
                            break
                    if metrics:
                        log.debug(
                            f"[QC] Guide library: coverage={metrics.get('guide_library_coverage_pct')}%, "
                            f"transf_eff={metrics.get('transfection_efficiency_pct')}%, "
                            f"doublets={metrics.get('doublet_fraction_pct')}%"
                        )
                        return metrics
                except (OSError, json.JSONDecodeError):
                    continue
        return None

    # ------------------------------------------------------------------
    # ChIP-seq / ATAC-seq
    # ------------------------------------------------------------------

    def _parse_peakcalling_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse MACS2/3 peak call output.
        Key metric: number of peaks called.
        """
        metrics: Dict[str, Any] = {}

        for peak_file in (
            list(task_work_dir.glob("*_peaks.narrowPeak"))
            + list(task_work_dir.glob("*_peaks.broadPeak"))
            + list(task_work_dir.glob("*_summits.bed"))
        ):
            try:
                lines = [l for l in peak_file.read_text(errors="replace").splitlines()
                         if l.strip() and not l.startswith("#")]
                metrics["peaks_called"] = len(lines)
                break
            except OSError:
                continue

        # MACS2 log: "# d = X" (fragment length) and "# total tags after filtering: X"
        for log_file in list(task_work_dir.glob("*.log")) + list(task_work_dir.glob("*_macs2.log")):
            try:
                text = log_file.read_text(errors="replace")
                import re as _re
                m = _re.search(r"total tags after filtering:\s*(\d+)", text)
                if m:
                    metrics["tags_after_filtering"] = int(m.group(1))
            except OSError:
                continue

        # FRiP score: nf-core/chipseq and ENCODE pipelines write frip_score.txt
        # source: ENCODE4 ChIP-seq standards: ≥ 0.01 (TF), ≥ 0.1 (histone marks)
        for frip_file in (
            list(task_work_dir.glob("*frip_score*"))
            + list(task_work_dir.glob("*frip*"))
        ):
            try:
                val = float(frip_file.read_text(errors="replace").strip().split()[0])
                metrics["frip_score"] = round(val, 4)
                break
            except (OSError, ValueError, IndexError):
                continue

        if not metrics:
            return None
        return metrics

    def _parse_atac_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse ATAC-seq specific QC output files.
        Key metrics: TSS enrichment score, FRiP (ATAC), NRF.
        sources:
          - TSS enrichment: ENCODE4 ATAC-seq standards (≥ 7 high quality, ≥ 5 acceptable)
          - FRiP: ENCODE4 ATAC-seq (≥ 0.3)
          - NRF (PBC1): ENCODE4 (≥ 0.9)
        """
        metrics: Dict[str, Any] = {}

        # TSS enrichment score — typically a single float in tss_enrich.txt or *.tss.txt
        for tss_file in (
            list(task_work_dir.glob("tss_enrich.txt"))
            + list(task_work_dir.glob("*.tss.txt"))
            + list(task_work_dir.glob("*tss_enrichment*"))
        ):
            try:
                val = float(tss_file.read_text(errors="replace").strip().split()[0])
                metrics["tss_enrichment"] = round(val, 2)
                break
            except (OSError, ValueError, IndexError):
                continue

        # NRF (Non-Redundant Fraction) from nf-core pbc.txt or ENCODE ATAC-seq pipeline.
        # NRF ≠ PBC1: NRF = DistinctReadPairs / TotalReadPairs; PBC1 = OneReadPair / DistinctReadPairs.
        # Both share the ≥ 0.9 ENCODE4 threshold but measure different aspects of library complexity.
        # nf-core/atacseq pbc.txt format (0-indexed):
        #   col 0: TotalReadPairs  col 1: DistinctReadPairs  col 2: OneReadPair  col 3: TwoReadPairs
        #   col 4: NRF             col 5: PBC1               col 6: PBC2
        for pbc_file in (
            list(task_work_dir.glob("*.pbc.txt"))
            + list(task_work_dir.glob("*pbc*"))
        ):
            try:
                lines = [l for l in pbc_file.read_text(errors="replace").splitlines()
                         if l.strip() and not l.startswith("#")]
                if lines:
                    parts = lines[0].split("\t")
                    if len(parts) >= 5:
                        try:
                            # Column 4 (index 4) is NRF
                            metrics["nrf_score"] = float(parts[4])
                        except (ValueError, IndexError):
                            pass
                if "nrf_score" in metrics:
                    break
            except OSError:
                continue

        # FRiP score: same frip_score.txt convention as ChIP-seq
        for frip_file in (
            list(task_work_dir.glob("*frip_score*"))
            + list(task_work_dir.glob("*frip*"))
        ):
            try:
                val = float(frip_file.read_text(errors="replace").strip().split()[0])
                metrics["frip_score"] = round(val, 4)
                break
            except (OSError, ValueError, IndexError):
                continue

        if not metrics:
            return None
        return metrics

    # ------------------------------------------------------------------
    # Metagenomics
    # ------------------------------------------------------------------

    def _parse_metagenomics_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse Kraken2 report or MetaPhlAn output.
        Key metric: classified reads fraction.
        """
        metrics: Dict[str, Any] = {}
        import re as _re

        # Kraken2 report: first two lines are "unclassified" and "root"
        for report_file in (
            list(task_work_dir.glob("*.report"))
            + list(task_work_dir.glob("*kraken*"))
            + list(task_work_dir.glob("*.k2report"))
        ):
            try:
                lines = [l for l in report_file.read_text(errors="replace").splitlines()
                         if l.strip()]
                if not lines:
                    continue
                # Kraken2: first line may be unclassified (U), second is root (R)
                classified_pct = None
                unclassified_pct = None
                for line in lines[:5]:
                    parts = line.split("\t")
                    if len(parts) >= 4 and parts[3].strip() == "U":
                        try:
                            unclassified_pct = float(parts[0].strip())
                            classified_pct = round(100.0 - unclassified_pct, 2)
                        except ValueError:
                            pass
                if classified_pct is not None:
                    metrics["classified_pct"] = classified_pct
                    break
            except OSError:
                continue

        if not metrics:
            return None
        return metrics

    def _parse_2d_classification_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse CryoSPARC 2D classification output (class2d_report.json).

        Derives ``junk_class_fraction`` from ``num_good_classes`` / ``num_classes``:
          > 0.70 → GOLD blocking (too many poor classes to trust selected particles)
          0.50–0.70 → BRONZE advisory

        Reference: community heuristic; < 50% good classes usually indicates poor particle
        quality or ice contamination.
        """
        for fname in ("class2d_report.json", "class2d_r1_report.json",
                      "class2d_r2_report.json", "class2d_metrics.json"):
            for p in (list(task_work_dir.glob(fname))
                      + list(task_work_dir.glob(f"**/{fname}"))):
                try:
                    data = json.loads(p.read_text(errors="replace"))
                    metrics: Dict[str, Any] = {}

                    # Prefer explicit junk_class_fraction if written
                    junk = data.get("junk_class_fraction")
                    if junk is not None:
                        try:
                            metrics["junk_class_fraction"] = float(junk)
                        except (ValueError, TypeError):
                            pass

                    # Derive from class counts (SPA pipeline format)
                    if "junk_class_fraction" not in metrics:
                        num_total = data.get("num_classes")
                        num_good = data.get("num_good_classes")
                        if (num_total is not None and num_good is not None
                                and isinstance(num_total, (int, float)) and num_total > 0):
                            metrics["junk_class_fraction"] = round(
                                1.0 - float(num_good) / float(num_total), 4
                            )

                    # Additional informational metrics
                    for key in ("num_particles", "num_classes", "num_good_classes",
                                "avg_resolution_angstroms"):
                        if data.get(key) is not None:
                            metrics[key] = data[key]

                    if "junk_class_fraction" in metrics:
                        log.debug(
                            f"[QC] 2D classify: junk_fraction={metrics['junk_class_fraction']:.2f}"
                        )
                        return metrics
                except (OSError, json.JSONDecodeError):
                    continue
        return None

    def _parse_refinement_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse CryoSPARC refinement / FSC validation output.

        CryoSPARC writes a JSON results file with FSC data; also supports
        a simple text file with "FSC_resolution: X.X" for testing purposes.
        Returns None when no readable output is present.
        """
        import json as _json
        metrics: Dict[str, Any] = {}

        # Try CryoSPARC JSON output first (job.json or *_results.json)
        for json_file in (list(task_work_dir.glob("*_results.json"))
                          + list(task_work_dir.glob("job.json"))
                          + list(task_work_dir.glob("*.json"))):
            try:
                data = _json.loads(json_file.read_text(errors="replace"))
                # CryoSPARC stores FSC resolution in results dict
                fsc = data.get("fsc_resolution_angstrom")
                if fsc is None:
                    fsc = data.get("FSC_resolution_A")
                if fsc is None:
                    fsc = data.get("resolution_A")
                if fsc is not None:
                    try:
                        metrics["fsc_resolution_angstrom"] = float(fsc)
                    except (ValueError, TypeError):
                        pass
                # Junk class fraction (from 2D classification step)
                junk = data.get("junk_class_fraction")
                if junk is None:
                    junk = data.get("rejected_fraction")
                if junk is not None:
                    try:
                        metrics["junk_class_fraction"] = float(junk)
                    except (ValueError, TypeError):
                        pass
                if metrics:
                    break
            except (OSError, _json.JSONDecodeError):
                continue

        # Fallback: simple text file (used in tests + pipeline summary outputs)
        if not metrics:
            for txt_file in (list(task_work_dir.glob("*fsc*.txt"))
                             + list(task_work_dir.glob("*refinement*.txt"))
                             + list(task_work_dir.glob("*.txt"))):
                try:
                    for line in txt_file.read_text(errors="replace").splitlines():
                        line_lower = line.lower()
                        if "fsc_resolution" in line_lower or "fsc resolution" in line_lower:
                            parts = line.split(":")
                            if len(parts) >= 2:
                                try:
                                    metrics["fsc_resolution_angstrom"] = float(parts[-1].strip())
                                except ValueError:
                                    pass
                        elif "junk_class_fraction" in line_lower or "junk fraction" in line_lower:
                            parts = line.split(":")
                            if len(parts) >= 2:
                                try:
                                    metrics["junk_class_fraction"] = float(parts[-1].strip())
                                except ValueError:
                                    pass
                    if metrics:
                        break
                except OSError:
                    continue

        if not metrics:
            log.debug(f"[QC] No refinement metrics found in {task_work_dir}")
            return None
        return metrics

    def _parse_sharpening_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse CryoSPARC post-processing / sharpening output.

        Reads ``sharpening_results.json`` written by the ctf_refine_sharpen workflow step.

        Key QC field:
          bfactor_angstrom_squared — applied B-factor in Å².
            Negative = sharpening (typical: −50 to −200 Å² for near-atomic maps).
            Positive = blurring (unusual; may indicate over-refinement).
            Very large negative (< −300 Å²) = over-sharpening artefacts.

        Guinier/DeepEMhancer references: Rosenthal & Henderson 2003 JMB 333:721;
        Terwilliger et al. 2018 Acta Cryst D74:545.
        """
        # Field aliases: actual SPA pipeline uses b_factor_applied; legacy names also checked
        _BFACTOR_KEYS = ("bfactor_angstrom_squared", "b_factor_applied", "b_factor",
                         "bfactor", "b_factor_angstrom2")
        for fname in ("sharpening_report.json", "sharpening_results.json",
                      "postprocessing_results.json", "postprocess_report.json"):
            for p in (list(task_work_dir.glob(fname))
                      + list(task_work_dir.glob(f"**/{fname}"))):
                try:
                    data = json.loads(p.read_text(errors="replace"))
                    metrics: Dict[str, Any] = {}
                    for key in _BFACTOR_KEYS:
                        val = data.get(key)
                        if val is not None:
                            try:
                                metrics["bfactor_angstrom_squared"] = float(val)
                                break
                            except (ValueError, TypeError):
                                pass
                    if metrics:
                        log.debug(f"[QC] Sharpening: B-factor={metrics.get('bfactor_angstrom_squared')} Å²")
                        return metrics
                except (OSError, json.JSONDecodeError):
                    continue
        return None

    def _parse_model_quality_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """Parse MolProbity validation report and EMRinger score after atomic model fitting."""
        metrics: Dict[str, Any] = {}
        import re as _re

        # MolProbity JSON output
        for fname in (
            "molprobity_results.json",
            "molprobity_report.json",
            "validation_report.json",
            "model_validation.json",
        ):
            for p in (
                list(task_work_dir.glob(fname))
                + list(task_work_dir.glob(f"**/{fname}"))
            ):
                try:
                    data = json.loads(p.read_text(errors="replace"))
                    for key in ("ramachandran_outliers_pct", "rama_outliers_pct", "ramachandran_outliers"):
                        if key in data:
                            metrics["ramachandran_outliers_pct"] = float(data[key])
                            break
                    for key in ("rotamer_outliers_pct", "rota_outliers_pct", "rotamer_outliers"):
                        if key in data:
                            metrics["rotamer_outliers_pct"] = float(data[key])
                            break
                    for key in ("clashscore", "clash_score"):
                        if key in data:
                            metrics["clashscore"] = float(data[key])
                            break
                    if metrics:
                        log.debug(
                            f"[QC] MolProbity: Rama={metrics.get('ramachandran_outliers_pct')}%, "
                            f"Rotamer={metrics.get('rotamer_outliers_pct')}%, "
                            f"Clashscore={metrics.get('clashscore')}"
                        )
                        break
                except (OSError, json.JSONDecodeError):
                    continue

        # EMRinger — plain text "Overall EMRinger Score: X.XX" or JSON
        for fname in (
            "emringer_score.txt",
            "emringer_results.json",
            "emringer_output.json",
            "emringer_report.txt",
        ):
            for p in (
                list(task_work_dir.glob(fname))
                + list(task_work_dir.glob(f"**/{fname}"))
            ):
                try:
                    text = p.read_text(errors="replace")
                    if fname.endswith(".txt"):
                        m = _re.search(r"(?i)overall emringer score[:\s]+([0-9.-]+)", text)
                        if m:
                            metrics["emringer_score"] = float(m.group(1))
                            break
                    else:
                        data = json.loads(text)
                        for key in ("emringer_score", "overall_score", "score"):
                            if key in data:
                                metrics["emringer_score"] = float(data[key])
                                break
                    if "emringer_score" in metrics:
                        log.debug(f"[QC] EMRinger score: {metrics['emringer_score']:.2f}")
                        break
                except (OSError, json.JSONDecodeError, ValueError):
                    continue

        return metrics if metrics else None

    def _parse_local_resolution_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse local resolution estimation output.

        Reads ``local_resolution_results.json`` written by the local_resolution workflow step
        (CryoSPARC local resolution job or MonoRes/ResMap).

        Key QC field:
          std_spread_angstrom — standard deviation of the local resolution distribution (Å).
            Low spread (< 1 Å) = uniform, well-ordered structure.
            Moderate (1–3 Å) = typical; some flexibility acceptable.
            High (> 3 Å) = high conformational disorder or dominant flexible regions;
                            advisory to check domain orientation and flexible loops.

        Reference: Vilas et al. 2018 Structure 26:337 (MonoRes).
        """
        # std aliases: actual SPA pipeline writes std_resolution_angstroms
        _STD_KEYS = ("std_spread_angstrom", "std_resolution_angstroms",
                     "resolution_std", "std_local_resolution")
        # mean aliases: SPA writes mean_resolution_angstroms (with trailing 's')
        _MEAN_KEYS = ("mean_resolution_angstroms", "mean_resolution_angstrom",
                      "mean_local_resolution_angstrom")
        for fname in ("local_resolution_report.json", "local_resolution_results.json",
                      "localres_results.json", "localres_report.json"):
            for p in (list(task_work_dir.glob(fname))
                      + list(task_work_dir.glob(f"**/{fname}"))):
                try:
                    data = json.loads(p.read_text(errors="replace"))
                    metrics: Dict[str, Any] = {}
                    for key in _STD_KEYS:
                        val = data.get(key)
                        if val is not None:
                            try:
                                metrics["std_spread_angstrom"] = float(val)
                                break
                            except (ValueError, TypeError):
                                pass
                    for key in _MEAN_KEYS:
                        val = data.get(key)
                        if val is not None:
                            try:
                                metrics["mean_local_resolution_angstrom"] = float(val)
                                break
                            except (ValueError, TypeError):
                                pass
                    if metrics:
                        log.debug(f"[QC] Local resolution: std={metrics.get('std_spread_angstrom')} Å")
                        return metrics
                except (OSError, json.JSONDecodeError):
                    continue
        return None

    def _parse_maxquant_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse MaxQuant output files.

        Primary sources:
          summary.txt    — PSM count, missed cleavage rate (per-experiment row)
          proteinGroups.txt — protein FDR proxy (decoy/reverse fraction), CV
          Phospho (STY)Sites.txt — phosphosite localization scores (phospho experiments only)

        Returns None when no MaxQuant output files are found.
        """
        import csv as _csv
        import statistics as _stats

        metrics: Dict[str, Any] = {}

        # --- summary.txt: overall PSM count and missed cleavages ---
        for summary_file in (list(task_work_dir.glob("**/summary.txt"))
                             + list(task_work_dir.glob("summary.txt"))):
            try:
                with open(summary_file, newline="", errors="replace") as f:
                    reader = _csv.DictReader(f, delimiter="\t")
                    for row in reader:
                        # MaxQuant summary: "MS/MS Identified" column
                        psm_val = row.get("MS/MS Identified")
                        if psm_val is None:
                            psm_val = row.get("MS/MS identified")
                        if psm_val is not None:
                            try:
                                metrics["psm_count"] = int(str(psm_val).replace(",", ""))
                            except ValueError:
                                pass
                        mc = row.get("Missed Cleavages")
                        if mc is None:
                            mc = row.get("Missed cleavages")
                        if mc is not None:
                            try:
                                metrics.setdefault("missed_cleavage_pct", float(mc))
                            except ValueError:
                                pass
                        break  # first data row only
                if "psm_count" in metrics:
                    break
            except OSError:
                continue

        # --- proteinGroups.txt: protein FDR (decoy ratio) and LFQ CV ---
        for pg_file in (list(task_work_dir.glob("**/proteinGroups.txt"))
                        + list(task_work_dir.glob("proteinGroups.txt"))):
            try:
                with open(pg_file, newline="", errors="replace") as f:
                    reader = _csv.DictReader(f, delimiter="\t")
                    total = 0
                    decoy = 0
                    cvs = []
                    for row in reader:
                        total += 1
                        # MaxQuant marks reverse/contaminant hits with "+"
                        if (row.get("Reverse", "").strip() == "+"
                                or row.get("Potential contaminant", "").strip() == "+"):
                            decoy += 1
                        # Collect LFQ CV columns (column names vary by MQ version)
                        for key in row:
                            if "cv" in key.lower() and "intensity" in key.lower():
                                try:
                                    val = float(row[key])
                                    if 0 < val < 300:
                                        cvs.append(val)
                                except (ValueError, TypeError):
                                    pass
                    if total > 0:
                        metrics.setdefault("protein_fdr_pct", round((decoy / total) * 100.0, 3))
                    if cvs:
                        metrics.setdefault("cv_pct", round(_stats.median(cvs), 1))
                break
            except OSError:
                continue

        # --- Phospho (STY)Sites.txt: median localization probability ---
        for phospho_file in (list(task_work_dir.glob("**/Phospho (STY)Sites.txt"))
                             + list(task_work_dir.glob("Phospho (STY)Sites.txt"))
                             + list(task_work_dir.glob("**/PhosphoSites.txt"))):
            try:
                with open(phospho_file, newline="", errors="replace") as f:
                    reader = _csv.DictReader(f, delimiter="\t")
                    scores = []
                    for row in reader:
                        score_val = row.get("Localization prob")
                        if score_val is None:
                            score_val = row.get("Localization Prob")
                        if score_val is not None:
                            try:
                                scores.append(float(score_val))
                            except ValueError:
                                pass
                if scores:
                    metrics["phosphosite_localization_score"] = round(_stats.median(scores), 3)
                break
            except OSError:
                continue

        if not metrics:
            log.debug(f"[QC] No MaxQuant metrics found in {task_work_dir}")
            return None
        return metrics

    def _parse_diann_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse DIA-NN output files.

        Primary sources:
          report.stats.tsv  — high-level run statistics (PSM count, FDR)
          report.tsv        — precursor-level data (used to compute CV and missing values)

        Returns None when no DIA-NN output files are found.
        """
        import csv as _csv
        import statistics as _stats

        metrics: Dict[str, Any] = {}

        # --- report.stats.tsv: summary statistics ---
        for stats_file in (list(task_work_dir.glob("**/report.stats.tsv"))
                           + list(task_work_dir.glob("report.stats.tsv"))):
            try:
                with open(stats_file, newline="", errors="replace") as f:
                    reader = _csv.DictReader(f, delimiter="\t")
                    for row in reader:
                        for key in row:
                            key_l = key.lower()
                            if "precursor" in key_l and "count" in key_l:
                                try:
                                    metrics.setdefault("psm_count", int(row[key]))
                                except (ValueError, TypeError):
                                    pass
                            elif "protein" in key_l and "fdr" in key_l:
                                try:
                                    fdr = float(row[key])
                                    # DIA-NN reports FDR as 0–1; convert to percent
                                    fdr_pct = fdr * 100.0 if fdr <= 1.0 else fdr
                                    metrics.setdefault("protein_fdr_pct", round(fdr_pct, 3))
                                except (ValueError, TypeError):
                                    pass
                break
            except OSError:
                continue

        # --- report.tsv: CV and missing value calculation ---
        for report_file in (list(task_work_dir.glob("**/report.tsv"))
                            + list(task_work_dir.glob("report.tsv"))):
            try:
                protein_intensities: Dict[str, list] = {}
                with open(report_file, newline="", errors="replace") as f:
                    reader = _csv.DictReader(f, delimiter="\t")
                    for row in reader:
                        prot = (row.get("Protein.Group")
                                or row.get("ProteinName")
                                or row.get("Protein.Name"))
                        intensity = (row.get("Precursor.Normalised")
                                     or row.get("Intensity"))
                        if prot and intensity:
                            try:
                                val = float(intensity)
                                if val > 0:
                                    protein_intensities.setdefault(prot, []).append(val)
                            except ValueError:
                                pass

                # Median CV across proteins with ≥ 2 replicate observations
                cvs = []
                for vals in protein_intensities.values():
                    if len(vals) >= 2:
                        mean_v = _stats.mean(vals)
                        if mean_v > 0:
                            cv = (_stats.stdev(vals) / mean_v) * 100.0
                            if 0 < cv < 300:
                                cvs.append(cv)
                if cvs:
                    metrics.setdefault("cv_pct", round(_stats.median(cvs), 1))

                # Missing value fraction: proteins with fewer observations than the modal count
                if protein_intensities:
                    max_obs = max(len(v) for v in protein_intensities.values())
                    if max_obs > 1:
                        n_missing = sum(1 for v in protein_intensities.values()
                                        if len(v) < max_obs)
                        total_prot = len(protein_intensities)
                        metrics["missing_value_pct"] = round(
                            (n_missing / total_prot) * 100.0, 1
                        )
                break
            except OSError:
                continue

        if not metrics:
            log.debug(f"[QC] No DIA-NN metrics found in {task_work_dir}")
            return None
        return metrics

    def _parse_pulldown_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse chemoproteomics pulldown enrichment output.

        Expected input: a TSV file (enrichment_ratios.tsv or similar) with columns:
            protein_id, prey_intensity, input_intensity, enrichment_ratio

        Falls back to a JSON summary file. Returns None if no readable data found.

        The median enrichment ratio across all identified proteins is the primary
        quality metric: values < 3× indicate a failed pulldown (matrix binder list).
        """
        import csv as _csv
        import statistics as _stats

        metrics: Dict[str, Any] = {}

        # TSV with per-protein enrichment ratios (pipeline-generated)
        for tsv_file in (list(task_work_dir.glob("**/enrichment_ratios.tsv"))
                         + list(task_work_dir.glob("enrichment_ratios.tsv"))
                         + list(task_work_dir.glob("*enrichment*.tsv"))
                         + list(task_work_dir.glob("*pulldown*.tsv"))):
            try:
                ratios = []
                prey_above_threshold = 0
                with open(tsv_file, newline="", errors="replace") as f:
                    reader = _csv.DictReader(f, delimiter="\t")
                    for row in reader:
                        ratio_val = (row.get("enrichment_ratio")
                                     or row.get("Enrichment_Ratio")
                                     or row.get("ratio"))
                        if ratio_val:
                            try:
                                r = float(ratio_val)
                                if r > 0:
                                    ratios.append(r)
                                    if r >= 3.0:
                                        prey_above_threshold += 1
                            except ValueError:
                                pass
                if ratios:
                    metrics["median_enrichment_ratio"] = round(_stats.median(ratios), 3)
                    metrics["prey_protein_count"] = prey_above_threshold
                    metrics["total_proteins_quantified"] = len(ratios)
                    break
            except OSError:
                continue

        # JSON summary fallback (pipeline summary output)
        if not metrics:
            import json as _json
            for json_file in (list(task_work_dir.glob("*pulldown*summary*.json"))
                              + list(task_work_dir.glob("enrichment_summary.json"))
                              + list(task_work_dir.glob("*.json"))):
                try:
                    data = _json.loads(json_file.read_text(errors="replace"))
                    enr = data.get("median_enrichment_ratio")
                    if enr is None:
                        enr = data.get("enrichment_ratio")
                    if enr is not None:
                        metrics["median_enrichment_ratio"] = float(enr)
                    prey = data.get("prey_protein_count")
                    if prey is not None:
                        metrics["prey_protein_count"] = int(prey)
                    crap = data.get("crapome_contamination_fraction")
                    if crap is not None:
                        metrics["crapome_contamination_fraction"] = float(crap)
                    if metrics:
                        break
                except (OSError, _json.JSONDecodeError, ValueError, TypeError):
                    continue

        if not metrics:
            log.debug(f"[QC] No pulldown enrichment metrics found in {task_work_dir}")
            return None
        return metrics

    def _parse_smiles_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse compound SMILES input and run structural quality checks with RDKit.

        Reads a text file of SMILES (one per line, with optional compound ID):
            COMPOUND_ID  SMILES_STRING
        or just:
            SMILES_STRING

        Checks performed:
          [GOLD]   SMILES parseable by RDKit (invalid → hard gate)
          [SILVER] Salt form (disconnected fragments via '.')
          [SILVER] Undefined stereocenters (@ notation absent where expected)
          [BRONZE] Molecular weight > 900 Da

        Falls back to gracefully handling RDKit import failures (CI/CD environments).
        """
        metrics: Dict[str, Any] = {}

        # Find SMILES input file — search recursively then top-level
        smiles_files = (list(task_work_dir.glob("**/*.smi"))
                        + list(task_work_dir.glob("*.smi"))
                        + list(task_work_dir.glob("**/*.smiles"))
                        + list(task_work_dir.glob("*.smiles"))
                        + list(task_work_dir.glob("*compounds*.txt"))
                        + list(task_work_dir.glob("compounds.txt")))

        # Characters that appear in SMILES but not in compound IDs — used to identify
        # the SMILES token on lines that also contain ID fields.
        _SMILES_CHARS = frozenset("()=[]#@/\\")

        smiles_list = []
        for smi_file in smiles_files:
            try:
                for line in smi_file.read_text(errors="replace").splitlines():
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    parts = line.split()
                    # Identify the SMILES token using unambiguous SMILES-specific characters.
                    # Standard .smi format has SMILES first; reversed (ID SMILES) puts it second.
                    smiles_str = None
                    for part in parts:
                        if any(c in part for c in _SMILES_CHARS):
                            smiles_str = part
                            break
                    if smiles_str is None and parts:
                        # Fallback: take first token (standard .smi format: SMILES first)
                        smiles_str = parts[0]
                    if smiles_str:
                        smiles_list.append(smiles_str)
                if smiles_list:
                    break
            except OSError:
                continue

        if not smiles_list:
            log.debug(f"[QC] No SMILES files found in {task_work_dir}")
            return None

        # Try RDKit validation
        try:
            from rdkit import Chem
            from rdkit.Chem import Descriptors, rdMolDescriptors
        except ImportError:
            log.warning("[QC] RDKit not available — SMILES QC gate skipped")
            return None

        total = len(smiles_list)
        invalid_count = 0
        salt_count = 0
        undefined_stereo_count = 0
        high_mw_count = 0
        mw_limit = 900.0

        for smi in smiles_list:
            mol = Chem.MolFromSmiles(smi, sanitize=False)
            if mol is None:
                invalid_count += 1
                continue

            try:
                Chem.SanitizeMol(mol)
            except Exception:
                invalid_count += 1
                continue

            # Salt form: disconnected fragments
            if "." in smi:
                salt_count += 1
                # Strip salts for subsequent checks
                frags = Chem.GetMolFrags(mol, asMols=True)
                mol = max(frags, key=lambda m: m.GetNumHeavyAtoms()) if frags else mol

            # Undefined stereocenters
            si = Chem.FindMolChiralCenters(mol, includeUnassigned=True)
            if any(s[1] == "?" for s in si):
                undefined_stereo_count += 1

            # Molecular weight
            try:
                mw = Descriptors.MolWt(mol)
                if mw > mw_limit:
                    high_mw_count += 1
            except Exception:
                pass

        metrics["total_compounds"] = total
        metrics["invalid_smiles_count"] = invalid_count
        metrics["salt_form_count"] = salt_count
        metrics["undefined_stereo_count"] = undefined_stereo_count
        metrics["high_mw_count"] = high_mw_count
        metrics["valid_fraction"] = round((total - invalid_count) / max(total, 1), 4)

        log.debug(
            f"[QC] SMILES QC: {total} compounds, {invalid_count} invalid, "
            f"{salt_count} salt form, {undefined_stereo_count} undefined stereo"
        )
        return metrics

    def _parse_admet_toxicity_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse ADMET toxicity prediction output for safety screening gates.

        Reads (in priority order):
          1. ``toxicity_report.json``   — structured output from a dedicated toxicity step
          2. ``predict_admet_properties_results.json`` — DeepPurpose MPNN output
          3. ``predict_admet_properties_output.txt``  — text research log (fallback)
          4. ``ADMET_pred_results.json`` — simple ADMET_pred output

        Metrics extracted:
          herg_ic50_uM            — hERG IC50 (μM); < 1 μM = high cardiotox risk
          herg_inhibition_prob    — probability of hERG channel inhibition (0–1)
          dili_risk               — "high" | "medium" | "low" (DILIrank category)
          dili_probability        — DILI probability score (0–1)
          ames_positive           — bool; True = mutagenicity predicted
          ames_probability        — Ames test probability (0–1)
          clintox_probability     — ClinTox clinical toxicity probability (0–1)
        """
        metrics: Dict[str, Any] = {}

        # ── 1. Structured toxicity_report.json ──────────────────────────────
        for candidate in (list(task_work_dir.glob("toxicity_report.json"))
                          + list(task_work_dir.glob("**/toxicity_report.json"))):
            try:
                import json as _json
                data = _json.loads(candidate.read_text())
                tox = data.get("toxicity", data)  # allow flat or nested

                if "herg_ic50_uM" in tox:
                    metrics["herg_ic50_uM"] = float(tox["herg_ic50_uM"])
                if "herg_inhibition_prob" in tox:
                    metrics["herg_inhibition_prob"] = float(tox["herg_inhibition_prob"])
                if "dili_risk" in tox:
                    metrics["dili_risk"] = str(tox["dili_risk"]).lower()
                if "dili_probability" in tox:
                    metrics["dili_probability"] = float(tox["dili_probability"])
                if "ames_positive" in tox:
                    metrics["ames_positive"] = bool(tox["ames_positive"])
                if "ames_probability" in tox:
                    metrics["ames_probability"] = float(tox["ames_probability"])
                if "clintox_probability" in tox:
                    metrics["clintox_probability"] = float(tox["clintox_probability"])
                if metrics:
                    return metrics
            except (OSError, ValueError, KeyError):
                continue

        # ── 2. predict_admet_properties_results.json ────────────────────────
        for candidate in (list(task_work_dir.glob("predict_admet_properties_results.json"))
                          + list(task_work_dir.glob("**/predict_admet_properties_results.json"))):
            try:
                import json as _json
                data = _json.loads(candidate.read_text())
                result = data.get("result", "")
                if isinstance(result, dict):
                    tox = result.get("toxicity", result)
                    if "herg_ic50_uM" in tox:
                        metrics["herg_ic50_uM"] = float(tox["herg_ic50_uM"])
                    if "clintox_probability" in tox:
                        metrics["clintox_probability"] = float(tox["clintox_probability"])
                    if "dili_risk" in tox:
                        metrics["dili_risk"] = str(tox["dili_risk"]).lower()
                    if metrics:
                        return metrics
            except (OSError, ValueError, KeyError):
                continue

        # ── 3. Text log: predict_admet_properties_output.txt ────────────────
        # Format: "- Clinical Toxicity: 0.85 %"
        for txt_file in (list(task_work_dir.glob("predict_admet_properties_output.txt"))
                         + list(task_work_dir.glob("**/predict_admet_properties_output.txt"))):
            try:
                import re as _re
                text = txt_file.read_text(errors="replace")
                clintox_m = _re.search(
                    r"clinical.?toxicity[:\s]+([0-9]+\.?[0-9]*)\s*%?", text, _re.IGNORECASE
                )
                if clintox_m:
                    val = float(clintox_m.group(1))
                    # Value may be 0–100 (%) or 0–1 (probability)
                    metrics["clintox_probability"] = val / 100.0 if val > 1.0 else val
                herg_m = _re.search(
                    r"herg.{0,20}ic50[:\s]+([0-9]+\.?[0-9]*)\s*(uM|μM|µM)?", text, _re.IGNORECASE
                )
                if herg_m:
                    metrics["herg_ic50_uM"] = float(herg_m.group(1))
                if metrics:
                    return metrics
            except OSError:
                continue

        # ── 4. ADMET_pred_results.json fallback ─────────────────────────────
        for candidate in (list(task_work_dir.glob("ADMET_pred_results.json"))
                          + list(task_work_dir.glob("**/ADMET_pred_results.json"))):
            try:
                import json as _json
                data = _json.loads(candidate.read_text())
                result = data.get("result", {})
                if isinstance(result, dict):
                    pred = result.get("predictions", {})
                    if "herg_ic50_uM" in pred:
                        metrics["herg_ic50_uM"] = float(pred["herg_ic50_uM"])
                    if "clintox_probability" in pred:
                        metrics["clintox_probability"] = float(pred["clintox_probability"])
                    if "dili_risk" in pred:
                        metrics["dili_risk"] = str(pred["dili_risk"]).lower()
                    if metrics:
                        return metrics
            except (OSError, ValueError, KeyError):
                continue

        log.debug(f"[QC] No ADMET toxicity metrics found in {task_work_dir}")
        return None

    def _parse_pgx_coverage_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse per-gene WGS coverage for pharmacogenomics (PGx) QC.

        Reads mosdepth per-gene summary output.  Expects either:
          - ``pgx_coverage.tsv``      — custom PGx report: gene \\t mean_coverage
          - ``mosdepth.gene_summary`` — mosdepth gene-level summary
          - ``*.regions.bed.gz``      — mosdepth regions output (requires pysam)

        Extracts coverage for the CPIC Tier 1 + 2 genes:
            CYP2D6, CYP2C19, CYP3A4, CYP3A5, CYP2C9, CYP1A2,
            DPYD, TPMT, NUDT15, SLCO1B1, UGT1A1, VKORC1

        Returns dict of {gene_name: coverage_depth, "min_pgx_coverage": float,
                         "pgx_genes_below_threshold": list[str]}
        """
        metrics: Dict[str, Any] = {}
        _PGX_GENES = {
            "CYP2D6", "CYP2C19", "CYP3A4", "CYP3A5", "CYP2C9", "CYP1A2",
            "DPYD", "TPMT", "NUDT15", "SLCO1B1", "UGT1A1", "VKORC1",
        }

        gene_coverage: Dict[str, float] = {}

        # ── pgx_coverage.tsv ────────────────────────────────────────────────
        for tsv in (list(task_work_dir.glob("pgx_coverage.tsv"))
                    + list(task_work_dir.glob("**/pgx_coverage.tsv"))):
            try:
                for line in tsv.read_text(errors="replace").splitlines():
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    parts = line.split("\t")
                    if len(parts) >= 2:
                        gene = parts[0].strip().upper()
                        if gene in _PGX_GENES:
                            try:
                                gene_coverage[gene] = float(parts[1])
                            except ValueError:
                                pass
                if gene_coverage:
                    break
            except OSError:
                continue

        # ── mosdepth gene_summary ────────────────────────────────────────────
        if not gene_coverage:
            for summary_file in (list(task_work_dir.glob("*.gene_summary"))
                                  + list(task_work_dir.glob("**/mosdepth.gene_summary"))):
                try:
                    import re as _re
                    for line in summary_file.read_text(errors="replace").splitlines():
                        parts = line.split("\t")
                        if len(parts) >= 4:
                            gene = parts[0].strip().upper()
                            if gene in _PGX_GENES:
                                try:
                                    gene_coverage[gene] = float(parts[3])  # mean coverage col
                                except ValueError:
                                    pass
                    if gene_coverage:
                        break
                except OSError:
                    continue

        if not gene_coverage:
            log.debug(f"[QC] No PGx coverage files found in {task_work_dir}")
            return None

        threshold = self._get_threshold("pgx_min_coverage", 30)
        below = [g for g, cov in gene_coverage.items() if cov < threshold]

        metrics.update(gene_coverage)
        metrics["min_pgx_coverage"] = min(gene_coverage.values()) if gene_coverage else 0.0
        metrics["pgx_genes_below_threshold"] = below
        metrics["pgx_genes_assessed"] = len(gene_coverage)
        log.debug(
            f"[QC] PGx coverage: {len(gene_coverage)} genes assessed, "
            f"{len(below)} below {threshold}×"
        )
        return metrics

    def _parse_nca_results(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse PKNCA non-compartmental analysis output.

        Reads ``nca_results.json`` produced by the nca_pknca Nextflow workflow.
        Key QC fields:
          - auc_extrap_pct_max  : max % AUC extrapolated across subjects (> 20% = unreliable t½)
          - subjects_with_no_terminal_slope : count of subjects where lambda_z failed
          - n_subjects          : total subjects analysed
        """
        for fname in ("nca_results.json",):
            for p in (list(task_work_dir.glob(fname))
                      + list(task_work_dir.glob(f"**/{fname}"))):
                try:
                    data = json.loads(p.read_text(errors="replace"))
                    metrics: Dict[str, Any] = {}
                    for key in ("n_subjects", "route", "cmax_mean", "auclast_mean",
                                "thalf_mean_h", "cl_f_mean", "auc_extrap_pct_max",
                                "subjects_with_no_terminal_slope", "pknca_version"):
                        if data.get(key) is not None:
                            metrics[key] = data[key]
                    if metrics:
                        log.debug(
                            f"[QC] NCA: {metrics.get('n_subjects')} subjects, "
                            f"AUC extrap {metrics.get('auc_extrap_pct_max')}%, "
                            f"no-slope subjects {metrics.get('subjects_with_no_terminal_slope')}"
                        )
                        return metrics
                except (OSError, json.JSONDecodeError, KeyError):
                    continue
        return None

    def _parse_pbpk_results(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse PBPK simulation outputs for QC gate evaluation.

        Reads ``nca_parameters.json`` and ``pk_profile.csv`` produced by
        pk_sim_pbpk / pbpk_simulation / simcyp_pbpk workflows.

        Key QC fields extracted:
          - Tmax_h               : time to Cmax (h); should be < simulation_end * 0.8
          - t_half_h             : terminal half-life (h); null = no elimination
          - CL_L_h               : systemic clearance (L/h); unrealistically low = no metabolism
          - F_oral               : oral bioavailability (fraction 0–1)
          - pbpk_monotonic       : True if blood conc never declines (missing elimination)
          - pbpk_tmax_fraction   : Tmax_h / simulation_end_h (> 0.8 = peak at end of sim)
          - pbpk_simulation_end_h: last time point in pk_profile.csv
        """
        metrics: Dict[str, Any] = {}

        # 1. nca_parameters.json — structured NCA output
        for fname in ("nca_parameters.json",):
            for p in (list(task_work_dir.glob(fname))
                      + list(task_work_dir.glob(f"**/{fname}"))):
                try:
                    data = json.loads(p.read_text(errors="replace"))
                    for key in ("Cmax_ng_mL", "AUC0inf_h_ng_mL", "Tmax_h",
                                "t_half_h", "CL_L_h", "F_oral",
                                "Vss_L_kg", "CL_hep_L_h"):
                        if data.get(key) is not None:
                            metrics[key] = data[key]
                except (OSError, json.JSONDecodeError):
                    continue

        # 2. pk_summary_report.json — report with quality_tier, compound, pk_parameters
        for fname in ("pk_summary_report.json",):
            for p in (list(task_work_dir.glob(fname))
                      + list(task_work_dir.glob(f"**/{fname}"))):
                try:
                    data = json.loads(p.read_text(errors="replace"))
                    pk = data.get("pk_parameters", {})
                    for key in ("Cmax_ng_mL", "AUC0inf_h_ng_mL", "Tmax_h",
                                "t_half_h", "CL_L_h", "F_oral"):
                        if pk.get(key) is not None and key not in metrics:
                            metrics[key] = pk[key]
                    if data.get("quality_tier"):
                        metrics["pbpk_quality_tier"] = data["quality_tier"]
                    warnings = data.get("validation_warnings", [])
                    if warnings:
                        metrics["pbpk_validation_warnings"] = len(warnings)
                except (OSError, json.JSONDecodeError):
                    continue

        # 3. pk_profile.csv — check for monotonic (no-peak) concentration profile
        for fname in ("pk_profile.csv",):
            for p in (list(task_work_dir.glob(fname))
                      + list(task_work_dir.glob(f"**/{fname}"))):
                try:
                    import csv as _csv
                    rows = []
                    with open(p) as f:
                        reader = _csv.DictReader(f)
                        for row in reader:
                            try:
                                rows.append((float(row["time_h"]),
                                             float(row["Cblood_ng_mL"])))
                            except (KeyError, ValueError):
                                pass
                    if len(rows) >= 4:
                        times = [r[0] for r in rows]
                        concs = [r[1] for r in rows]
                        sim_end = times[-1]
                        metrics["pbpk_simulation_end_h"] = sim_end
                        # Tmax fraction: where in the simulation does the peak occur?
                        peak_idx = concs.index(max(concs))
                        peak_time = times[peak_idx]
                        metrics["pbpk_tmax_fraction"] = round(peak_time / sim_end, 3) if sim_end > 0 else 1.0
                        # Monotonic check: does the profile ever decline after peak?
                        post_peak = concs[peak_idx:]
                        metrics["pbpk_monotonic"] = all(
                            post_peak[i] <= post_peak[i - 1] * 1.01  # 1% tolerance for noise
                            for i in range(1, len(post_peak))
                        ) is False  # True = has decline = good; False = never declines = bad
                        # Overwrite Tmax if not already set from nca_parameters
                        if "Tmax_h" not in metrics:
                            metrics["Tmax_h"] = peak_time
                except (OSError, StopIteration):
                    continue

        if metrics:
            log.debug(
                "[QC] PBPK: Tmax=%.1fh t½=%s CL=%.4f F_oral=%.2f monotonic_decline=%s",
                metrics.get("Tmax_h", float("nan")),
                metrics.get("t_half_h"),
                metrics.get("CL_L_h", float("nan")),
                metrics.get("F_oral", float("nan")),
                metrics.get("pbpk_monotonic"),
            )
            return metrics
        return None

    def _parse_disease_state_results(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse disease-state PBPK report for renal/hepatic impairment QC.

        Reads ``disease_state_pk_report.json`` from the pbpk_disease_state workflow.

        Key QC fields:
          - ds_max_auc_ratio         : highest AUC_ratio across all impairment grades
          - ds_contraindicated        : True if any grade has AUC_ratio > 5 (FDA CI threshold)
          - ds_dose_adjustment_needed : True if any grade has AUC_ratio > 1.25 (FDA label trigger)
          - ds_max_cmax_ratio         : highest Cmax_ratio (safety relevance for NTI drugs)
        """
        for fname in ("disease_state_pk_report.json",):
            for p in (list(task_work_dir.glob(fname))
                      + list(task_work_dir.glob(f"**/{fname}"))):
                try:
                    data = json.loads(p.read_text(errors="replace"))
                    metrics: Dict[str, Any] = {}
                    max_auc = 0.0
                    max_cmax = 0.0
                    any_ci = False
                    any_adj = False
                    for section_key in ("renal_impairment", "hepatic_impairment"):
                        for scenario in data.get(section_key, []):
                            auc = scenario.get("AUC_ratio", 1.0) or 1.0
                            cmax = scenario.get("Cmax_ratio", 1.0) or 1.0
                            ci = scenario.get("contraindicated", False)
                            adj = (not ci) and auc > 1.25
                            max_auc = max(max_auc, auc)
                            max_cmax = max(max_cmax, cmax)
                            if ci:
                                any_ci = True
                            if adj:
                                any_adj = True
                    if max_auc > 0:
                        metrics["ds_max_auc_ratio"] = round(max_auc, 3)
                        metrics["ds_max_cmax_ratio"] = round(max_cmax, 3)
                        metrics["ds_contraindicated"] = any_ci
                        metrics["ds_dose_adjustment_needed"] = any_adj
                        log.debug(
                            "[QC] DiseaseStatePBPK: max_AUC_ratio=%.2f contraindicated=%s dose_adj=%s",
                            max_auc, any_ci, any_adj,
                        )
                        return metrics
                except (OSError, json.JSONDecodeError, KeyError):
                    continue
        return None

    def _parse_biomarker_enrichment_results(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse biomarker patient enrichment output for predictive enrichment QC.

        Reads ``biomarker_enrichment_results.json`` from the biomarker_patient_enrichment workflow.

        Key QC fields:
          - be_n_significant          : number of biomarkers passing FDR q < 0.05
          - be_max_enrichment_ratio   : highest enrichment_ratio across significant biomarkers
          - be_min_bc_sensitivity     : lowest bias-corrected sensitivity at optimal cut-point
          - be_min_phase3_pct_savings : lowest % sample-size reduction among significant biomarkers
        """
        for fname in ("biomarker_enrichment_results.json",):
            for p in (list(task_work_dir.glob(fname))
                      + list(task_work_dir.glob(f"**/{fname}"))):
                try:
                    data = json.loads(p.read_text(errors="replace"))
                    bm_results = data if isinstance(data, list) else data.get("results", [])
                    if isinstance(data, dict) and "biomarkers" in data:
                        bm_results = list(data["biomarkers"].values())
                    metrics: Dict[str, Any] = {}
                    sig = [bm for bm in bm_results if bm.get("fdr_significant")]
                    metrics["be_n_significant"] = len(sig)
                    if sig:
                        ers = [bm.get("enrichment_ratio") for bm in sig if bm.get("enrichment_ratio")]
                        metrics["be_max_enrichment_ratio"] = round(max(ers), 3) if ers else None
                        senses = [bm.get("cut_point_bc_sensitivity") for bm in sig
                                  if bm.get("cut_point_bc_sensitivity") is not None]
                        metrics["be_min_bc_sensitivity"] = round(min(senses), 4) if senses else None
                        savings = [bm.get("phase3_sample_size", {}).get("pct_savings")
                                   for bm in sig if bm.get("phase3_sample_size", {}).get("pct_savings")]
                        metrics["be_min_phase3_pct_savings"] = round(min(savings), 1) if savings else None
                    log.debug(
                        "[QC] BiomarkerEnrichment: n_sig=%d max_ER=%s min_sens=%s min_savings=%s%%",
                        metrics.get("be_n_significant", 0),
                        metrics.get("be_max_enrichment_ratio"),
                        metrics.get("be_min_bc_sensitivity"),
                        metrics.get("be_min_phase3_pct_savings"),
                    )
                    return metrics
                except (OSError, json.JSONDecodeError, KeyError):
                    continue
        return None

    def _parse_polymorph_stability_results(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse polymorph stability screening output for solid-state QC.

        Reads ``polymorph_stability_report.json`` from the polymorph_stability_screening workflow.

        Key QC fields:
          - ps_risk_score      : Fleming/Blagden heuristic score (0–10)
          - ps_risk_tier       : 'LOW' | 'MEDIUM' | 'HIGH'
          - ps_hygroscopic     : True if hygroscopicity class is 'HIGH'
          - ps_photostability  : photostability risk level ('LOW' | 'MEDIUM' | 'HIGH')
          - ps_xrpd_required   : True when tier is HIGH (ICH Q6A §3.1.1.5 mandate)
        """
        for fname in ("polymorph_stability_report.json",):
            for p in (list(task_work_dir.glob(fname))
                      + list(task_work_dir.glob(f"**/{fname}"))):
                try:
                    data = json.loads(p.read_text(errors="replace"))
                    poly = data.get("polymorph_risk", data)
                    stab = data.get("stability", {})
                    metrics: Dict[str, Any] = {}
                    risk_score = poly.get("risk_score")
                    risk_tier = poly.get("risk_tier", "")
                    if risk_score is not None:
                        metrics["ps_risk_score"] = risk_score
                    if risk_tier:
                        metrics["ps_risk_tier"] = risk_tier
                        metrics["ps_xrpd_required"] = (risk_tier == "HIGH")
                    hygro = stab.get("details", {}).get("hygroscopicity", {}).get("class") \
                            or data.get("hygroscopicity", {}).get("class")
                    if hygro:
                        metrics["ps_hygroscopic"] = (hygro == "HIGH")
                    photo = stab.get("details", {}).get("photostability", {}).get("risk") \
                            or data.get("photostability", {}).get("risk")
                    if photo:
                        metrics["ps_photostability"] = photo
                    log.debug(
                        "[QC] PolymorphScreening: risk_score=%s tier=%s hygro=%s photo=%s",
                        risk_score, risk_tier, hygro, photo,
                    )
                    if metrics:
                        return metrics
                except (OSError, json.JSONDecodeError, KeyError):
                    continue
        return None

    def _parse_nlmixr2_results(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse nlmixr2 population PK results.

        Reads ``nlmixr2_results.json`` produced by the nlmixr2_population_pk workflow.
        Key QC fields:
          - convergence_status      : "converged" | "not_converged" | "failed"
          - max_eta_shrinkage_pct   : random effects shrinkage (> 30% = parameters poorly estimated)
          - condition_number        : covariance matrix condition (> 1000 = parameter correlation)
          - ofv                     : objective function value
        """
        for fname in ("nlmixr2_results.json",):
            for p in (list(task_work_dir.glob(fname))
                      + list(task_work_dir.glob(f"**/{fname}"))):
                try:
                    data = json.loads(p.read_text(errors="replace"))
                    metrics: Dict[str, Any] = {}
                    for key in ("convergence_status", "ofv", "model_type", "algorithm",
                                "n_subjects", "n_observations", "max_eta_shrinkage_pct",
                                "condition_number", "aic", "bic"):
                        if data.get(key) is not None:
                            metrics[key] = data[key]
                    if metrics:
                        log.debug(
                            f"[QC] Population PK: convergence={metrics.get('convergence_status')}, "
                            f"ETA shrinkage={metrics.get('max_eta_shrinkage_pct')}%, "
                            f"condition={metrics.get('condition_number')}"
                        )
                        return metrics
                except (OSError, json.JSONDecodeError, KeyError):
                    continue
        return None

    def _parse_ivive_results(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse IVIVE hepatic clearance scaling output.

        Reads ``ivive_results.json`` produced by the ivive_hepatic_clearance workflow.
        Key QC fields:
          - clh_predicted_ml_min_kg   : predicted hepatic clearance (mL/min/kg)
          - clh_fraction_of_qh        : CLh as fraction of hepatic blood flow (0–1)
          - scaling_method            : "well_stirred" | "parallel_tube" | "dispersion"
          - fu_plasma                 : fraction unbound in plasma used
          - clint_scaled_ml_min_kg    : scaled intrinsic clearance
        """
        for fname in ("ivive_results.json",):
            for p in (list(task_work_dir.glob(fname))
                      + list(task_work_dir.glob(f"**/{fname}"))):
                try:
                    data = json.loads(p.read_text(errors="replace"))
                    metrics: Dict[str, Any] = {}
                    for key in ("clh_predicted_ml_min_kg", "clh_fraction_of_qh",
                                "scaling_method", "fu_plasma", "clint_scaled_ml_min_kg",
                                "species", "clh_lower_ci", "clh_upper_ci"):
                        if data.get(key) is not None:
                            metrics[key] = data[key]
                    if metrics:
                        log.debug(
                            f"[QC] IVIVE: CLh={metrics.get('clh_predicted_ml_min_kg')} mL/min/kg, "
                            f"fraction of QH={metrics.get('clh_fraction_of_qh')}"
                        )
                        return metrics
                except (OSError, json.JSONDecodeError, KeyError):
                    continue
        return None

    def _parse_docking_results(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse molecular docking output.

        Reads ``docking_results.json`` written by the molecular_docking workflow step.

        Key QC fields:
          best_score_kcal_mol  — most favourable (most negative) binding energy across all poses (kcal/mol).
            AutoDock Vina convention: more negative = stronger binding.
            Typical hit threshold: ≤ −7 kcal/mol (community heuristic; Trott & Olson 2010 J Comput Chem).
          top_pose_rmsd_angstrom — RMSD of top pose relative to known/reference ligand (optional).
            > 2 Å RMSD from reference = pose unreliable for pharmacophore work.
          n_poses_generated — number of valid docking poses produced.
            < 5 may indicate steric clash or parameter issue.
        """
        for fname in ("docking_autodock_vina_results.json", "docking_results.json",
                      "vina_results.json", "glide_results.json"):
            for p in (list(task_work_dir.glob(fname))
                      + list(task_work_dir.glob(f"**/{fname}"))):
                try:
                    data = json.loads(p.read_text(errors="replace"))
                    metrics: Dict[str, Any] = {}

                    # Direct top-level fields (preferred format)
                    for key in ("best_score_kcal_mol", "top_pose_rmsd_angstrom",
                                "n_poses_generated", "docking_software", "receptor"):
                        if data.get(key) is not None:
                            metrics[key] = data[key]

                    # AutoDock Vina workflow format: data["scores"] = {smiles: score_float}
                    # Derives best_score_kcal_mol and n_poses_generated when not already present
                    if "scores" in data and isinstance(data["scores"], dict):
                        valid_scores = [
                            v for v in data["scores"].values()
                            if v is not None and isinstance(v, (int, float))
                        ]
                        if valid_scores:
                            if "best_score_kcal_mol" not in metrics:
                                metrics["best_score_kcal_mol"] = min(valid_scores)
                            if "n_poses_generated" not in metrics:
                                metrics["n_poses_generated"] = len(valid_scores)

                    if metrics:
                        log.debug(
                            f"[QC] Docking: best_score={metrics.get('best_score_kcal_mol')} kcal/mol, "
                            f"poses={metrics.get('n_poses_generated')}"
                        )
                        return metrics
                except (OSError, json.JSONDecodeError, KeyError):
                    continue
        return None

    def _parse_cyp_ddi_results(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse CYP DDI risk assessment output from the cyp_ddi_panel workflow.

        Reads (in priority order):
          1. ``ddi_risk_assessment.json`` — structured DDI risk per isoform with R1/R2 flags
          2. ``cyp_panel_summary.json``   — merged summary from DDI_REPORT process

        Returns a dict matching the CYPDDIQCEvaluator input schema:
          {
            "summary": {
              "n_clinical": int,        # isoforms flagged CLINICAL_STUDY_RECOMMENDED
              "n_investigate": int,     # isoforms flagged INVESTIGATE
              "n_tdi": int,             # isoforms with TDI structural alerts
              "overall_recommendation": str
            }
          }
        """
        for fname in ("ddi_risk_assessment.json", "cyp_panel_summary.json"):
            for p in (list(task_work_dir.glob(fname))
                      + list(task_work_dir.glob(f"**/{fname}"))):
                try:
                    data = json.loads(p.read_text(errors="replace"))

                    # ddi_risk_assessment.json has a top-level "summary" dict
                    if "summary" in data:
                        s = data["summary"]
                        metrics = {
                            "summary": {
                                "n_clinical": int(
                                    s.get("n_clinical_study_recommended",
                                          s.get("n_clinical", 0)) or 0
                                ),
                                "n_investigate": int(s.get("n_investigate", 0) or 0),
                                "n_tdi": int(
                                    s.get("n_tdi_flagged", s.get("n_tdi", 0)) or 0
                                ),
                                "overall_recommendation": str(
                                    s.get("overall_recommendation", "NOT_EXPECTED")
                                ),
                            }
                        }
                        log.debug(
                            f"[QC] CYP DDI: {metrics['summary']}"
                        )
                        return metrics

                    # cyp_panel_summary.json nests DDI risk under "ddi_risk"
                    if "ddi_risk" in data and "summary" in data["ddi_risk"]:
                        s = data["ddi_risk"]["summary"]
                        metrics = {
                            "summary": {
                                "n_clinical": int(
                                    s.get("n_clinical_study_recommended",
                                          s.get("n_clinical", 0)) or 0
                                ),
                                "n_investigate": int(s.get("n_investigate", 0) or 0),
                                "n_tdi": int(
                                    s.get("n_tdi_flagged", s.get("n_tdi", 0)) or 0
                                ),
                                "overall_recommendation": str(
                                    data.get("overall_recommendation",
                                             s.get("overall_recommendation", "NOT_EXPECTED"))
                                ),
                            }
                        }
                        log.debug(f"[QC] CYP DDI (panel summary): {metrics['summary']}")
                        return metrics

                except (OSError, json.JSONDecodeError, KeyError, TypeError):
                    continue

        log.debug(f"[QC] No CYP DDI results found in {task_work_dir}")
        return None

    def _parse_qsar_results(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse QSAR model evaluation output.

        Reads ``qsar_results.json`` written by the qsar_model workflow step.

        Key QC fields:
          cv_r2_score      — cross-validated R² (0–1).
            < 0.5 is typically considered uninformative (Golbraikh & Tropsha 2002 J Mol Graph Model).
          cv_rmse          — cross-validated RMSE in the same units as the target.
          test_r2_score    — holdout test set R² (when available).
          n_compounds      — number of compounds in training set.
            < 50 makes QSAR models unreliable.
          model_type       — "random_forest", "xgboost", "chemprop", etc.
        """
        for fname in ("qsar_results.json", "model_metrics.json"):
            for p in (list(task_work_dir.glob(fname))
                      + list(task_work_dir.glob(f"**/{fname}"))):
                try:
                    data = json.loads(p.read_text(errors="replace"))
                    metrics: Dict[str, Any] = {}
                    for key in ("cv_r2_score", "cv_rmse", "test_r2_score",
                                "n_compounds", "model_type", "target_property"):
                        if data.get(key) is not None:
                            metrics[key] = data[key]
                    if metrics:
                        log.debug(
                            f"[QC] QSAR: R²={metrics.get('cv_r2_score')}, "
                            f"n_compounds={metrics.get('n_compounds')}"
                        )
                        return metrics
                except (OSError, json.JSONDecodeError, KeyError):
                    continue
        return None

    def _check_qc_thresholds(
        self,
        process_name: str,
        qc_metrics: Dict[str, Any]
    ) -> tuple[bool, list]:
        """
        Check if QC metrics meet quality thresholds.

        Returns:
            (qc_passed, list_of_structured_failure_dicts)

        Each failure dict has the keys:
            metric    – exact metric name from qc_metrics
            value     – actual measured value
            threshold – threshold value that was violated
            operator  – ">" or "<" indicating the direction of violation
            message   – human-readable description
        """
        failures = []
        process_upper = process_name.upper()

        if "MOTION_CORRECTION" in process_upper:
            total_drift = qc_metrics.get("total_drift_angstrom")
            _drift_t = self._get_threshold("total_drift_angstrom", 50)
            if total_drift is not None and total_drift > _drift_t:
                failures.append({
                    "metric": "total_drift_angstrom",
                    "value": total_drift,
                    "threshold": _drift_t,
                    "operator": ">",
                    "message": f"Excessive drift: {total_drift:.1f}Å (threshold: {_drift_t:.0f}Å)"
                })

            correlation = qc_metrics.get("correlation_score")
            _corr_t = self._get_threshold("correlation_score", 0.5)
            if correlation is not None and correlation < _corr_t:
                failures.append({
                    "metric": "correlation_score",
                    "value": correlation,
                    "threshold": _corr_t,
                    "operator": "<",
                    "message": f"Low correlation: {correlation:.3f} (threshold: {_corr_t:.1f})"
                })

        elif "CTF_ESTIMATION" in process_upper or "CTF_ESTIMATE" in process_upper:
            if qc_metrics.get("defocus_out_of_range"):
                du = qc_metrics.get("defocus_u_angstrom", 0)
                direction = qc_metrics.get("defocus_direction", "outside")
                if direction == "below":
                    msg = (f"Estimated defocus {du:.0f}Å is near-focus "
                           f"(valid range 1,000–100,000Å). Consider collecting at "
                           f"1.0–3.0 μm underfocus, or widen the CTF search range minimum.")
                else:
                    msg = (f"Estimated defocus {du:.0f}Å is too far from focus "
                           f"(valid range 1,000–100,000Å). Check for stage drift or "
                           f"incorrect microscope calibration.")
                failures.append({
                    "metric": "defocus_u_angstrom",
                    "value": du,
                    "threshold": 1000 if direction == "below" else 100000,
                    "operator": "<" if direction == "below" else ">",
                    "message": msg
                })

            astigmatism = qc_metrics.get("astigmatism_angstrom")
            # [BRONZE] No published consensus threshold for astigmatism-only gating.
            # The field primarily uses fit_quality (CTF resolution) as the authoritative gate.
            # Published high-resolution structures have been obtained with 500–2000Å astigmatism.
            # 1000Å used here as an ADVISORY (non-blocking) marker for operator awareness.
            # source: CryoSPARC v4 documentation; community practice only.
            _astig_t = self._get_threshold("astigmatism_angstrom", 1000)
            if astigmatism is not None and astigmatism > _astig_t:
                failures.append({
                    "metric": "astigmatism_angstrom",
                    "value": astigmatism,
                    "threshold": _astig_t,
                    "operator": ">",
                    "advisory": True,  # non-blocking: fit_quality is the primary CTF gate
                    "message": f"Elevated astigmatism: {astigmatism:.0f}Å (advisory: {_astig_t:.0f}Å). "
                               f"Note: CTF fit quality is the primary quality indicator. "
                               f"High astigmatism may indicate lens contamination, coma, or specimen charging. "
                               f"Review micrographs if fit_quality is also degraded."
                })

            fit = qc_metrics.get("fit_quality")
            _fit_t = self._get_threshold("fit_quality", 0.7)
            if fit is not None and fit < _fit_t:
                failures.append({
                    "metric": "fit_quality",
                    "value": fit,
                    "threshold": _fit_t,
                    "operator": "<",
                    "message": f"Poor CTF fit: {fit:.3f} (threshold: {_fit_t:.1f})"
                })

            # --- Volta Phase Plate gates (advisory only; only fired when data present) ---
            # Ref: Danev & Bharat 2018 Trends Cell Biol — optimal phase shift 0.4–0.8π (≈1.3–2.5 rad)
            # practical range for productive VPP: 0.2–1.5 rad
            phase_shift = qc_metrics.get("avg_phase_shift_rad")
            if phase_shift is not None:
                _ps_min = self._get_threshold("avg_phase_shift_rad_min", 0.2)
                _ps_max = self._get_threshold("avg_phase_shift_rad_max", 1.5)
                if phase_shift < _ps_min:
                    failures.append({
                        "metric": "avg_phase_shift_rad",
                        "value": phase_shift,
                        "threshold": _ps_min,
                        "operator": "<",
                        "advisory": True,
                        "message": (
                            f"[BRONZE] Volta Phase Plate appears depleted: avg phase shift "
                            f"{phase_shift:.3f} rad < {_ps_min:.2f} rad advisory minimum. "
                            f"Move the phase plate to a fresher position or condition it with "
                            f"higher fluence before continuing data collection."
                        ),
                    })
                elif phase_shift > _ps_max:
                    failures.append({
                        "metric": "avg_phase_shift_rad",
                        "value": phase_shift,
                        "threshold": _ps_max,
                        "operator": ">",
                        "advisory": True,
                        "message": (
                            f"[BRONZE] Volta Phase Plate is over-charged: avg phase shift "
                            f"{phase_shift:.3f} rad > {_ps_max:.2f} rad advisory maximum. "
                            f"Advance to a fresh VPP spot; over-charged plates introduce "
                            f"non-uniform phase shifts that degrade CTF correction."
                        ),
                    })

        elif "PARTICLE_PICKING" in process_upper or "PICKING" in process_upper:
            count = qc_metrics.get("particles_picked")
            _pick_t = self._get_threshold("particles_picked", 1000)
            if count is not None and count < _pick_t:
                failures.append({
                    "metric": "particles_picked",
                    "value": count,
                    "threshold": _pick_t,
                    "operator": "<",
                    "message": f"Too few particles: {count} (threshold: {_pick_t:.0f})"
                })

            duplicate_frac = qc_metrics.get("duplicate_fraction")
            # "duplicate_fraction_picking" key to avoid conflict with FLAGSTAT duplicate_pct
            _dup_pick_t = self._get_threshold("duplicate_fraction_picking", 0.2)
            if duplicate_frac is not None and duplicate_frac > _dup_pick_t:
                failures.append({
                    "metric": "duplicate_fraction",
                    "value": duplicate_frac,
                    "threshold": _dup_pick_t,
                    "operator": ">",
                    "message": f"High duplicate fraction: {duplicate_frac:.1%} (threshold: {_dup_pick_t:.0%})"
                })

        elif any(k in process_upper for k in ("CLASSIFY_2D", "CLASS_2D", "2D_CLASSIFICATION",
                                               "2DCLASSIFICATION")):
            # [advisory] Junk class fraction — high fraction of particles in low-quality 2D classes.
            # Gates on junk_class_fraction derived from class2d_report.json num_good_classes/num_classes.
            # > 0.70 → heavy junk, effectively useless (BRONZE advisory — does not block by default)
            # community heuristic; no published consensus threshold.
            junk_frac = qc_metrics.get("junk_class_fraction")
            _junk_t = self._get_threshold("junk_class_fraction", 0.5)
            if junk_frac is not None and junk_frac > _junk_t:
                failures.append({
                    "metric": "junk_class_fraction",
                    "value": junk_frac,
                    "threshold": _junk_t,
                    "operator": ">",
                    "advisory": True,
                    "message": (
                        f"[BRONZE] High junk class fraction: {junk_frac:.1%} of 2D classes "
                        f"are low-quality (advisory threshold: {_junk_t:.0%}). "
                        f"Consider re-picking with a stricter threshold, checking ice thickness, "
                        f"or reviewing the particle extraction box size."
                    ),
                })

        elif any(k in process_upper for k in ("HOMOGENEOUS_REFINEMENT", "NONUNIFORM_REFINEMENT",
                                               "HETEROGENEOUS_REFINEMENT", "VALIDATION_FSC",
                                               "LOCAL_CTF_REFINEMENT", "AB_INITIO")):
            # [GOLD] FSC 0.143 resolution gate — Henderson et al. 2012 gold-standard criterion.
            # 10Å as the gate: coarser than 10Å is not interpretable for drug discovery targets.
            # Note: smaller Å value = higher resolution (better). Gate fires when value > threshold.
            fsc_res = qc_metrics.get("fsc_resolution_angstrom")
            _fsc_t = self._get_threshold("fsc_resolution_angstrom", 10.0)
            if fsc_res is not None and fsc_res > _fsc_t:
                failures.append({
                    "metric": "fsc_resolution_angstrom",
                    "value": fsc_res,
                    "threshold": _fsc_t,
                    "operator": ">",
                    "message": (
                        f"Poor reconstruction: FSC 0.143 resolution {fsc_res:.1f}Å "
                        f"(gate: better than {_fsc_t:.0f}Å). "
                        f"Consider increasing particle count, re-examining 2D class selection, "
                        f"or checking for preferred orientation artifacts."
                    ),
                })

            # [advisory] Junk class fraction — high fraction of particles in rejected 2D classes.
            # Threshold 0.5 (50%) is a community heuristic; does not block workflow.
            junk_frac = qc_metrics.get("junk_class_fraction")
            _junk_t = self._get_threshold("junk_class_fraction", 0.5)
            if junk_frac is not None and junk_frac > _junk_t:
                failures.append({
                    "metric": "junk_class_fraction",
                    "value": junk_frac,
                    "threshold": _junk_t,
                    "operator": ">",
                    "advisory": True,
                    "message": (
                        f"High junk class fraction: {junk_frac:.1%} of particles in low-quality "
                        f"2D classes (advisory threshold: {_junk_t:.0%}). "
                        f"Consider lowering the particle picker threshold or re-selecting 2D classes."
                    ),
                })

        elif any(k in process_upper for k in ("SHARPEN", "CTF_REFINE_SHARPEN",
                                               "POSTPROCESS", "POSTPROCESSING")):
            # [BRONZE advisory] B-factor out of expected range.
            # Rosenthal & Henderson 2003 JMB 333:721 — typical values −50 to −200 Å².
            # B > 0 (blurring) is unexpected in post-processing; B < −300 indicates over-sharpening.
            bfactor = qc_metrics.get("bfactor_angstrom_squared")
            if bfactor is not None:
                if bfactor > 0:
                    failures.append({
                        "metric": "bfactor_angstrom_squared",
                        "value": bfactor,
                        "threshold": 0,
                        "operator": ">",
                        "advisory": True,
                        "message": (
                            f"[BRONZE] Applied B-factor {bfactor:.1f} Å² is positive (blurring). "
                            f"Expected negative sharpening (−50 to −200 Å²). "
                            f"Check that the correct half-maps were used for post-processing."
                        ),
                    })
                elif bfactor < -300:
                    failures.append({
                        "metric": "bfactor_angstrom_squared",
                        "value": bfactor,
                        "threshold": -300,
                        "operator": "<",
                        "advisory": True,
                        "message": (
                            f"[BRONZE] Applied B-factor {bfactor:.1f} Å² is very large negative — "
                            f"over-sharpening may introduce map artefacts. "
                            f"Typical range: −50 to −200 Å² (Rosenthal & Henderson 2003). "
                            f"Consider using automated B-factor estimation or DeepEMhancer."
                        ),
                    })

        elif any(k in process_upper for k in ("MOLPROBITY", "EMRINGER", "MODEL_QUALITY", "MODEL_VALIDATION", "ALPHAFOLD_FIT")):
            # MolProbity Ramachandran outliers — advisory >2%
            rama = qc_metrics.get("ramachandran_outliers_pct")
            if rama is not None and rama > 2.0:
                failures.append({
                    "metric": "ramachandran_outliers_pct",
                    "value": rama,
                    "threshold": 2.0,
                    "severity": "BRONZE",
                    "advisory": True,
                    "message": (
                        f"Ramachandran outliers {rama:.1f}% > 2.0% advisory. "
                        "Good structures have < 2% Ramachandran outliers (MolProbity guidelines). "
                        "[BRONZE] Advisory — consider real-space refinement."
                    ),
                })
            # MolProbity Rotamer outliers — advisory >5%
            rota = qc_metrics.get("rotamer_outliers_pct")
            if rota is not None and rota > 5.0:
                failures.append({
                    "metric": "rotamer_outliers_pct",
                    "value": rota,
                    "threshold": 5.0,
                    "severity": "BRONZE",
                    "advisory": True,
                    "message": (
                        f"Rotamer outliers {rota:.1f}% > 5.0% advisory. "
                        "[BRONZE] Advisory — consider PHENIX real_space_refine."
                    ),
                })
            # MolProbity Clashscore — advisory >20
            clash = qc_metrics.get("clashscore")
            if clash is not None and clash > 20.0:
                failures.append({
                    "metric": "clashscore",
                    "value": clash,
                    "threshold": 20.0,
                    "severity": "BRONZE",
                    "advisory": True,
                    "message": (
                        f"MolProbity clashscore {clash:.1f} > 20.0 advisory. "
                        "Score < 20 expected for well-refined cryo-EM models. "
                        "[BRONZE] Advisory — run PHENIX real_space_refine."
                    ),
                })
            # EMRinger score — advisory <1.0
            emringer = qc_metrics.get("emringer_score")
            if emringer is not None and emringer < 1.0:
                failures.append({
                    "metric": "emringer_score",
                    "value": emringer,
                    "threshold": 1.0,
                    "severity": "BRONZE",
                    "advisory": True,
                    "message": (
                        f"EMRinger score {emringer:.2f} < 1.0 advisory. "
                        "Scores > 1.0 indicate good side-chain-to-density fit "
                        "(Barad BA et al. 2015 Nat Methods 12(10):943-946). "
                        "[BRONZE] Advisory — model may need rotamer correction."
                    ),
                })

        elif any(k in process_upper for k in ("LOCAL_RESOLUTION", "LOCALRES",
                                               "MONORES", "RESMAP")):
            # [BRONZE advisory] High spread in local resolution distribution.
            # Vilas et al. 2018 Structure 26:337 — σ > 3 Å indicates high conformational disorder.
            std = qc_metrics.get("std_spread_angstrom")
            _std_t = self._get_threshold("local_resolution_std_spread", 3.0)
            if std is not None and std > _std_t:
                failures.append({
                    "metric": "std_spread_angstrom",
                    "value": std,
                    "threshold": _std_t,
                    "operator": ">",
                    "advisory": True,
                    "message": (
                        f"[BRONZE] Local resolution spread σ={std:.1f} Å (advisory: < {_std_t:.1f} Å). "
                        f"High heterogeneity may indicate flexible regions, preferred orientation, "
                        f"or a mixed particle population. Consider 3D variability analysis or "
                        f"focused classification on the disordered region."
                    ),
                })

        # --- RNA-seq / sequencing quality ---
        elif any(k in process_upper for k in ("FASTQC", "MULTIQC")):
            module_failures = qc_metrics.get("module_failures")
            if module_failures is not None and module_failures > 0:
                failures.append({
                    "metric": "module_failures",
                    "value": module_failures,
                    "threshold": 0,
                    "operator": ">",
                    "message": f"FastQC: {module_failures} module(s) FAILED"
                })

        elif any(k in process_upper for k in ("FASTP", "TRIMGALORE", "TRIMMOMATIC", "BBDUK")):
            surviving = qc_metrics.get("reads_surviving_pct")
            _surv_t = self._get_threshold("reads_surviving_pct", 70.0)
            if surviving is not None and surviving < _surv_t:
                failures.append({
                    "metric": "reads_surviving_pct",
                    "value": surviving,
                    "threshold": _surv_t,
                    "operator": "<",
                    "message": f"Low read survival: {surviving:.1f}% (threshold: {_surv_t:.0f}%)"
                })
            q30 = qc_metrics.get("q30_pct")
            _q30_t = self._get_threshold("q30_pct", 75.0)
            if q30 is not None and q30 < _q30_t:
                failures.append({
                    "metric": "q30_pct",
                    "value": q30,
                    "threshold": _q30_t,
                    "operator": "<",
                    "message": f"Low Q30: {q30:.1f}% (threshold: {_q30_t:.0f}%)"
                })

        elif any(k in process_upper for k in ("STAR_ALIGN", "STAR_GENOME", "HISAT2_ALIGN",
                                               "HISAT2", "BOWTIE2_ALIGN", "BOWTIE2",
                                               "BWA_MEM", "BWA_MEM2", "BWAMEM")):
            rate = qc_metrics.get("alignment_rate")
            if rate is None:
                rate = qc_metrics.get("uniquely_mapped_pct")
            _align_t = self._get_threshold("alignment_rate", 70.0)
            if rate is not None and rate < _align_t:
                # The critical sub-tier (< 25%) detects sample swap / catastrophic contamination.
                # Its threshold is fixed (not user-overridable) — it is a red-line condition.
                if rate < 25.0:
                    msg = (f"Critically low alignment rate: {rate:.1f}% (threshold: {_align_t:.0f}%). "
                           f"Values below 25% usually indicate a species/genome mismatch, "
                           f"corrupt input, or heavy contamination — verify input data "
                           f"before adjusting parameters.")
                    sev = "critical"
                else:
                    msg = f"Low alignment rate: {rate:.1f}% (threshold: {_align_t:.0f}%)"
                    sev = "warning"
                failures.append({
                    "metric": "alignment_rate",
                    "value": rate,
                    "threshold": _align_t,
                    "operator": "<",
                    "message": msg,
                    "severity": sev
                })

        elif any(k in process_upper for k in ("FEATURECOUNTS", "SUBREAD", "HTSEQ")):
            assigned = qc_metrics.get("assigned_reads_pct")
            _assign_t = self._get_threshold("assigned_reads_pct", 50.0)
            if assigned is not None and assigned < _assign_t:
                failures.append({
                    "metric": "assigned_reads_pct",
                    "value": assigned,
                    "threshold": _assign_t,
                    "operator": "<",
                    "message": f"Low feature assignment: {assigned:.1f}% (threshold: {_assign_t:.0f}%)"
                })

        elif any(k in process_upper for k in ("SALMON_QUANT", "SALMON", "KALLISTO")):
            mapping = qc_metrics.get("mapping_rate")
            _map_t = self._get_threshold("mapping_rate", 50.0)
            if mapping is not None and mapping < _map_t:
                failures.append({
                    "metric": "mapping_rate",
                    "value": mapping,
                    "threshold": _map_t,
                    "operator": "<",
                    "message": f"Low mapping rate: {mapping:.1f}% (threshold: {_map_t:.0f}%)"
                })

        # --- DNA-seq ---
        elif any(k in process_upper for k in ("FLAGSTAT", "SAMTOOLS_FLAGSTAT", "SAMTOOLS_STATS")):
            mapped = qc_metrics.get("mapped_pct")
            # mapped_pct is GOLD (GATK Best Practices) — threshold hardcoded; _get_threshold will
            # ignore any override and return the default. The call is still made for transparency.
            if mapped is not None and mapped < self._get_threshold("mapped_pct", 70.0):
                failures.append({
                    "metric": "mapped_pct",
                    "value": mapped,
                    "threshold": 70.0,
                    "operator": "<",
                    "message": f"Low mapping: {mapped:.1f}% (threshold: 70%)"
                })
            dup = qc_metrics.get("duplicate_pct")
            _dup_t = self._get_threshold("duplicate_pct", 40.0)
            if dup is not None and dup > _dup_t:
                failures.append({
                    "metric": "duplicate_pct",
                    "value": dup,
                    "threshold": _dup_t,
                    "operator": ">",
                    "message": f"High duplication: {dup:.1f}% (threshold: {_dup_t:.0f}%)"
                })

        elif any(k in process_upper for k in ("MARKDUPLICATES", "PICARD_MARKDUP",
                                               "MARKDUP", "GATK_MARKDUP")):
            dup = qc_metrics.get("duplicate_pct")
            # source: GATK Best Practices (WGS ≤ 20-30%); dupRadar (PMC5073875) shows
            # RNA-seq duplication is biologically expected from high-expression — skip for rna_seq.
            # Also skip ChIP-seq and ATAC-seq: enriched regions produce expected high duplication
            # that does NOT indicate library quality problems.
            _skip_domains = ("rna_seq", "rnaseq", "rna", "scrna_seq", "single_cell",
                             "atac_seq", "atacseq", "chip_seq", "chipseq",
                             "cut_and_run", "cutandrun")
            if dup is not None and self.workflow_domain not in _skip_domains:
                _dup_t = self._get_threshold("duplicate_pct", 40.0)
                if dup > _dup_t:
                    failures.append({
                        "metric": "duplicate_pct",
                        "value": dup,
                        "threshold": _dup_t,
                        "operator": ">",
                        "message": f"High PCR duplication: {dup:.1f}% (threshold: {_dup_t:.0f}%). "
                                   f"Indicates low library complexity — consider deeper sequencing "
                                   f"or additional PCR cycles during library prep."
                    })

        # --- CRISPR screen / Perturb-seq guide library ---
        elif any(k in process_upper for k in ("MAGECK_COUNT", "MAGECK_MLE", "MAGECK_TEST", "CRISPRRESSO", "GUIDE_ASSIGN", "PERTURB_SEQ")):
            guide_cov = qc_metrics.get("guide_library_coverage_pct")
            _guide_t = self._get_threshold("guide_library_coverage_pct", 70.0)
            if guide_cov is not None and guide_cov < _guide_t:
                failures.append({
                    "metric": "guide_library_coverage_pct",
                    "value": guide_cov,
                    "threshold": _guide_t,
                    "severity": "SILVER",
                    "message": (
                        f"Guide library coverage {guide_cov:.1f}% below {_guide_t:.0f}% threshold. "
                        "Low coverage reduces statistical power for hit calling. "
                        "[SILVER] Replogle et al. 2022 Cell Supp Methods."
                    ),
                })
            transf = qc_metrics.get("transfection_efficiency_pct")
            _transf_t = self._get_threshold("transfection_efficiency_pct", 30.0)
            if transf is not None and transf < _transf_t:
                failures.append({
                    "metric": "transfection_efficiency_pct",
                    "value": transf,
                    "threshold": _transf_t,
                    "severity": "BRONZE",
                    "advisory": True,
                    "message": (
                        f"Transfection/transduction efficiency {transf:.1f}% below {_transf_t:.0f}%. "
                        "Low efficiency increases unperturbed cell fraction. "
                        "[BRONZE] Advisory only — acceptable for pilot screens."
                    ),
                })
            doublets = qc_metrics.get("doublet_fraction_pct")
            _doublet_t = self._get_threshold("max_doublet_fraction_pct", 10.0)
            if doublets is not None and doublets > _doublet_t:
                failures.append({
                    "metric": "doublet_fraction_pct",
                    "value": doublets,
                    "threshold": _doublet_t,
                    "severity": "SILVER",
                    "advisory": True,
                    "message": (
                        f"Predicted doublet fraction {doublets:.1f}% exceeds {_doublet_t:.0f}% advisory. "
                        "High doublet rate inflates guide co-occurrence and confounds perturbation effects. "
                        "[SILVER] Advisory. Consider DoubletFinder filtering before MAGeCK."
                    ),
                })

        # --- Single-cell ---
        elif any(k in process_upper for k in ("CELLRANGER_COUNT", "CELLRANGER",
                                               "STARSOLO", "ALEVIN")):
            cells = qc_metrics.get("cells_detected")
            _cells_t = self._get_threshold("cells_detected", 200)
            if cells is not None and cells < _cells_t:
                failures.append({
                    "metric": "cells_detected",
                    "value": cells,
                    "threshold": _cells_t,
                    "operator": "<",
                    "message": f"Too few cells: {cells} (threshold: {_cells_t:.0f})"
                })
            genes = qc_metrics.get("median_genes_per_cell")
            _genes_t = self._get_threshold("median_genes_per_cell", 500)
            if genes is not None and genes < _genes_t:
                failures.append({
                    "metric": "median_genes_per_cell",
                    "value": genes,
                    "threshold": _genes_t,
                    "operator": "<",
                    "message": f"Low median genes/cell: {genes} (threshold: {_genes_t:.0f})"
                })
            # source: Osorio & Cai (2021) Bioinformatics PMC8599307 — tissue-specific thresholds:
            # 5% for mouse, 10% for human. 20% used here as a permissive universal gate covering
            # high-respiration cell types; Luecken & Theis (2019) MSB e8746 recommends adaptive
            # MAD-based thresholds. Values > 20% are generally indicative of dead/compromised cells.
            # Override allowed up to the red-line ceiling of 80% (cardiac/muscle tissue use cases).
            mito = qc_metrics.get("mito_fraction_pct")
            _mito_t = self._get_threshold("mito_fraction_pct", 20.0)
            if mito is not None and mito > _mito_t:
                failures.append({
                    "metric": "mito_fraction_pct",
                    "value": mito,
                    "threshold": _mito_t,
                    "operator": ">",
                    "message": f"High mitochondrial fraction: {mito:.1f}% (threshold: {_mito_t:.0f}%). "
                               f"Indicates dead or compromised cells. Published evidence supports "
                               f"5% (mouse) / 10% (human) as ideal; 20% used as permissive universal gate."
                })

        # --- Coverage depth (mosdepth / Picard WGS) ---
        elif any(k in process_upper for k in ("MOSDEPTH", "SAMTOOLS_COVERAGE",
                                               "GATK_COVERAGE", "PICARD_WGS")):
            cov = qc_metrics.get("mean_coverage")
            # source: GATK Best Practices — WGS ≥ 30X germline; WES ≥ 80X germline,
            # ≥ 150X somatic (Illumina/GATK guidelines; Sims et al. 2014 Nature Rev Genet).
            # Apply WES threshold when workflow domain indicates exome/targeted sequencing.
            _wes_domains = ("wes", "whole_exome", "exome_seq", "exome", "targeted_seq", "targeted")
            _is_wes = self.workflow_domain in _wes_domains
            _default_cov = 80.0 if _is_wes else 30.0
            _label = "WES germline" if _is_wes else "WGS germline"
            # Apply user override on top of the domain-adjusted default.
            # Override key "mean_coverage" applies regardless of WES/WGS context.
            _cov_t = self._get_threshold("mean_coverage", _default_cov)
            if cov is not None and cov < _cov_t:
                failures.append({
                    "metric": "mean_coverage",
                    "value": cov,
                    "threshold": _cov_t,
                    "operator": "<",
                    "message": f"Low genome coverage: {cov:.1f}X (threshold: {_cov_t:.0f}X for {_label}). "
                               f"GATK Best Practices: ≥ 30X WGS, ≥ 80X WES germline, ≥ 150X WES somatic."
                })

        # --- ChIP-seq / ATAC-seq ---
        elif any(k in process_upper for k in ("MACS2", "MACS3", "CALLPEAK")):
            peaks = qc_metrics.get("peaks_called")
            _peaks_t = self._get_threshold("peaks_called", 1000)
            if peaks is not None and peaks < _peaks_t:
                failures.append({
                    "metric": "peaks_called",
                    "value": peaks,
                    "threshold": _peaks_t,
                    "operator": "<",
                    "message": f"Too few peaks: {peaks} (threshold: {_peaks_t:.0f})"
                })
            # source: ENCODE4 ChIP-seq explicitly does NOT define a hard FRiP threshold
            # (ENCODE4 TF/histone pages state FRiP is "collected without defined thresholds").
            # The historical 1% (0.01) figure is from Landt et al. 2012 (ENCODE2/3) and
            # is used here only as an extreme-low advisory, not a mandatory gate.
            frip = qc_metrics.get("frip_score")
            # [ADVISORY] ENCODE4 explicitly does NOT define a hard FRiP threshold for ChIP-seq.
            # ENCODE4 states FRiP is "collected without defined thresholds" (2024 standards page).
            # The historical 1% (0.01) figure is from Landt et al. 2012 (ENCODE2/3) only.
            # This fires as advisory-only (non-blocking) — workflow continues.
            if frip is not None and frip < 0.01:
                failures.append({
                    "metric": "frip_score",
                    "value": frip,
                    "threshold": 0.01,
                    "operator": "<",
                    "severity": "warning",
                    "advisory": True,  # non-blocking: ENCODE4 has no hard FRiP gate
                    "message": f"Very low FRiP score: {frip:.4f} (advisory: 0.01). "
                               f"ENCODE4 does not mandate a hard FRiP cutoff; this is advisory only "
                               f"(historical ENCODE2/3 practice, Landt et al. 2012). "
                               f"Check IP efficiency and antibody quality."
                })

        # --- ATAC-seq QC ---
        elif any(k in process_upper for k in ("ATAC_QC", "TSS_ENRICH", "ATAC_PEAK",
                                               "DEEPTOOLS_PLOTFINGERPRINT", "PLOTFINGERPRINT")):
            tss = qc_metrics.get("tss_enrichment")
            # source: ENCODE4 ATAC-seq standards: TSS enrichment ≥ 7 (high quality), ≥ 5 (acceptable)
            if tss is not None:
                if tss < 5.0:
                    failures.append({
                        "metric": "tss_enrichment",
                        "value": tss,
                        "threshold": 5.0,
                        "operator": "<",
                        "severity": "critical" if tss < 3.0 else "warning",
                        "message": f"Low TSS enrichment: {tss:.1f} (threshold: 5.0, ideal: ≥ 7.0). "
                                   f"ENCODE4 requires ≥ 5 for acceptable ATAC-seq data. "
                                   f"Check nucleosome-free region filtering and library quality."
                    })
            frip = qc_metrics.get("frip_score")
            # source: ENCODE4 ATAC-seq — FRiP > 0.3 is ideal; > 0.2 is acceptable.
            # EN-TEx tissue samples are exempt from FRiP enforcement in ENCODE4.
            # We gate at 0.2 (the "acceptable" floor) and note 0.3 as the ideal.
            if frip is not None and frip < 0.2:
                failures.append({
                    "metric": "frip_score",
                    "value": frip,
                    "threshold": 0.2,
                    "operator": "<",
                    "message": f"Low ATAC-seq FRiP score: {frip:.4f} (threshold: 0.2 acceptable, 0.3 ideal per ENCODE4). "
                               f"Check peak calling parameters (shift/extsize) and sequencing depth."
                })
            nrf = qc_metrics.get("nrf_score")
            # source: ENCODE4: NRF ≥ 0.9 indicates good library complexity
            # (NRF = DistinctReadPairs / TotalReadPairs — distinct from PBC1)
            if nrf is not None and nrf < 0.9:
                failures.append({
                    "metric": "nrf_score",
                    "value": nrf,
                    "threshold": 0.9,
                    "operator": "<",
                    "severity": "critical" if nrf < 0.5 else "warning",
                    "message": f"Low library complexity (NRF/PBC1): {nrf:.3f} (threshold: 0.9). "
                               f"ENCODE4 requires ≥ 0.9. Indicates PCR over-amplification — "
                               f"reduce PCR cycles or increase input material."
                })

        # --- Metagenomics ---
        elif any(k in process_upper for k in ("KRAKEN2", "KRAKEN", "BRACKEN",
                                               "METAPHLAN", "KAIJU")):
            classified = qc_metrics.get("classified_pct")
            # source: Wood, Lu & Langmead (2019) Genome Biology 20:257 (Kraken2 paper);
            # QIIME2 community standards; environmental metagenomics practice.
            # Novel environments routinely classify 40-80% (database-dependent); < 30% is
            # critically low (possible contamination, wrong DB, or divergent organisms);
            # 30-60% warrants investigation.
            # Override keys: "classified_pct_critical" (default 30%) and
            # "classified_pct_warning" (default 60%) allow separate adjustment.
            _cls_crit_t = self._get_threshold("classified_pct_critical", 30.0)
            _cls_warn_t = self._get_threshold("classified_pct_warning", 60.0)
            if classified is not None:
                if classified < _cls_crit_t:
                    failures.append({
                        "metric": "classified_pct",
                        "value": classified,
                        "threshold": _cls_crit_t,
                        "operator": "<",
                        "severity": "critical",
                        "message": f"Critically low classification: {classified:.1f}% (threshold: {_cls_crit_t:.0f}%). "
                                   f"Possible contamination, wrong database, or highly divergent organisms. "
                                   f"Verify sample and database match before proceeding."
                    })
                elif classified < _cls_warn_t:
                    failures.append({
                        "metric": "classified_pct",
                        "value": classified,
                        "threshold": _cls_warn_t,
                        "operator": "<",
                        "severity": "warning",
                        "message": f"Low classification: {classified:.1f}% (threshold: {_cls_warn_t:.0f}%). "
                                   f"Consider upgrading to a larger Kraken2 database or adjusting "
                                   f"the confidence threshold."
                    })

        elif any(k in process_upper for k in ("MAXQUANT", "MAXQUANT_SEARCH",
                                               "MAXQUANT_ANDROMEDA")):
            # [GOLD] PSM FDR — Elias & Gygi 2007, Nature Methods (8,000+ citations)
            # Target-decoy approach: 1% FDR is universally accepted as the standard.
            psm_fdr = qc_metrics.get("psm_fdr_pct")
            _psm_fdr_t = self._get_threshold("psm_fdr_pct", 1.0)
            if psm_fdr is not None and psm_fdr > _psm_fdr_t:
                failures.append({
                    "metric": "psm_fdr_pct",
                    "value": psm_fdr,
                    "threshold": _psm_fdr_t,
                    "operator": ">",
                    "message": (
                        f"[GOLD] PSM FDR {psm_fdr:.2f}% exceeds 1% threshold (Elias & Gygi 2007). "
                        f"Check peptide search parameters: enzyme specificity, mass tolerances, "
                        f"and database size."
                    ),
                })

            # [GOLD] Protein FDR — same authority as PSM FDR
            protein_fdr = qc_metrics.get("protein_fdr_pct")
            _prot_fdr_t = self._get_threshold("protein_fdr_pct", 1.0)
            if protein_fdr is not None and protein_fdr > _prot_fdr_t:
                failures.append({
                    "metric": "protein_fdr_pct",
                    "value": protein_fdr,
                    "threshold": _prot_fdr_t,
                    "operator": ">",
                    "message": (
                        f"[GOLD] Protein FDR {protein_fdr:.2f}% exceeds 1% threshold (Elias & Gygi 2007). "
                        f"Re-examine search database composition and score cutoffs."
                    ),
                })

            # [SILVER] Missed cleavage rate — EuBIC 2018 proteomics QC community standards
            mc_pct = qc_metrics.get("missed_cleavage_pct")
            _mc_t = self._get_threshold("missed_cleavage_pct", 20.0)
            if mc_pct is not None and mc_pct > _mc_t:
                failures.append({
                    "metric": "missed_cleavage_pct",
                    "value": mc_pct,
                    "threshold": _mc_t,
                    "operator": ">",
                    "message": (
                        f"[SILVER] Missed cleavage rate {mc_pct:.1f}% exceeds {_mc_t:.0f}% "
                        f"(EuBIC 2018 community standards). Check for incomplete digestion: "
                        f"increase trypsin concentration, extend digestion time, or verify "
                        f"sample denaturation."
                    ),
                })

            # [SILVER] CV across technical replicates — EuBIC 2018
            cv_pct = qc_metrics.get("cv_pct")
            _cv_t = self._get_threshold("cv_pct", 20.0)
            if cv_pct is not None and cv_pct > _cv_t:
                failures.append({
                    "metric": "cv_pct",
                    "value": cv_pct,
                    "threshold": _cv_t,
                    "operator": ">",
                    "message": (
                        f"[SILVER] Median CV {cv_pct:.1f}% exceeds {_cv_t:.0f}% "
                        f"(EuBIC 2018 community standards). Check for sample preparation "
                        f"variability, LC column degradation, or instrument instability."
                    ),
                })

            # [SILVER] Phosphosite localization score — Beausoleil et al. 2006, Nature Biotechnology
            # Only fires if localization data is present (i.e., phospho enrichment experiment)
            loc_score = qc_metrics.get("phosphosite_localization_score")
            _loc_t = self._get_threshold("phosphosite_localization_score", 0.75)
            if loc_score is not None and loc_score < _loc_t:
                failures.append({
                    "metric": "phosphosite_localization_score",
                    "value": loc_score,
                    "threshold": _loc_t,
                    "operator": "<",
                    "message": (
                        f"[SILVER] Median phosphosite localization score {loc_score:.3f} "
                        f"below 0.75 (Beausoleil et al. 2006, Nat Biotechnology). "
                        f"Consider improving phosphopeptide enrichment efficiency or "
                        f"extending gradient length for better fragmentation."
                    ),
                })

            # [BRONZE] PSM count — minimum for meaningful protein identification
            psm_count = qc_metrics.get("psm_count")
            _psm_t = self._get_threshold("psm_count", 1000)
            if psm_count is not None and psm_count < _psm_t:
                failures.append({
                    "metric": "psm_count",
                    "value": psm_count,
                    "threshold": _psm_t,
                    "operator": "<",
                    "advisory": True,
                    "message": (
                        f"[BRONZE] PSM count {psm_count} is low (advisory: ≥ {_psm_t:.0f} for "
                        f"standard cell lysate). This may be expected for phospho-enriched or "
                        f"pulldown samples. Check loading amount and spray stability."
                    ),
                })

        elif any(k in process_upper for k in ("DIANN", "DIANN_CONVERT", "SPECTRONAUT",
                                               "DIANN_SEARCH")):
            # DIA-NN / Spectronaut DIA proteomics gates
            # [GOLD] Protein FDR — same standard as MaxQuant (universal proteomics consensus)
            protein_fdr = qc_metrics.get("protein_fdr_pct")
            _prot_fdr_t = self._get_threshold("protein_fdr_pct", 1.0)
            if protein_fdr is not None and protein_fdr > _prot_fdr_t:
                failures.append({
                    "metric": "protein_fdr_pct",
                    "value": protein_fdr,
                    "threshold": _prot_fdr_t,
                    "operator": ">",
                    "message": (
                        f"[GOLD] Protein FDR {protein_fdr:.2f}% exceeds 1% threshold. "
                        f"Verify spectral library specificity and DIA-NN confidence settings."
                    ),
                })

            # [SILVER] CV across replicates — DIA community standards (Stenbratt et al. 2021)
            cv_pct = qc_metrics.get("cv_pct")
            _cv_t = self._get_threshold("cv_pct", 15.0)  # DIA typically achieves < 15%
            if cv_pct is not None and cv_pct > _cv_t:
                failures.append({
                    "metric": "cv_pct",
                    "value": cv_pct,
                    "threshold": _cv_t,
                    "operator": ">",
                    "message": (
                        f"[SILVER] Median CV {cv_pct:.1f}% exceeds {_cv_t:.0f}% "
                        f"(DIA community standards; Stenbratt et al. 2021). "
                        f"Check chromatographic reproducibility and spectral library quality."
                    ),
                })

            # [SILVER] Missing value fraction — applied when profile sets explicit threshold
            missing_pct = qc_metrics.get("missing_value_pct")
            _miss_t = self._get_threshold("missing_value_pct", None)
            if missing_pct is not None and _miss_t is not None and missing_pct > _miss_t:
                failures.append({
                    "metric": "missing_value_pct",
                    "value": missing_pct,
                    "threshold": _miss_t,
                    "operator": ">",
                    "message": (
                        f"[SILVER] Missing value fraction {missing_pct:.1f}% exceeds {_miss_t:.0f}% "
                        f"(plasma biomarker profile). Increase sample loading or "
                        f"reduce the stringency of the missing value filter."
                    ),
                })

        elif any(k in process_upper for k in ("PULLDOWN_QC", "CHEMOPROTEOMICS_QC",
                                               "ENRICHMENT_QC", "PULLDOWN_ANALYSIS",
                                               "CHEMOPROTEOMICS_PULLDOWN", "ABPP_PULLDOWN",
                                               "ABPP", "PULLDOWN")):
            # [SILVER] Enrichment ratio gate — prey/input > 3× (ABPP community practice).
            # A pulldown failing this gate means the bead coupling failed or the drug loading
            # was insufficient; downstream protein list will be dominated by matrix contaminants.
            enrichment_ratio = qc_metrics.get("median_enrichment_ratio")
            _enr_t = self._get_threshold("median_enrichment_ratio", 3.0)
            if enrichment_ratio is not None and enrichment_ratio < _enr_t:
                failures.append({
                    "metric": "median_enrichment_ratio",
                    "value": enrichment_ratio,
                    "threshold": _enr_t,
                    "operator": "<",
                    "message": (
                        f"[SILVER] Pulldown enrichment ratio {enrichment_ratio:.2f}× "
                        f"below threshold {_enr_t:.0f}× (ABPP community practice). "
                        f"Check bead coupling efficiency, drug loading concentration, "
                        f"and input proteome quality. Results will contain predominantly "
                        f"non-specific matrix binders."
                    ),
                })

            # [SILVER] Minimum prey protein count — too few proteins suggests failed pulldown
            prey_count = qc_metrics.get("prey_protein_count")
            _prey_t = self._get_threshold("prey_protein_count", 50)
            if prey_count is not None and prey_count < _prey_t:
                failures.append({
                    "metric": "prey_protein_count",
                    "value": prey_count,
                    "threshold": _prey_t,
                    "operator": "<",
                    "advisory": True,
                    "message": (
                        f"[SILVER] Only {prey_count} proteins above enrichment threshold "
                        f"(advisory: ≥ {_prey_t:.0f}). Low prey count may indicate failed "
                        f"pulldown or very specific interaction. Review manually before "
                        f"committing to wet-lab follow-up."
                    ),
                })

            # [advisory] CRAPome contamination fraction — fraction of prey proteins that are
            # known common mass-spec contaminants (high = pulldown failed)
            crapome_frac = qc_metrics.get("crapome_contamination_fraction")
            _crap_t = self._get_threshold("crapome_contamination_fraction", 0.5)
            if crapome_frac is not None and crapome_frac > _crap_t:
                failures.append({
                    "metric": "crapome_contamination_fraction",
                    "value": crapome_frac,
                    "threshold": _crap_t,
                    "operator": ">",
                    "advisory": True,
                    "message": (
                        f"[ADVISORY] {crapome_frac:.1%} of prey proteins are known CRAPome "
                        f"contaminants (threshold: {_crap_t:.0%}). "
                        f"High contaminant fraction strongly suggests non-specific binding. "
                        f"Cross-reference hits against CRAPome (crapome.org) before "
                        f"prioritising for wet-lab validation."
                    ),
                })

        elif any(k in process_upper for k in ("SMILES_QC", "COMPOUND_QC", "STRUCTURE_QC",
                                               "ADMET_PRECHECK", "DOCKING_PRECHECK")):
            # [GOLD] SMILES parseable — hard gate before any ADMET/docking computation.
            # An unparseable SMILES produces undefined predictions that propagate silently.
            invalid_count = qc_metrics.get("invalid_smiles_count", 0)
            total_count = qc_metrics.get("total_compounds", 1)
            if invalid_count > 0:
                invalid_pct = (invalid_count / max(total_count, 1)) * 100.0
                failures.append({
                    "metric": "invalid_smiles_count",
                    "value": invalid_count,
                    "threshold": 0,
                    "operator": ">",
                    "message": (
                        f"[GOLD] {invalid_count} compound(s) ({invalid_pct:.1f}%) have "
                        f"unparseable SMILES (RDKit sanitize failed). These will produce "
                        f"undefined ADMET/docking predictions. Fix or exclude before "
                        f"downstream computation."
                    ),
                })

            # [SILVER] Salt form — multi-fragment SMILES may bias MW and ADMET predictions
            salt_count = qc_metrics.get("salt_form_count", 0)
            if salt_count > 0:
                salt_pct = (salt_count / max(total_count, 1)) * 100.0
                failures.append({
                    "metric": "salt_form_count",
                    "value": salt_count,
                    "threshold": 0,
                    "operator": ">",
                    "advisory": True,
                    "message": (
                        f"[SILVER] {salt_count} compound(s) ({salt_pct:.1f}%) are in salt "
                        f"form (SMILES contains '.'). Salt stripping applied automatically. "
                        f"Verify that the largest fragment is the intended drug molecule."
                    ),
                })

            # [SILVER] Undefined stereocenters — may produce incorrect ADMET estimates
            undefined_stereo_count = qc_metrics.get("undefined_stereo_count", 0)
            if undefined_stereo_count > 0:
                stereo_pct = (undefined_stereo_count / max(total_count, 1)) * 100.0
                failures.append({
                    "metric": "undefined_stereo_count",
                    "value": undefined_stereo_count,
                    "threshold": 0,
                    "operator": ">",
                    "advisory": True,
                    "message": (
                        f"[SILVER] {undefined_stereo_count} compound(s) ({stereo_pct:.1f}%) "
                        f"have undefined stereocenters. ADMET predictions may differ "
                        f"significantly between enantiomers. Specify stereochemistry where known."
                    ),
                })

            # [BRONZE] MW outside drug-like space
            high_mw_count = qc_metrics.get("high_mw_count", 0)
            _mw_t = self._get_threshold("compound_mw_limit", 900.0)
            if high_mw_count > 0:
                high_mw_pct = (high_mw_count / max(total_count, 1)) * 100.0
                failures.append({
                    "metric": "high_mw_count",
                    "value": high_mw_count,
                    "threshold": int(_mw_t),
                    "operator": ">",
                    "advisory": True,
                    "message": (
                        f"[BRONZE] {high_mw_count} compound(s) ({high_mw_pct:.1f}%) have "
                        f"MW > {_mw_t:.0f} Da. Standard ADMET models are validated for "
                        f"drug-like molecules (< 900 Da). Predictions may be unreliable "
                        f"for large or macrocyclic compounds."
                    ),
                })

        elif any(k in process_upper for k in ("ADMET_TOXICITY", "HERG_SCREEN", "DILI_SCREEN",
                                               "TOXICITY_SCREEN", "ADMET_PRED",
                                               "PREDICT_ADMET", "ADMET_SAFETY")):
            # ── hERG cardiotoxicity ──────────────────────────────────────────
            # [GOLD] IC50 < 1 μM — high-risk hERG inhibition; QT prolongation + TdP risk.
            # Source: Sanguinetti & Tristani-Firouzi (2006) Nature 440:463
            # FDA Guidance for Industry: E14 Clinical Evaluation of QT/QTc Interval (2005)
            herg_ic50 = qc_metrics.get("herg_ic50_uM")
            if herg_ic50 is not None:
                _herg_gold_t = self._get_threshold("herg_ic50_high_risk_uM", 1.0)
                _herg_silver_t = self._get_threshold("herg_ic50_medium_risk_uM", 10.0)
                if herg_ic50 < _herg_gold_t:
                    failures.append({
                        "metric": "herg_ic50_uM",
                        "value": round(herg_ic50, 3),
                        "threshold": _herg_gold_t,
                        "operator": "<",
                        "message": (
                            f"[GOLD] hERG IC50 {herg_ic50:.3f} μM is below the high-risk "
                            f"threshold of {_herg_gold_t:.1f} μM (Sanguinetti & Tristani-Firouzi "
                            f"2006; FDA E14 guidance). High-risk hERG inhibition predicts QT "
                            f"interval prolongation and risk of Torsade de Pointes (TdP). "
                            f"Structural optimisation to reduce hERG liability is required "
                            f"before progression."
                        ),
                    })
                elif herg_ic50 < _herg_silver_t:
                    failures.append({
                        "metric": "herg_ic50_uM",
                        "value": round(herg_ic50, 3),
                        "threshold": _herg_silver_t,
                        "operator": "<",
                        "advisory": True,
                        "message": (
                            f"[SILVER] hERG IC50 {herg_ic50:.3f} μM is in the medium-risk "
                            f"range (1–{_herg_silver_t:.0f} μM). Monitor QT interval in "
                            f"preclinical cardiac safety assays (IonWorks / manual patch clamp). "
                            f"Document in IND safety package."
                        ),
                    })

            # Also accept hERG inhibition probability from ML models
            herg_prob = qc_metrics.get("herg_inhibition_prob")
            if herg_prob is not None and herg_ic50 is None:
                _herg_prob_t = self._get_threshold("herg_inhibition_prob_threshold", 0.9)
                if herg_prob >= _herg_prob_t:
                    failures.append({
                        "metric": "herg_inhibition_prob",
                        "value": round(herg_prob, 3),
                        "threshold": _herg_prob_t,
                        "operator": ">=",
                        "message": (
                            f"[GOLD] hERG inhibition probability {herg_prob:.3f} ≥ "
                            f"{_herg_prob_t:.1f} (high-confidence prediction). "
                            f"Follow up with experimental IC50 measurement before IND filing."
                        ),
                    })

            # ── DILI (drug-induced liver injury) ────────────────────────────
            # [GOLD] "Most-DILI-Concern" — FDA DILIrank database (Chen et al. 2016,
            # Drug Metabolism and Disposition 44:1717)
            dili_risk = qc_metrics.get("dili_risk", "").lower()
            dili_prob = qc_metrics.get("dili_probability")
            _dili_prob_t = self._get_threshold("dili_probability_threshold", 0.7)
            if dili_risk == "high" or (dili_prob is not None and dili_prob >= 0.8):
                failures.append({
                    "metric": "dili_risk",
                    "value": dili_risk or f"{dili_prob:.2f}",
                    "threshold": "low",
                    "operator": "!=",
                    "message": (
                        f"[GOLD] DILI risk classified as '{dili_risk or 'high-probability'}' "
                        f"(DILIrank; Chen et al. 2016). Drug-induced liver injury is the "
                        f"leading cause of post-market drug withdrawal (Onakpoya et al. 2016). "
                        f"Hepatotoxicity investigation (ALT/AST panel, hepatocyte assay) is "
                        f"required before clinical progression."
                    ),
                })
            elif dili_risk == "medium" or (
                dili_prob is not None and _dili_prob_t <= dili_prob < 0.8
            ):
                failures.append({
                    "metric": "dili_risk",
                    "value": dili_risk or f"{dili_prob:.2f}",
                    "threshold": "low",
                    "operator": "!=",
                    "advisory": True,
                    "message": (
                        f"[SILVER] DILI risk classified as '{dili_risk or 'medium-probability'}'. "
                        f"Includes 'Less-DILI-Concern' compounds in DILIrank. "
                        f"Include hepatotoxicity monitoring in preclinical and Phase I design."
                    ),
                })

            # ── Ames mutagenicity ────────────────────────────────────────────
            # [SILVER] Positive Ames prediction — ICH S2(R1) guideline requires Ames test
            # for all new drug substances before first-in-human dosing.
            ames_positive = qc_metrics.get("ames_positive")
            ames_prob = qc_metrics.get("ames_probability")
            _ames_prob_t = self._get_threshold("ames_probability_threshold", 0.7)
            if ames_positive or (ames_prob is not None and ames_prob >= _ames_prob_t):
                failures.append({
                    "metric": "ames_positive",
                    "value": ames_prob if ames_prob is not None else int(bool(ames_positive)),
                    "threshold": _ames_prob_t,
                    "operator": ">=",
                    "advisory": True,
                    "message": (
                        f"[SILVER] Ames mutagenicity predicted positive "
                        f"(probability: {ames_prob:.2f}). "
                        f"ICH S2(R1) requires experimental Ames assay (TA98, TA100, TA1535, "
                        f"TA1537 ± S9 activation) before IND filing. "
                        f"Genotoxic compounds require additional in vivo follow-up."
                    ),
                })

            # ── Clinical toxicity (ClinTox) ──────────────────────────────────
            # [SILVER] ClinTox > 0.8 — DeepPurpose ClinTox model trained on FDA clinical
            # trial failures due to toxicity (Wu et al. 2018, Mol Pharm 15:2362)
            clintox = qc_metrics.get("clintox_probability")
            _clintox_t = self._get_threshold("clintox_probability_threshold", 0.8)
            if clintox is not None and clintox >= _clintox_t:
                failures.append({
                    "metric": "clintox_probability",
                    "value": round(clintox, 3),
                    "threshold": _clintox_t,
                    "operator": ">=",
                    "advisory": True,
                    "message": (
                        f"[SILVER] ClinTox clinical toxicity probability {clintox:.2f} ≥ "
                        f"{_clintox_t:.1f} (Wu et al. 2018, Mol Pharm). High probability "
                        f"of clinical trial failure due to toxicity. Review all available "
                        f"safety data before IND submission."
                    ),
                })

        elif any(k in process_upper for k in ("PGX_COVERAGE", "CYP_COVERAGE",
                                               "PHARMACOGENOMICS_QC", "PGX_QC")):
            # ── PGx CYP gene coverage ────────────────────────────────────────
            # [GOLD] < 30× on any CPIC Tier 1 gene — CPIC guideline minimum for reliable
            # star allele assignment. GC bias causes CYP2D6 to fall below 30× even in
            # 30× WGS libraries. Source: cpicpgx.org
            genes_below = qc_metrics.get("pgx_genes_below_threshold", [])
            min_cov = qc_metrics.get("min_pgx_coverage", 0.0)
            _pgx_t = self._get_threshold("pgx_min_coverage", 30)
            if genes_below:
                failures.append({
                    "metric": "pgx_genes_below_threshold",
                    "value": min_cov,
                    "threshold": _pgx_t,
                    "operator": "<",
                    "message": (
                        f"[GOLD] {len(genes_below)} PGx gene(s) below {_pgx_t}× coverage: "
                        f"{', '.join(sorted(genes_below))}. "
                        f"Coverage < {_pgx_t}× produces unreliable diplotype calls and "
                        f"CPIC-grade dosing recommendations cannot be issued "
                        f"(cpicpgx.org Tier 1 standards). "
                        f"Check for GC-bias in library prep (CYP2D6 is particularly affected). "
                        f"Consider local coverage re-sequencing of PGx loci."
                    ),
                })

            # Near-threshold warning: 30–36× (within 20% of threshold)
            _near_pgx_t = _pgx_t * 1.2
            near_threshold_genes = [
                g for g, cov in qc_metrics.items()
                if g in {"CYP2D6", "CYP2C19", "CYP3A4", "CYP3A5", "CYP2C9", "CYP1A2",
                         "DPYD", "TPMT", "NUDT15", "SLCO1B1", "UGT1A1", "VKORC1"}
                and isinstance(cov, (int, float))
                and _pgx_t <= cov < _near_pgx_t
                and g not in genes_below
            ]
            if near_threshold_genes:
                failures.append({
                    "metric": "pgx_near_threshold_genes",
                    "value": min(qc_metrics.get(g, _pgx_t) for g in near_threshold_genes),
                    "threshold": _near_pgx_t,
                    "operator": "<",
                    "advisory": True,
                    "message": (
                        f"[ADVISORY] {len(near_threshold_genes)} PGx gene(s) marginally above "
                        f"{_pgx_t}× threshold (within 20%): "
                        f"{', '.join(sorted(near_threshold_genes))}. "
                        f"CPIC calls are valid but fragile; flag as provisional in reports."
                    ),
                })

        elif any(k in process_upper for k in ("PK_SIM", "PKSIM", "PBPK_SIMULATION",
                                               "PBPK_SIM", "NCA_ANALYSIS",
                                               "PK_REPORT", "GENERATE_PK_REPORT")):
            # ── PBPK simulation QC ──────────────────────────────────────────────
            # [GOLD] No terminal elimination phase — Tmax at end of simulation
            # indicates CL is zero or near-zero; the model is accumulating without
            # any elimination. Willmann et al. J Med Chem 2003; EMA guideline on
            # PBPK modelling (EMA/CHMP/900052/2019).
            tmax_frac = qc_metrics.get("pbpk_tmax_fraction")
            _tmax_frac_t = self._get_threshold("pbpk_tmax_fraction_max", 0.80)
            sim_end = qc_metrics.get("pbpk_simulation_end_h", 0)
            tmax_h = qc_metrics.get("Tmax_h")
            if tmax_frac is not None and tmax_frac > _tmax_frac_t:
                failures.append({
                    "metric": "pbpk_tmax_fraction",
                    "value": round(tmax_frac, 3),
                    "threshold": _tmax_frac_t,
                    "operator": ">",
                    "message": (
                        f"[GOLD] Tmax ({tmax_h:.1f}h) occurs at {tmax_frac*100:.0f}% of the "
                        f"simulation window ({sim_end:.0f}h) — no absorption peak followed by "
                        f"elimination was observed. The PBPK model is missing hepatic or renal "
                        f"clearance. Check CLint_microsomal, fu_p, and MW inputs. "
                        f"Reference: EMA PBPK Guideline EMA/CHMP/900052/2019."
                    ),
                })

            # [GOLD] No terminal decline in concentration profile
            if qc_metrics.get("pbpk_monotonic") is False:
                failures.append({
                    "metric": "pbpk_monotonic",
                    "value": "no_decline",
                    "threshold": "terminal_decline_required",
                    "operator": "==",
                    "message": (
                        "[GOLD] Blood concentration profile shows no terminal decline phase. "
                        "A valid PBPK profile must show absorption (rising Cblood), distribution, "
                        "and elimination (declining Cblood). Missing elimination indicates zero "
                        "or near-zero clearance parameters — review CLint, fu_p, or hepatic "
                        "blood flow inputs."
                    ),
                })

            # [GOLD] Unrealistically low systemic clearance
            cl_lh = qc_metrics.get("CL_L_h")
            _cl_min_t = self._get_threshold("pbpk_cl_min_L_h", 0.01)
            if cl_lh is not None and cl_lh < _cl_min_t:
                failures.append({
                    "metric": "CL_L_h",
                    "value": round(cl_lh, 6),
                    "threshold": _cl_min_t,
                    "operator": "<",
                    "message": (
                        f"[GOLD] Systemic clearance CL = {cl_lh:.4f} L/h is below the minimum "
                        f"plausible value of {_cl_min_t} L/h for a small molecule. "
                        f"For comparison, midazolam CL ≈ 25 L/h (Davies 1993). "
                        f"Check CLint_microsomal and fu_p — if both are correct, the compound "
                        f"may have anomalously low hepatic extraction (e.g. BCS III/IV with "
                        f"high protein binding). Verify against in vitro clearance data."
                    ),
                })

            # [SILVER] Missing terminal half-life
            t_half = qc_metrics.get("t_half_h")
            if t_half is None:
                failures.append({
                    "metric": "t_half_h",
                    "value": None,
                    "threshold": "not_null",
                    "operator": "==",
                    "advisory": True,
                    "message": (
                        "[SILVER] Terminal half-life (t½) could not be estimated — the "
                        "concentration-time profile does not show a log-linear terminal phase. "
                        "This prevents AUCinf extrapolation and dosing interval calculations. "
                        "Extend the simulation window to ≥ 5 × expected t½ or check for "
                        "zero-clearance parameters. Reference: FDA Guidance on Pharmacokinetics 2018."
                    ),
                })

        elif any(k in process_upper for k in ("NCA_PKNCA", "NCA_ANALYSIS",
                                               "NONCOMPARTMENTAL", "PKNCA")):
            # ── Non-compartmental analysis (PKNCA) ─────────────────────────────
            # [SILVER] AUC extrapolation > 20% — Gabrielsson & Weiner 2006;
            # FDA Guidance on PK studies 2018: "extrapolated AUC should be < 20%
            # of AUCinf to consider the profile adequately characterised"
            auc_extrap = qc_metrics.get("auc_extrap_pct_max")
            # Modifier-aware: profile / phase / population can tighten or relax
            # the 20% FDA-default. See _MODIFIER_AWARE_METRICS + the YAML
            # `modifiers` block for nca_auc_extrap. Defaults to 20.0 when no
            # context applies (legacy behavior preserved).
            _extrap_t = self._get_threshold_with_context(
                "auc_extrap_pct_max",
                self._get_threshold("auc_extrap_pct_max", 20.0),
                context=self._build_modifier_context(),
            )
            if auc_extrap is not None and auc_extrap > _extrap_t:
                failures.append({
                    "metric": "auc_extrap_pct_max",
                    "value": round(auc_extrap, 1),
                    "threshold": _extrap_t,
                    "operator": ">",
                    "advisory": True,
                    "message": (
                        f"[SILVER] Maximum AUC extrapolation {auc_extrap:.1f}% exceeds "
                        f"{_extrap_t:.0f}% (FDA PK Guidance 2018). Terminal half-life is poorly "
                        f"characterised — the concentration-time profile was not sampled long "
                        f"enough to capture ≥ 80% of AUCinf. Extend sampling to ≥ 3 half-lives "
                        f"or report AUClast without AUCinf extrapolation."
                    ),
                })

            # [BRONZE] Subjects with no estimable terminal slope
            no_slope = qc_metrics.get("subjects_with_no_terminal_slope", 0)
            n_subj = qc_metrics.get("n_subjects", 1)
            _no_slope_frac_t = self._get_threshold("nca_no_slope_fraction", 0.3)
            if no_slope and n_subj and (no_slope / max(n_subj, 1)) > _no_slope_frac_t:
                failures.append({
                    "metric": "subjects_with_no_terminal_slope",
                    "value": no_slope,
                    "threshold": int(n_subj * _no_slope_frac_t),
                    "operator": ">",
                    "advisory": True,
                    "message": (
                        f"[BRONZE] {no_slope}/{n_subj} subjects have no estimable terminal "
                        f"elimination slope (lambda_z). Half-life and AUCinf cannot be "
                        f"calculated for these subjects. Check that sampling extends through "
                        f"at least 3 half-lives and that ≥ 3 time points fall in the terminal "
                        f"log-linear phase."
                    ),
                })

        elif any(k in process_upper for k in ("PBPK_DISEASE_STATE", "DISEASE_STATE_PK",
                                               "RENAL_IMPAIRMENT_PBPK", "HEPATIC_IMPAIRMENT_PBPK")):
            # ── Disease-state PBPK — renal/hepatic impairment dosing ────────────
            # Thresholds derived from FDA Guidance on PK in Renal Impairment (2010) and
            # FDA Guidance on PK in Hepatic Impairment (2003).
            # FDA defines: AUC_ratio > 2.0 = "substantial increase" → dose adjustment labelling;
            #              AUC_ratio > 5.0 = use is contraindicated.
            # Validated against 6 drug-impairment pairs (10.6% MAE; all within ±35%):
            # Gabapentin, Metformin, Atenolol (renal); Midazolam, Lorazepam, Theophylline (hepatic).
            # Benchmark: docs/20260429_PHARMACOLOGY_BENCHMARK_RESULTS.md, Test 1.

            if qc_metrics.get("ds_contraindicated"):
                ci_auc = qc_metrics.get("ds_max_auc_ratio", "unknown")
                failures.append({
                    "metric": "ds_contraindicated",
                    "value": True,
                    "threshold": False,
                    "operator": "==",
                    "message": (
                        f"[GOLD] Simulated AUC_ratio = {ci_auc}× in the impaired population "
                        f"exceeds 5× — use is contraindicated in this impairment grade per "
                        f"FDA Guidance on Pharmacokinetics in Patients with Impaired Renal "
                        f"Function (2010, §IV.A) and FDA Guidance on Hepatic Impairment (2003). "
                        f"Label text must state CONTRAINDICATED. Review dose rationale or "
                        f"consider restricting indication. "
                        f"Ref: FDA 2010/2003 impairment guidance; ICH E7 (1993)."
                    ),
                })

            elif qc_metrics.get("ds_dose_adjustment_needed"):
                auc = qc_metrics.get("ds_max_auc_ratio", "unknown")
                failures.append({
                    "metric": "ds_dose_adjustment_needed",
                    "value": auc,
                    "threshold": 2.0,
                    "operator": ">",
                    "advisory": True,
                    "message": (
                        f"[SILVER] AUC_ratio = {auc}× exceeds 2× in the impaired population — "
                        f"FDA defines this as a 'substantial increase in exposure' requiring a "
                        f"dose adjustment recommendation in the prescribing label (§12.3, "
                        f"Special Populations). Dose fraction recommendation has been computed; "
                        f"verify with clinical PK data before labelling. "
                        f"Ref: FDA Guidance Renal Impairment (2010) Table 2; FDA Hepatic "
                        f"Impairment Guidance (2003) §III.B; Nolin 2010 Adv Chronic Kidney Dis."
                    ),
                })

        elif any(k in process_upper for k in ("BIOMARKER_PATIENT_ENRICHMENT",
                                               "PREDICTIVE_ENRICHMENT", "BIOMARKER_ENRICHMENT")):
            # ── Biomarker patient enrichment — predictive enrichment QC ─────────
            # Thresholds from FDA Enrichment Strategies Guidance (2019) and validated
            # against BRIM-3 (Chapman NEJM 2011): BRAF V600E → ER=33.2× recovered,
            # 77.8% Phase III size reduction, 0 false positives on noise biomarkers.
            # Benchmark: docs/20260429_PHARMACOLOGY_BENCHMARK_RESULTS.md, Test 2.
            # FDA (2019): "enrichment factor ≥ 2 is the minimum meaningful threshold
            # for a predictive enrichment design to justify the screening cost."
            # Sargent 2005 (JNCI): sensitivity ≥ 0.75 at optimal cut-point is
            # required for a clinically useful predictive biomarker.

            n_sig = qc_metrics.get("be_n_significant", 0)
            if n_sig == 0:
                failures.append({
                    "metric": "be_n_significant",
                    "value": 0,
                    "threshold": 1,
                    "operator": "<",
                    "advisory": True,
                    "message": (
                        "[SILVER] No biomarker reached significance (FDR q < 0.05). "
                        "The dataset contains no detectable predictive signal at this "
                        "sample size. Either the true enrichment ratio is below 2× "
                        "(FDA 2019 minimum meaningful threshold), or sample size is "
                        "insufficient to detect the signal (underpowered). "
                        "Do not proceed to biomarker-enriched Phase III without confirmatory "
                        "data. "
                        "Ref: FDA Enrichment Strategies Guidance (2019); "
                        "Sargent 2005 JNCI 97:1209."
                    ),
                })
            else:
                er_max = qc_metrics.get("be_max_enrichment_ratio")
                _er_min = self._get_threshold("be_min_enrichment_ratio", 2.0)
                if er_max is not None and er_max < _er_min:
                    failures.append({
                        "metric": "be_max_enrichment_ratio",
                        "value": round(er_max, 2),
                        "threshold": _er_min,
                        "operator": "<",
                        "advisory": True,
                        "message": (
                            f"[SILVER] Maximum enrichment ratio ER = {er_max:.2f}× is below "
                            f"the {_er_min:.1f}× minimum threshold (FDA 2019 Enrichment "
                            f"Strategies Guidance). At ER < 2×, the gain from biomarker "
                            f"enrichment does not justify the additional screening cost and "
                            f"may reduce generalisability of study results. "
                            f"BRIM-3 (Chapman NEJM 2011): BRAF V600E → ER > 12×. "
                            f"Ref: FDA 2019 §III.A; Simon 2010 Cancer Biomarkers 8:1."
                        ),
                    })

                min_sens = qc_metrics.get("be_min_bc_sensitivity")
                _sens_min = self._get_threshold("be_min_bc_sensitivity", 0.75)
                if min_sens is not None and min_sens < _sens_min:
                    failures.append({
                        "metric": "be_min_bc_sensitivity",
                        "value": round(min_sens, 3),
                        "threshold": _sens_min,
                        "operator": "<",
                        "advisory": True,
                        "message": (
                            f"[SILVER] Bias-corrected sensitivity at optimal cut-point = "
                            f"{min_sens:.3f} < {_sens_min:.2f}. A sensitivity below 0.75 "
                            f"means > 25% of true responders would be excluded from the "
                            f"enriched trial — significantly reducing the benefit of "
                            f"enrichment. The cut-point may be over-fitting to the discovery "
                            f"cohort; validate in an independent cohort. "
                            f"Ref: Sargent 2005 JNCI 97:1209; "
                            f"Youden 1950 Cancer 3:32 (J-statistic)."
                        ),
                    })

        elif any(k in process_upper for k in ("POLYMORPH_STABILITY_SCREENING",
                                               "POLYMORPH_SCREENING", "CRYSTAL_FORM_SCREEN",
                                               "SOLID_STATE_SCREEN")):
            # ── Polymorph stability screening — solid-state QC ─────────────────
            # Thresholds from ICH Q6A (1999) §3.1.1.5 and Fleming 2010 heuristic.
            # Validated against CSD polymorph counts: Ritonavir 9.5/10 HIGH (historic
            # $250M recall); Sulfathiazole/Carbamazepine MEDIUM; Aspirin/Caffeine/
            # Ibuprofen ≤4.0 (no false negatives on CMC-crisis compounds).
            # Benchmark: docs/20260429_PHARMACOLOGY_BENCHMARK_RESULTS.md, Test 3.
            # ICH Q6A §3.1.1.5: "If polymorphism is shown to affect drug performance,
            # acceptance criteria should be established." HIGH-risk compounds require
            # XRPD and DSC characterisation before IND submission.

            if qc_metrics.get("ps_xrpd_required"):
                score = qc_metrics.get("ps_risk_score", "unknown")
                failures.append({
                    "metric": "ps_xrpd_required",
                    "value": True,
                    "threshold": False,
                    "operator": "==",
                    "message": (
                        f"[GOLD] Polymorph risk score = {score}/10 → HIGH tier. "
                        f"ICH Q6A §3.1.1.5 requires XRPD and DSC characterisation for "
                        f"high-polymorph-risk drug substances before IND/NDA submission. "
                        f"A high score indicates ≥ 5 H-bond capacity, MW > 400 Da, or "
                        f"≥ 12 rotatable bonds — features associated with ritonavir "
                        f"(Form II CMC crisis, 1998) and carbamazepine (5 known forms). "
                        f"CRITICAL: An undetected polymorph transformation in the final "
                        f"drug product can alter dissolution, bioavailability, and shelf-life. "
                        f"Ref: ICH Q6A (1999) §3.1.1.5; Fleming 2010 Org Process Res Dev "
                        f"14:975; Blagden & Davey 2003 Chem Soc Rev 32:495."
                    ),
                })

            if qc_metrics.get("ps_hygroscopic"):
                failures.append({
                    "metric": "ps_hygroscopic",
                    "value": True,
                    "threshold": False,
                    "operator": "==",
                    "advisory": True,
                    "message": (
                        "[SILVER] HIGH hygroscopicity risk (TPSA > 100 Å² or ≥ 5 H-bond "
                        "groups). Moisture uptake may promote hydrate formation (altering "
                        "dissolution rate) or accelerate hydrolytic degradation. "
                        "ICH Q1A(R2) recommends controlled-humidity accelerated stability "
                        "conditions (40°C/75% RH). Storage specification ≤ 60% RH should "
                        "be considered. "
                        "Ref: ICH Q1A(R2) (2003); ICH Q6A Table 2; "
                        "Brittain 2009 Polymorphism in Pharmaceutical Solids §4."
                    ),
                })

            if qc_metrics.get("ps_photostability") == "HIGH":
                failures.append({
                    "metric": "ps_photostability",
                    "value": "HIGH",
                    "threshold": "LOW",
                    "operator": "==",
                    "advisory": True,
                    "message": (
                        "[SILVER] HIGH photostability risk (UV-active chromophore detected). "
                        "ICH Q1B Option 1 photostability study is required before NDA submission. "
                        "UV-active aromatic or conjugated carbonyl groups can undergo "
                        "photo-oxidation or photo-rearrangement, affecting potency and "
                        "generating toxic degradants. "
                        "Ref: ICH Q1B (1996); ICH Q6A §3.1.1.5 Table 2."
                    ),
                })

        elif any(k in process_upper for k in ("NLMIXR2", "POPULATION_PK",
                                               "POP_PK", "POPPK", "POPK")):
            # ── Population pharmacokinetics (nlmixr2) ──────────────────────────
            # [GOLD] Non-convergence — Karlsson & Sheiner 1993; FDA Pop PK Guidance 2019:
            # "a model that did not converge should not be used for labelling"
            convergence = qc_metrics.get("convergence_status")
            if convergence and convergence != "converged":
                failures.append({
                    "metric": "convergence_status",
                    "value": convergence,
                    "threshold": "converged",
                    "operator": "!=",
                    "message": (
                        f"[GOLD] Population PK model did not converge "
                        f"(status: {convergence}). A non-converged model cannot be used "
                        f"for dosing recommendations or regulatory submissions "
                        f"(FDA Pop PK Guidance 2019). "
                        f"Try simplifying the model (1-compartment before 2-compartment), "
                        f"increasing iterations, or checking for data outliers."
                    ),
                })

            # [SILVER] ETA shrinkage > 30% — Savic & Karlsson 2009 CPT:PSP:
            # "shrinkage > 30% renders individual estimates unreliable for EBE-based diagnostics"
            shrinkage = qc_metrics.get("max_eta_shrinkage_pct")
            _shrinkage_t = self._get_threshold("max_eta_shrinkage_pct", 30.0)
            if shrinkage is not None and shrinkage > _shrinkage_t:
                failures.append({
                    "metric": "max_eta_shrinkage_pct",
                    "value": round(shrinkage, 1),
                    "threshold": _shrinkage_t,
                    "operator": ">",
                    "advisory": True,
                    "message": (
                        f"[SILVER] ETA shrinkage {shrinkage:.1f}% exceeds {_shrinkage_t:.0f}% "
                        f"(Savic & Karlsson 2009 CPT:PSP). Individual Bayesian estimates (EBEs) "
                        f"are unreliable for individual-level diagnostics. "
                        f"Consider merging sparse occasions, collecting richer PK sampling, "
                        f"or simplifying the random effects structure."
                    ),
                })

            # [BRONZE] Condition number > 1000 — Beal & Sheiner 1992;
            # high condition number indicates near-collinear parameters
            cond_num = qc_metrics.get("condition_number")
            _cond_t = self._get_threshold("condition_number", 1000.0)
            if cond_num is not None and cond_num > _cond_t:
                failures.append({
                    "metric": "condition_number",
                    "value": round(cond_num, 1),
                    "threshold": _cond_t,
                    "operator": ">",
                    "advisory": True,
                    "message": (
                        f"[BRONZE] Covariance matrix condition number {cond_num:.0f} > "
                        f"{_cond_t:.0f}. High condition numbers indicate near-collinear "
                        f"parameters — the model may be over-parameterised for the available "
                        f"data. Consider fixing one clearance or volume parameter to a "
                        f"literature value, or reducing to a simpler structural model."
                    ),
                })

        elif any(k in process_upper for k in ("IVIVE", "HEPATIC_CLEARANCE",
                                               "IVIVE_HEPATIC", "CLEARANCE_SCALING")):
            # ── IVIVE hepatic clearance ─────────────────────────────────────────
            # [BRONZE] CLh approaching hepatic blood flow — Obach 2009 Drug Metab Dispos;
            # CLh > 90% of QH means the compound is a high-extraction drug;
            # predictions are most uncertain at the extremes (< 30% or > 90% QH)
            clh_frac = qc_metrics.get("clh_fraction_of_qh")
            _high_extraction_t = self._get_threshold("clh_fraction_of_qh_high", 0.90)
            _low_extraction_t = self._get_threshold("clh_fraction_of_qh_low", 0.30)
            clh_val = qc_metrics.get("clh_predicted_ml_min_kg")
            if clh_frac is not None and clh_frac > _high_extraction_t:
                failures.append({
                    "metric": "clh_fraction_of_qh",
                    "value": round(clh_frac, 3),
                    "threshold": _high_extraction_t,
                    "operator": ">",
                    "advisory": True,
                    "message": (
                        f"[BRONZE] Predicted hepatic clearance is {clh_frac*100:.0f}% of "
                        f"hepatic blood flow (CLh = {clh_val:.1f} mL/min/kg). "
                        f"High-extraction compounds (> 90% QH) are subject to high first-pass "
                        f"metabolism; IVIVE predictions are least reliable in this range "
                        f"(Obach 2009 Drug Metab Dispos). Confirm with portal-vein dosing "
                        f"data or a physiologically-based PK model."
                    ),
                })
            elif clh_frac is not None and clh_frac < _low_extraction_t:
                failures.append({
                    "metric": "clh_fraction_of_qh",
                    "value": round(clh_frac, 3),
                    "threshold": _low_extraction_t,
                    "operator": "<",
                    "advisory": True,
                    "message": (
                        f"[BRONZE] Predicted hepatic clearance is {clh_frac*100:.0f}% of "
                        f"hepatic blood flow (CLh = {clh_val:.1f} mL/min/kg). "
                        f"Low-extraction compounds are sensitive to plasma protein binding "
                        f"and intrinsic clearance variability. Verify fu_plasma and "
                        f"CLint_in_vitro inputs, as small measurement errors are amplified "
                        f"in this range."
                    ),
                })

        elif any(k in process_upper for k in ("MOLECULAR_DOCKING", "DOCKING",
                                               "AUTODOCK", "VINA", "GLIDE")):
            # [SILVER] Docking score threshold.
            # Trott & Olson 2010 J Comput Chem 31:455 — Vina scoring; community heuristic for hits.
            # ≤ −7 kcal/mol is a commonly used minimum for primary screening hits.
            score = qc_metrics.get("best_score_kcal_mol")
            _score_t = self._get_threshold("docking_score_kcal_mol", -7.0)
            if score is not None and score > _score_t:  # more negative = better; gate fires when too weak
                failures.append({
                    "metric": "best_score_kcal_mol",
                    "value": score,
                    "threshold": _score_t,
                    "operator": ">",
                    "message": (
                        f"[SILVER] Weak docking score: {score:.1f} kcal/mol "
                        f"(threshold: ≤ {_score_t:.0f} kcal/mol). "
                        f"Compound may not bind the target with sufficient affinity. "
                        f"Consider scaffold hopping, growing into polar sub-pockets, or "
                        f"verifying the binding site definition."
                    ),
                })

            # [BRONZE advisory] Insufficient pose count.
            n_poses = qc_metrics.get("n_poses_generated")
            if n_poses is not None and n_poses < 5:
                failures.append({
                    "metric": "n_poses_generated",
                    "value": n_poses,
                    "threshold": 5,
                    "operator": "<",
                    "advisory": True,
                    "message": (
                        f"[BRONZE] Only {n_poses} docking pose(s) generated (expected ≥ 5). "
                        f"Check for steric clashes in the binding site definition or "
                        f"invalid SMILES input."
                    ),
                })

            # [BRONZE advisory] High RMSD vs reference.
            rmsd = qc_metrics.get("top_pose_rmsd_angstrom")
            _rmsd_t = self._get_threshold("docking_rmsd_angstrom", 2.0)
            if rmsd is not None and rmsd > _rmsd_t:
                failures.append({
                    "metric": "top_pose_rmsd_angstrom",
                    "value": rmsd,
                    "threshold": _rmsd_t,
                    "operator": ">",
                    "advisory": True,
                    "message": (
                        f"[BRONZE] Top pose RMSD {rmsd:.2f} Å vs reference (threshold: < {_rmsd_t:.1f} Å). "
                        f"Pose may not reproduce the reference binding mode. "
                        f"Check grid box placement and receptor preparation."
                    ),
                })

        elif any(k in process_upper for k in ("QSAR_MODEL", "QSAR",
                                               "CHEMPROP", "DEEPCHEM")):
            # [SILVER] Cross-validated R² gate.
            # Golbraikh & Tropsha 2002 J Mol Graph Model 20:269 — R² < 0.5 = uninformative model.
            r2 = qc_metrics.get("cv_r2_score")
            _r2_t = self._get_threshold("qsar_cv_r2", 0.5)
            if r2 is not None and r2 < _r2_t:
                failures.append({
                    "metric": "cv_r2_score",
                    "value": r2,
                    "threshold": _r2_t,
                    "operator": "<",
                    "message": (
                        f"[SILVER] Low QSAR cross-validated R²: {r2:.3f} "
                        f"(threshold: ≥ {_r2_t:.1f}). "
                        f"Model explains less than 50% of variance — predictions are unreliable. "
                        f"Consider adding more compounds, additional descriptors, or switching to "
                        f"a graph neural network (ChemProp)."
                    ),
                })

            # [BRONZE advisory] Insufficient training set size.
            n_cpds = qc_metrics.get("n_compounds")
            _n_t = self._get_threshold("qsar_min_compounds", 50)
            if n_cpds is not None and n_cpds < _n_t:
                failures.append({
                    "metric": "n_compounds",
                    "value": n_cpds,
                    "threshold": _n_t,
                    "operator": "<",
                    "advisory": True,
                    "message": (
                        f"[BRONZE] QSAR model trained on {n_cpds} compounds (advised: ≥ {_n_t}). "
                        f"Small datasets produce high-variance models. "
                        f"Expand the assay data or apply Bayesian uncertainty quantification."
                    ),
                })

        # Advisory items (advisory=True) are informational only — they do not block the workflow.
        # qc_passed is determined solely by hard (non-advisory) failures.
        blocking_failures = [f for f in failures if not f.get("advisory", False)]
        return (len(blocking_failures) == 0, failures)

    def _emit_qc_gate_event(
        self,
        process_name: str,
        qc_metrics: Dict[str, Any],
        failures: list
    ):
        """
        Emit SSE event for QC gate trigger.
        Includes parameter suggestions if available.
        """
        # Generate parameter suggestions
        suggestions = []
        if self.parameter_suggester:
            try:
                suggestion_objects = self.parameter_suggester.suggest(
                    process_name=process_name,
                    qc_metrics=qc_metrics,
                    current_parameters=self.current_parameters,
                    failures=failures
                )
                # Convert to dict format for JSON serialization
                suggestions = [
                    {
                        "parameter": s.parameter,
                        "currentValue": s.current_value,
                        "suggestedValue": s.suggested_value,
                        "reason": s.reason,
                        "confidence": s.confidence,
                        "source": s.source,  # US-6.1: "rule" or "literature"
                    }
                    for s in suggestion_objects
                ]
                log.info(f"[QC Gate] Generated {len(suggestions)} parameter suggestions")
            except Exception as e:
                log.warning(f"[QC Gate] Failed to generate parameter suggestions: {e}")

        event_data = {
            "invocation_id": self.invocation_id,
            "process_name": process_name,
            "qc_metrics": qc_metrics,
            "failures": failures,
            "suggestions": suggestions,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "overrides_active": bool(self.qc_overrides),
            "active_overrides": dict(self.qc_overrides) if self.qc_overrides else {},
            "active_profile": self.active_profile,
        }

        # Audit log: record that a gate event fired under non-default thresholds
        if self.qc_overrides or self.active_profile:
            self._write_audit_log_entry("gate_triggered", {"process_name": process_name})

        # US-6.2: append to in-memory event log
        self.qc_event_log.append({
            "type": "gate",
            "process_name": process_name,
            "timestamp": event_data["timestamp"],
            "metrics": qc_metrics,
            "failures": failures,
            "suggestions": suggestions,
            "active_profile": self.active_profile,
        })

        try:
            self.sse_callback("qc_gate_triggered", event_data)
            log.info(f"[QC Gate] SSE event emitted for {process_name} with {len(suggestions)} suggestions")
        except Exception as e:
            log.error(f"[QC Gate] Failed to emit SSE event: {e}")

        # Friendly chat-progress line. A non-advisory failure means the gate
        # blocks the workflow and the user (or auto-loop) needs to adjust
        # parameters; otherwise it's an advisory warning.
        try:
            from galaxy.ai.workflow_ops.workflow_chat_narrator import emit as _narrator_emit
            blocking = [f for f in failures if not f.get("advisory", False)]
            primary = (blocking[0] if blocking else (failures[0] if failures else {}))
            metric = primary.get("metric") or "metric"
            value = primary.get("value")
            threshold = primary.get("threshold")
            kind = "workflow.qc_gate_blocked" if blocking else "workflow.qc_gate_warning"
            _narrator_emit(
                self.invocation_id,
                kind,
                technical={
                    "metric": metric,
                    "value": value,
                    "threshold": threshold,
                    "process_name": process_name,
                    "n_failures": len(failures),
                    "n_blocking": len(blocking),
                    "n_suggestions": len(suggestions),
                },
                sse_callback=self.sse_callback,
            )
        except Exception as e:
            log.debug("[QC Gate] narrator emit failed: %s", e)

    def _check_qc_warnings(
        self,
        process_name: str,
        qc_metrics: Dict[str, Any]
    ) -> list:
        """
        Check for metrics that are approaching (within 10% above) their threshold.
        Returns warning dicts with the same schema as failure dicts but severity='near_threshold'.
        These are advisory only — they do NOT gate the workflow.
        """
        warnings = []
        process_upper = process_name.upper()

        def _near_above(val, threshold, pct=0.10):
            """True if val is within pct% above threshold (just passed but close)."""
            return threshold <= val <= threshold * (1.0 + pct)

        if any(k in process_upper for k in ("STAR_ALIGN", "STAR_GENOME", "HISAT2_ALIGN",
                                             "HISAT2", "BOWTIE2_ALIGN", "BWA_MEM")):
            rate = qc_metrics.get("alignment_rate")
            if rate is None:
                rate = qc_metrics.get("uniquely_mapped_pct")
            _align_t = self._get_threshold("alignment_rate", 70.0)
            if rate is not None and _near_above(rate, _align_t):
                warnings.append({
                    "metric": "alignment_rate", "value": rate, "threshold": _align_t,
                    "operator": "<", "severity": "near_threshold",
                    "message": f"Alignment rate {rate:.1f}% is near the {_align_t:.0f}% threshold — monitor closely"
                })

        elif any(k in process_upper for k in ("FASTP", "TRIMGALORE", "TRIMMOMATIC", "BBDUK")):
            surviving = qc_metrics.get("reads_surviving_pct")
            _surv_t = self._get_threshold("reads_surviving_pct", 70.0)
            if surviving is not None and _near_above(surviving, _surv_t):
                warnings.append({
                    "metric": "reads_surviving_pct", "value": surviving, "threshold": _surv_t,
                    "operator": "<", "severity": "near_threshold",
                    "message": f"Read survival {surviving:.1f}% is near the {_surv_t:.0f}% threshold — monitor closely"
                })

        elif any(k in process_upper for k in ("SALMON_QUANT", "SALMON", "KALLISTO")):
            mapping = qc_metrics.get("mapping_rate")
            _map_t = self._get_threshold("mapping_rate", 50.0)
            if mapping is not None and _near_above(mapping, _map_t):
                warnings.append({
                    "metric": "mapping_rate", "value": mapping, "threshold": _map_t,
                    "operator": "<", "severity": "near_threshold",
                    "message": f"Mapping rate {mapping:.1f}% is near the {_map_t:.0f}% threshold — monitor closely"
                })

        elif any(k in process_upper for k in ("KRAKEN2", "KRAKEN", "BRACKEN",
                                               "METAPHLAN", "KAIJU")):
            classified = qc_metrics.get("classified_pct")
            _cls_warn_t = self._get_threshold("classified_pct_warning", 60.0)
            if classified is not None and _near_above(classified, _cls_warn_t):
                warnings.append({
                    "metric": "classified_pct", "value": classified, "threshold": _cls_warn_t,
                    "operator": "<", "severity": "near_threshold",
                    "message": f"Classification rate {classified:.1f}% is near the {_cls_warn_t:.0f}% threshold — monitor closely"
                })

        elif any(k in process_upper for k in ("CELLRANGER_COUNT", "CELLRANGER",
                                               "STARSOLO", "ALEVIN")):
            # Warn above mito_fraction_pct_warning (default 10%) but below the hard gate.
            # sc-best-practices.org recommends ≤ 10% for standard tissues (PBMC, blood).
            # Cardiac and muscle cells can exceed 20% naturally — context matters.
            # Override key: "mito_fraction_pct_warning" for the advisory level (default 10%).
            mito = qc_metrics.get("mito_fraction_pct")
            _mito_hard_t = self._get_threshold("mito_fraction_pct", 20.0)
            _mito_warn_t = self._get_threshold("mito_fraction_pct_warning", 10.0)
            if mito is not None and _mito_warn_t < mito <= _mito_hard_t:
                warnings.append({
                    "metric": "mito_fraction_pct", "value": mito, "threshold": _mito_hard_t,
                    "operator": ">", "severity": "near_threshold",
                    "message": f"Elevated mitochondrial fraction: {mito:.1f}% "
                               f"(advisory: {_mito_warn_t:.0f}% for standard tissues). "
                               f"sc-best-practices recommends ≤ 10% for PBMC/blood; cardiac/muscle cells may "
                               f"naturally exceed this. Hard gate triggers at > {_mito_hard_t:.0f}%."
                })

        return warnings

    # ------------------------------------------------------------------
    # US-6.2: QC event log + structured report
    # ------------------------------------------------------------------

    def get_qc_report(self) -> Dict[str, Any]:
        """
        Return a structured QC summary for this invocation.

        Returned dict:
          invocation_id: str
          active_profile: str | None
          active_overrides: dict
          gates_triggered: int          — blocking gate events
          warnings_emitted: int         — near-threshold warning events
          events: list[dict]            — all events in chronological order
          methods_text: str             — human-readable paragraph for methods sections
        """
        gate_events = [e for e in self.qc_event_log if e["type"] == "gate"]
        warn_events = [e for e in self.qc_event_log if e["type"] == "warning"]

        # Build methods paragraph
        profile_phrase = (
            f" using named profile '{self.active_profile}'"
            if self.active_profile else ""
        )
        override_phrase = (
            f" with {len(self.qc_overrides)} custom threshold override(s)"
            if self.qc_overrides else ""
        )
        if gate_events:
            gate_phrase = (
                f"QC gates were triggered for {len(gate_events)} process(es) "
                f"({', '.join(e['process_name'] for e in gate_events)}). "
            )
        else:
            gate_phrase = "All processes passed automated QC gates without intervention. "

        methods_text = (
            f"Quality control was performed automatically by BioMate{profile_phrase}{override_phrase}. "
            f"{gate_phrase}"
            f"A total of {len(warn_events)} near-threshold advisory warning(s) were recorded. "
            f"Gate thresholds and references are described in the BioMate QC governance "
            f"documentation (qc_trace_monitor.py, threshold evidence v3)."
        )

        return {
            "invocation_id": self.invocation_id,
            "active_profile": self.active_profile,
            "active_overrides": dict(self.qc_overrides) if self.qc_overrides else {},
            "gates_triggered": len(gate_events),
            "warnings_emitted": len(warn_events),
            "events": list(self.qc_event_log),
            "methods_text": methods_text,
        }

    def _emit_qc_warning_event(
        self,
        process_name: str,
        qc_metrics: Dict[str, Any],
        warnings: list
    ):
        """
        Emit advisory SSE event for metrics approaching (but not crossing) thresholds.
        Uses event type 'qc_warning' — frontend shows a step annotation without opening a modal.
        """
        event_data = {
            "invocation_id": self.invocation_id,
            "process_name": process_name,
            "qc_metrics": qc_metrics,
            "warnings": warnings,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "overrides_active": bool(self.qc_overrides),
            "active_overrides": dict(self.qc_overrides) if self.qc_overrides else {},
            "active_profile": self.active_profile,
        }
        # US-6.2: append to in-memory event log
        self.qc_event_log.append({
            "type": "warning",
            "process_name": process_name,
            "timestamp": event_data["timestamp"],
            "metrics": qc_metrics,
            "warnings": warnings,
            "active_profile": self.active_profile,
        })

        try:
            self.sse_callback("qc_warning", event_data)
            log.info(f"[QC Gate] Near-threshold warning emitted for {process_name}")
        except Exception as e:
            log.error(f"[QC Gate] Failed to emit warning event: {e}")

        # Friendly chat-progress line: near-threshold advisory (no action needed).
        try:
            from galaxy.ai.workflow_ops.workflow_chat_narrator import emit as _narrator_emit
            primary = warnings[0] if warnings else {}
            _narrator_emit(
                self.invocation_id,
                "workflow.qc_gate_warning",
                technical={
                    "metric": primary.get("metric") or "metric",
                    "value": primary.get("value"),
                    "threshold": primary.get("threshold"),
                    "process_name": process_name,
                    "n_warnings": len(warnings),
                    "advisory_only": True,
                },
                sse_callback=self.sse_callback,
            )
        except Exception as e:
            log.debug("[QC Gate] narrator emit (warning) failed: %s", e)
