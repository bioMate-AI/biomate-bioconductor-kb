#!/usr/bin/env nextflow
/*
 * drug_discovery/adc_design
 *
 * Antibody-Drug Conjugate (ADC) design workflow covering:
 *   1. Payload selection — rules-based scoring across 7 approved ADC payload classes
 *   2. Linker design — cleavable vs non-cleavable linker selection with conjugation site
 *   3. DAR optimization — aggregation risk scoring; site-specific conjugation flag
 *   4. ADC ADMET & PK — plasma stability, bystander killing, off-target tox flags,
 *                        two-analyte PK model (intact ADC + free payload)
 *
 * Payload library (approved ADC chemistries):
 *   - Auristatin MMAE    — DAR 4,   val-cit cleavable,        solid tumors / high antigen
 *   - Auristatin MMAF    — DAR 4,   maleimide-caproyl NC,     hematologic / low bystander
 *   - Maytansinoid DM1   — DAR 3.5, SMCC non-cleavable,       HER2+ solid tumors
 *   - Maytansinoid DM4   — DAR 3.5, disulfide cleavable,      ER+ solid tumors
 *   - SN-38 (TOP1-inhib) — DAR 8,   pH-sensitive cleavable,   TROP2/HER2-low
 *   - PBD dimer          — DAR 2,   disulfide cleavable,       hematologic malignancies
 *   - Calicheamicin      — DAR 2-3, hydrazone acid-labile,    CD33+ AML
 *
 * Input parameters:
 *   target_antigen           (required) — HER2, TROP2, CD33, FOLR1, HER3, EGFR, etc.
 *   indication               (required) — breast_cancer, aml, nsclc, ovarian, etc.
 *   antigen_expression_level (optional, default: high) — high / medium / low
 *   bystander_required       (optional, default: auto) — yes / no / auto
 *   payload_smiles           (optional) — custom payload SMILES for ADMET scoring
 *
 * Outputs:
 *   adc_design_report.json   — full structured results (all 4 steps)
 *   adc_summary.txt          — human-readable design recommendation
 *   payload_ranking.csv      — scored payload comparison table
 *   adc_pk_profile.json      — two-analyte PK parameters
 *
 * References:
 *   - Hamblett et al. 2004 Clin Cancer Res 10:7063 (DAR-PK relationship)
 *   - Junutula et al. 2008 Nat Biotechnol 26:925 (THIOMAB site-specific)
 *   - Casi & Neri 2012 J Control Release 161:422 (linker chemistry review)
 *   - Ogitani et al. 2016 Clin Cancer Res 22:5097 (DS-8201/Enhertu)
 *   - LoRusso et al. 2011 Clin Cancer Res 17:6437 (T-DM1/Kadcyla)
 *   - Bardia et al. 2019 NEJM 380:741 (Trodelvy/sacituzumab)
 *   - Senter & Sievers 2012 Nat Biotechnol 30:631 (SGN-35/Adcetris MMAE)
 */

nextflow.enable.dsl = 2

params.outdir                  = './results'
params.target_antigen          = 'HER2'       // required — e.g. HER2, TROP2, CD33, FOLR1
params.indication              = 'breast_cancer' // required — e.g. breast_cancer, aml, nsclc
params.antigen_expression_level = 'high'      // high | medium | low
params.bystander_required      = 'auto'       // yes | no | auto
params.payload_smiles          = 'null'       // optional custom payload SMILES

// [Phase 1] Payload Selection
// [Phase 2] Linker Design
// [Phase 3] DAR Optimization
// [Phase 4] ADC ADMET & PK

process ADC_DESIGN {
    tag "adc_design"
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("adc_design_report.json"),  emit: design_report
    tuple val(meta), path("adc_summary.txt"),          emit: summary
    tuple val(meta), path("payload_ranking.csv"),      emit: payload_ranking
    tuple val(meta), path("adc_pk_profile.json"),      emit: pk_profile
    path "versions.yml",                               emit: versions

    script:
    """
    export PARAM_ANTIGEN='${params.target_antigen}'
    export PARAM_INDICATION='${params.indication}'
    export PARAM_EXPRESSION='${params.antigen_expression_level}'
    export PARAM_BYSTANDER='${params.bystander_required}'
    export PARAM_SMILES='${params.payload_smiles}'

    python3 << 'PYEOF'
import json, os, csv, math

# ─── Parameters ──────────────────────────────────────────────────────────────
target_antigen  = os.environ.get('PARAM_ANTIGEN', 'HER2').strip().upper()
indication      = os.environ.get('PARAM_INDICATION', 'breast_cancer').strip().lower()
expr_level      = os.environ.get('PARAM_EXPRESSION', 'high').strip().lower()
bystander_req   = os.environ.get('PARAM_BYSTANDER', 'auto').strip().lower()
custom_smiles   = os.environ.get('PARAM_SMILES', 'null').strip()

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 1: Payload Library & Selection
# ─────────────────────────────────────────────────────────────────────────────

# Payload library — each entry encodes physicochemical + clinical properties
PAYLOAD_LIBRARY = [
    {
        "name":            "MMAE (Auristatin E)",
        "class":           "auristatin",
        "mechanism":       "microtubule_inhibitor",
        "dar_nominal":     4.0,
        "dar_range":       [2, 8],
        "kd_nm":           0.1,
        "bystander":       True,
        "bystander_score": 2,     # 0=none, 1=low, 2=high
        "clogp_proxy":     3.5,   # hydrophobicity proxy for aggregation risk
        "linker_default":  "val-cit cleavable",
        "linker_type":     "cleavable",
        "best_for":        ["solid_tumor", "high_antigen_density"],
        "approved_example": "Adcetris (brentuximab vedotin)",
        "off_target_tox":  ["peripheral_neuropathy", "thrombocytopenia"],
        "indication_affinity": {
            "breast_cancer": 3, "nsclc": 3, "bladder_cancer": 3,
            "lymphoma": 4, "aml": 1, "ovarian": 3, "gastric": 3,
        },
        "antigen_affinity": {
            "HER2": 3, "TROP2": 2, "CD30": 5, "NECTIN4": 4, "FOLR1": 3,
        },
        "expression_affinity": {"high": 3, "medium": 2, "low": 1},
    },
    {
        "name":            "MMAF (Auristatin F)",
        "class":           "auristatin",
        "mechanism":       "microtubule_inhibitor",
        "dar_nominal":     4.0,
        "dar_range":       [2, 8],
        "kd_nm":           0.1,
        "bystander":       False,
        "bystander_score": 0,
        "clogp_proxy":     3.8,
        "linker_default":  "maleimide-caproyl non-cleavable",
        "linker_type":     "non-cleavable",
        "best_for":        ["hematologic", "low_bystander_needed"],
        "approved_example": "Depatux-M (depatuxizumab mafodotin)",
        "off_target_tox":  ["thrombocytopenia", "corneal_toxicity"],
        "indication_affinity": {
            "aml": 3, "lymphoma": 4, "multiple_myeloma": 3,
            "breast_cancer": 2, "nsclc": 2, "glioblastoma": 3,
        },
        "antigen_affinity": {
            "CD33": 3, "CD19": 4, "EGFR": 3, "HER2": 2, "TROP2": 1,
        },
        "expression_affinity": {"high": 3, "medium": 3, "low": 2},
    },
    {
        "name":            "DM1 (Maytansinoid)",
        "class":           "maytansinoid",
        "mechanism":       "microtubule_inhibitor",
        "dar_nominal":     3.5,
        "dar_range":       [2, 5],
        "kd_nm":           1.0,
        "bystander":       True,
        "bystander_score": 1,
        "clogp_proxy":     2.8,
        "linker_default":  "SMCC non-cleavable",
        "linker_type":     "non-cleavable",
        "best_for":        ["HER2_solid_tumor", "non_cleavable_preferred"],
        "approved_example": "Kadcyla (ado-trastuzumab emtansine, T-DM1)",
        "off_target_tox":  ["hepatotoxicity", "thrombocytopenia", "neuropathy"],
        "indication_affinity": {
            "breast_cancer": 5, "gastric": 4, "nsclc": 3,
            "ovarian": 3, "colorectal": 2,
        },
        "antigen_affinity": {
            "HER2": 5, "HER3": 3, "EGFR": 2, "FOLR1": 2,
        },
        "expression_affinity": {"high": 5, "medium": 3, "low": 1},
    },
    {
        "name":            "DM4 (Maytansinoid)",
        "class":           "maytansinoid",
        "mechanism":       "microtubule_inhibitor",
        "dar_nominal":     3.5,
        "dar_range":       [2, 5],
        "kd_nm":           1.0,
        "bystander":       True,
        "bystander_score": 2,
        "clogp_proxy":     2.9,
        "linker_default":  "disulfide cleavable",
        "linker_type":     "cleavable",
        "best_for":        ["ER_positive_solid_tumor", "cleavable_preferred"],
        "approved_example": "SAR3419 (anti-CD19-DM4, dev discontinued)",
        "off_target_tox":  ["hepatotoxicity", "ocular_toxicity"],
        "indication_affinity": {
            "breast_cancer": 4, "ovarian": 4, "nsclc": 3,
            "lymphoma": 3, "aml": 1,
        },
        "antigen_affinity": {
            "HER2": 3, "FOLR1": 4, "CD44": 3, "EGFR": 2,
        },
        "expression_affinity": {"high": 4, "medium": 4, "low": 2},
    },
    {
        "name":            "SN-38 (Camptothecin/TOP1 inhibitor)",
        "class":           "camptothecin",
        "mechanism":       "topoisomerase_I_inhibitor",
        "dar_nominal":     8.0,
        "dar_range":       [6, 10],
        "kd_nm":           10.0,
        "bystander":       True,
        "bystander_score": 3,     # bystander++ (membrane permeable)
        "clogp_proxy":     1.2,   # low — hydrophilic; stable at high DAR
        "linker_default":  "pH-sensitive hydrazone cleavable",
        "linker_type":     "cleavable",
        "best_for":        ["TROP2", "HER2_low_expression", "high_DAR_tolerated"],
        "approved_example": "Trodelvy (sacituzumab govitecan), Enhertu (T-DXd)",
        "off_target_tox":  ["neutropenia", "diarrhea", "interstitial_lung_disease"],
        "indication_affinity": {
            "breast_cancer": 5, "nsclc": 5, "urothelial": 4,
            "ovarian": 4, "gastric": 4, "colorectal": 3,
        },
        "antigen_affinity": {
            "TROP2": 5, "HER2": 5, "HER3": 4, "EGFR": 3, "FOLR1": 3, "B7H3": 3,
        },
        "expression_affinity": {"high": 4, "medium": 5, "low": 5},
    },
    {
        "name":            "PBD dimer (Pyrrolobenzodiazepine)",
        "class":           "pbd",
        "mechanism":       "dna_crosslinker",
        "dar_nominal":     2.0,
        "dar_range":       [1, 2],
        "kd_nm":           0.01,
        "bystander":       False,
        "bystander_score": 0,
        "clogp_proxy":     4.2,
        "linker_default":  "disulfide cleavable",
        "linker_type":     "cleavable",
        "best_for":        ["hematologic_malignancies", "ultra_potent_needed"],
        "approved_example": "Zynlonta (loncastuximab tesirine, anti-CD19-PBD)",
        "off_target_tox":  ["pulmonary_toxicity", "effusions", "skin_toxicity"],
        "indication_affinity": {
            "lymphoma": 5, "aml": 4, "cll": 4, "multiple_myeloma": 3,
            "breast_cancer": 1, "nsclc": 1,
        },
        "antigen_affinity": {
            "CD19": 5, "CD33": 4, "CD22": 4, "BCMA": 3, "HER2": 1,
        },
        "expression_affinity": {"high": 3, "medium": 3, "low": 4},
    },
    {
        "name":            "Calicheamicin",
        "class":           "calicheamicin",
        "mechanism":       "dna_double_strand_break",
        "dar_nominal":     2.5,
        "dar_range":       [2, 3],
        "kd_nm":           0.01,
        "bystander":       False,
        "bystander_score": 0,
        "clogp_proxy":     3.0,
        "linker_default":  "hydrazone acid-labile",
        "linker_type":     "cleavable",
        "best_for":        ["CD33_AML", "hematologic"],
        "approved_example": "Mylotarg (gemtuzumab ozogamicin, CD33-calicheamicin)",
        "off_target_tox":  ["hepatotoxicity", "sinusoidal_obstruction_syndrome", "hemorrhage"],
        "indication_affinity": {
            "aml": 5, "all": 4, "lymphoma": 3,
            "breast_cancer": 0, "nsclc": 0,
        },
        "antigen_affinity": {
            "CD33": 5, "CD22": 4, "CD19": 3, "TROP2": 0,
        },
        "expression_affinity": {"high": 3, "medium": 3, "low": 3},
    },
]

def score_payload(p, antigen, indication, expr_lvl, bystander_req):
    """Composite payload score (0-100)."""
    score = 0

    # Indication match (0-5, weight 30)
    ind_scores = p.get("indication_affinity", {})
    ind_score = ind_scores.get(indication, ind_scores.get(indication.split("_")[0], 2))
    score += ind_score * 6  # max 30

    # Antigen match (0-5, weight 25)
    ag_scores = p.get("antigen_affinity", {})
    ag_score = ag_scores.get(antigen, 2)
    score += ag_score * 5  # max 25

    # Expression level fit (weight 15)
    expr_scores = p.get("expression_affinity", {})
    score += expr_scores.get(expr_lvl, 2) * 3  # max 15

    # Bystander requirement fit (weight 20)
    if bystander_req == "auto":
        # For hematologic: prefer no bystander (protect normal marrow)
        hemato_indications = {"aml", "all", "lymphoma", "cll", "multiple_myeloma"}
        if any(h in indication for h in hemato_indications):
            bystander_req_resolved = "no"
        else:
            bystander_req_resolved = "yes"
    else:
        bystander_req_resolved = bystander_req

    if bystander_req_resolved == "yes" and p["bystander"]:
        score += 20
    elif bystander_req_resolved == "no" and not p["bystander"]:
        score += 20
    elif bystander_req_resolved == "yes" and not p["bystander"]:
        score += 5   # non-ideal but not disqualifying
    else:
        score += 10  # bystander present but not needed — minor penalty

    # Potency fit for expression level (low expression → prefer ultra-potent)
    if expr_lvl == "low" and p["kd_nm"] <= 0.01:
        score += 10  # bonus for ultra-potent when antigen is scarce

    return min(100, score)

# Score all payloads
scored = []
for p in PAYLOAD_LIBRARY:
    s = score_payload(p, target_antigen, indication, expr_level, bystander_req)
    scored.append({**p, "composite_score": s})

scored.sort(key=lambda x: -x["composite_score"])
for i, p in enumerate(scored):
    p["rank"] = i + 1
top3 = scored[:3]

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 2: Linker Design
# ─────────────────────────────────────────────────────────────────────────────

LINKER_OPTIONS = {
    "val-cit cleavable": {
        "mechanism": "cathepsin_B_lysosomal",
        "cleavage_site": "lysosome (cathepsin B, pH 4.5-5.0)",
        "plasma_stability_score": 3,   # 1=poor, 5=excellent
        "lysosomal_release_rate": 5,   # 1=slow, 5=fast
        "bystander_potential": "high (MMAE membrane permeable)",
        "aggregation_risk_modifier": 0,
        "clinical_examples": ["Adcetris", "Polivy", "Padcev"],
    },
    "disulfide cleavable": {
        "mechanism": "glutathione_intracellular",
        "cleavage_site": "cytoplasm (glutathione, 1-10 mM intracellular)",
        "plasma_stability_score": 3,
        "lysosomal_release_rate": 4,
        "bystander_potential": "moderate",
        "aggregation_risk_modifier": 0,
        "clinical_examples": ["SAR3419 (dev)"],
    },
    "pH-sensitive hydrazone cleavable": {
        "mechanism": "acid_labile_endosomal",
        "cleavage_site": "endosome (pH 5.0-6.5) + lysosome",
        "plasma_stability_score": 2,   # moderate plasma stability
        "lysosomal_release_rate": 5,
        "bystander_potential": "very high (membrane permeable metabolite)",
        "aggregation_risk_modifier": -1,  # hydrophilic linker reduces aggregation
        "clinical_examples": ["Mylotarg", "Besylomab"],
    },
    "beta-glucuronide cleavable": {
        "mechanism": "beta_glucuronidase_lysosomal",
        "cleavage_site": "lysosome (beta-glucuronidase)",
        "plasma_stability_score": 5,   # excellent plasma stability
        "lysosomal_release_rate": 3,
        "bystander_potential": "low (glucuronide is hydrophilic prodrug)",
        "aggregation_risk_modifier": -1,
        "clinical_examples": ["preclinical stage"],
    },
    "SMCC non-cleavable": {
        "mechanism": "lysosomal_proteolysis_of_antibody",
        "cleavage_site": "lysosome (antibody proteolysis releases payload-lysine adduct)",
        "plasma_stability_score": 5,
        "lysosomal_release_rate": 2,
        "bystander_potential": "low-moderate (charged metabolite, limited permeability)",
        "aggregation_risk_modifier": 1,  # maleimide hydrophobic
        "clinical_examples": ["Kadcyla (T-DM1)"],
    },
    "maleimide-caproyl non-cleavable": {
        "mechanism": "lysosomal_proteolysis_of_antibody",
        "cleavage_site": "lysosome (antibody proteolysis)",
        "plasma_stability_score": 5,
        "lysosomal_release_rate": 2,
        "bystander_potential": "none (charged metabolite cannot exit cell)",
        "aggregation_risk_modifier": 2,  # caproyl spacer is hydrophobic
        "clinical_examples": ["Depatux-M"],
    },
}

CONJUGATION_SITES = {
    "lysine": {
        "method": "NHS-ester amide coupling",
        "dar_uniformity": "heterogeneous (DAR distribution 0-8)",
        "site_specificity": "low",
        "aggregation_risk": "moderate",
        "notes": "Multiple lysines — heterogeneous mixture; average DAR measurable by UV-vis",
    },
    "cysteine_interchain": {
        "method": "maleimide thiol-Michael addition (partial reduction)",
        "dar_uniformity": "semi-homogeneous (DAR 0/2/4/6/8 distribution)",
        "site_specificity": "moderate",
        "aggregation_risk": "moderate",
        "notes": "4 interchain disulfides → partial reduction → DAR 2/4/6/8; standard for most approved ADCs",
    },
    "site_specific_thiomab": {
        "method": "THIOMAB engineered cysteine",
        "dar_uniformity": "homogeneous DAR 2",
        "site_specificity": "high",
        "aggregation_risk": "low",
        "notes": "Junutula 2008 — improved TI vs cysteine-conjugated DAR4; FDA precedent for homogeneous ADCs",
    },
    "site_specific_unnatural_aa": {
        "method": "amber-stop codon suppression (pAcPhe) + oxime ligation",
        "dar_uniformity": "homogeneous DAR 2",
        "site_specificity": "very high",
        "aggregation_risk": "low",
        "notes": "Optimal TI; complex manufacturing; no approved ADC yet but clinical stage",
    },
}

def design_linker(payload, expr_level, dar_nominal):
    """Select optimal linker and conjugation site for payload."""
    linker_name = payload["linker_default"]
    linker_info = LINKER_OPTIONS.get(linker_name, LINKER_OPTIONS["val-cit cleavable"])

    # Conjugation site selection
    if dar_nominal <= 2:
        conj_site = "site_specific_thiomab"
        conj_rationale = "Low DAR target — site-specific conjugation provides homogeneous DAR 2 for optimal PK/TI"
    elif dar_nominal >= 7:
        conj_site = "cysteine_interchain"
        conj_rationale = "High DAR class — interchain cysteine standard; site-specific not feasible at DAR 8"
    else:
        conj_site = "cysteine_interchain"
        conj_rationale = "DAR 3-5 range — cysteine conjugation standard for clinical manufacturing"

    conj_info = CONJUGATION_SITES[conj_site]

    # Aggregation risk adjusted by linker hydrophobicity
    base_agg_risk = dar_nominal * payload["clogp_proxy"] / 10.0
    adjusted_agg = base_agg_risk + linker_info["aggregation_risk_modifier"] * 0.2

    agg_category = "LOW" if adjusted_agg < 1.5 else "MODERATE" if adjusted_agg < 2.5 else "HIGH"

    return {
        "linker_name":           linker_name,
        "linker_mechanism":      linker_info["mechanism"],
        "cleavage_site":         linker_info["cleavage_site"],
        "plasma_stability_score": linker_info["plasma_stability_score"],
        "lysosomal_release_rate": linker_info["lysosomal_release_rate"],
        "bystander_potential":   linker_info["bystander_potential"],
        "conjugation_site":      conj_site,
        "conjugation_method":    conj_info["method"],
        "dar_uniformity":        conj_info["dar_uniformity"],
        "aggregation_risk":      agg_category,
        "aggregation_score":     round(adjusted_agg, 3),
        "conjugation_rationale": conj_rationale,
        "clinical_examples":     linker_info["clinical_examples"],
    }

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 3: DAR Optimization
# ─────────────────────────────────────────────────────────────────────────────

def optimize_dar(payload, linker_design):
    """
    DAR scoring per Hamblett et al. 2004:
      DAR < 2:  insufficient potency
      DAR 2-4:  optimal PK, minimal aggregation (preferred)
      DAR > 4:  increased aggregation, faster clearance
      DAR 8 (SN-38 class): acceptable only for stable hydrophilic linkers
    """
    dar = payload["dar_nominal"]
    clogp = payload["clogp_proxy"]

    # Aggregation risk score: DAR × clogP proxy (normalized)
    agg_score = dar * clogp / 10.0  # >2.5 = HIGH risk

    # Potency score: inverse kd (subnanomolar = max)
    potency_score = min(5.0, 1.0 / (payload["kd_nm"] + 0.01))

    # DAR category
    if dar < 2:
        dar_flag   = "INSUFFICIENT_POTENCY"
        dar_ok     = False
    elif 2 <= dar <= 4:
        dar_flag   = "OPTIMAL"
        dar_ok     = True
    elif 4 < dar <= 6:
        dar_flag   = "ELEVATED_RISK"
        dar_ok     = True  # acceptable with low-clogP payload
    else:  # DAR > 6
        if clogp < 2.0:
            dar_flag = "HIGH_DAR_HYDROPHILIC_ACCEPTABLE"
            dar_ok   = True
        else:
            dar_flag = "AGGREGATION_RISK_HIGH"
            dar_ok   = False

    # Recommendation
    rec_site_specific = linker_design["aggregation_risk"] == "HIGH" or not dar_ok

    return {
        "dar_nominal":           dar,
        "dar_range":             payload["dar_range"],
        "dar_flag":              dar_flag,
        "aggregation_risk_score": round(agg_score, 3),
        "aggregation_category":  "HIGH" if agg_score >= 2.5 else "MODERATE" if agg_score >= 1.5 else "LOW",
        "potency_score":         round(potency_score, 3),
        "recommend_site_specific_conjugation": rec_site_specific,
        "site_specific_reason":  "Aggregation risk exceeds threshold — site-specific conjugation recommended to reduce heterogeneity and improve TI" if rec_site_specific else None,
        "pk_impact":             "Optimal clearance (t½ 4-7 days IgG-like)" if dar_ok and dar <= 4 else "Accelerated clearance expected (DAR >4 increases FcRn-independent elimination)",
    }

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 4: ADC ADMET & PK
# ─────────────────────────────────────────────────────────────────────────────

# Payload class PK parameters (literature-derived)
PAYLOAD_PK_PARAMS = {
    "auristatin": {
        "free_payload_t_half_h": 1.2,    # MMAE free drug t½ ~1-3h (plasma)
        "free_payload_vd_lkg":   40.0,   # high Vd (lipophilic)
        "free_payload_cl_mlmin": 300.0,
        "payload_class_mw":      717.9,
        "plasma_cleavage_pct_day": 3.0,  # ~3%/day val-cit in plasma
    },
    "maytansinoid": {
        "free_payload_t_half_h": 5.4,    # DM1 metabolites t½ ~5h
        "free_payload_vd_lkg":   15.0,
        "free_payload_cl_mlmin": 100.0,
        "payload_class_mw":      738.0,
        "plasma_cleavage_pct_day": 1.0,  # SMCC very stable
    },
    "camptothecin": {
        "free_payload_t_half_h": 0.5,    # SN-38 t½ short (lactone form)
        "free_payload_vd_lkg":   5.0,
        "free_payload_cl_mlmin": 500.0,
        "payload_class_mw":      392.4,
        "plasma_cleavage_pct_day": 4.5,  # pH-sensitive cleavage faster
    },
    "pbd": {
        "free_payload_t_half_h": 0.8,
        "free_payload_vd_lkg":   25.0,
        "free_payload_cl_mlmin": 200.0,
        "payload_class_mw":      590.0,
        "plasma_cleavage_pct_day": 1.5,  # disulfide — moderate stability
    },
    "calicheamicin": {
        "free_payload_t_half_h": 2.0,
        "free_payload_vd_lkg":   20.0,
        "free_payload_cl_mlmin": 150.0,
        "payload_class_mw":      1368.0,
        "plasma_cleavage_pct_day": 5.0,  # hydrazone — fastest cleavage
    },
}

def compute_adc_pk(payload, dar):
    """
    Two-analyte ADC PK model:
      Analyte 1: Intact ADC — IgG-like disposition + DAR-dependent clearance
      Analyte 2: Free payload — rapid small-molecule disposition

    Based on:
      - Intact ADC t½ = base_IgG_t_half × exp(-k_DAR × (DAR - 2))
        where k_DAR ~ 0.1/unit DAR (Hamblett 2004)
      - Free payload: first-order release + elimination
    """
    pk = PAYLOAD_PK_PARAMS.get(payload["class"], PAYLOAD_PK_PARAMS["auristatin"])

    # Intact ADC parameters
    base_igg_t_half_days = 21.0  # typical IgG1 FcRn-recycled t½
    k_dar_penalty = 0.1           # per DAR unit above 2
    dar_excess = max(0, dar - 2)
    adc_t_half_days = base_igg_t_half_days * math.exp(-k_dar_penalty * dar_excess)
    adc_t_half_days = round(adc_t_half_days, 2)

    # Clearance (mL/day/kg)
    base_cl_ml_day = 5.0   # typical mAb CL ~5 mL/day/kg
    adc_cl_ml_day_kg = base_cl_ml_day * math.exp(k_dar_penalty * dar_excess)
    adc_cl_ml_day_kg = round(adc_cl_ml_day_kg, 3)

    # Volume of distribution (IgG-like + DAR-dependent increase)
    adc_vd_ml_kg = 50.0 + dar_excess * 5.0  # plasma volume + some peripheral

    # AUC proxy (dose 3 mg/kg IV)
    dose_mg_kg = 3.0
    auc_mg_day_l = round(dose_mg_kg / (adc_cl_ml_day_kg / 1000), 1)  # dose/CL

    # Payload release kinetics
    cleavage_rate_day = pk["plasma_cleavage_pct_day"] / 100.0  # fraction/day
    free_payload_css_ng_ml = round(
        dose_mg_kg * 1e6 * dar / payload["dar_nominal"]  # ng/kg dose
        * cleavage_rate_day                                # release fraction
        / (pk["free_payload_cl_mlmin"] * 1440)            # clearance mL/day
        * 1000,                                            # convert to ng/mL
        2
    )

    # Therapeutic index estimate
    # TI proxy: ratio of tumor AUC (high antigen uptake) to normal tissue AUC
    # Simplified: tumor Kd-weighted uptake / normal tissue non-specific uptake
    antigen_uptake_factor = 1.0 / (payload["kd_nm"] + 1.0)  # higher for high-affinity
    ti_proxy = round(10.0 * antigen_uptake_factor * (1.0 / (cleavage_rate_day * 5 + 0.1)), 1)
    ti_category = "FAVORABLE" if ti_proxy >= 5 else "MODERATE" if ti_proxy >= 2 else "NARROW"

    return {
        "intact_adc": {
            "t_half_days":           adc_t_half_days,
            "clearance_ml_day_kg":   adc_cl_ml_day_kg,
            "vd_ml_kg":              round(adc_vd_ml_kg, 1),
            "auc_proxy_mg_day_L":    auc_mg_day_l,
            "dosing_interval_recommendation": "Q3W (every 21 days) standard for IgG1 ADC",
        },
        "free_payload": {
            "t_half_h":              pk["free_payload_t_half_h"],
            "vd_l_kg":               pk["free_payload_vd_lkg"],
            "clearance_ml_min":      pk["free_payload_cl_mlmin"],
            "estimated_css_ng_ml":   free_payload_css_ng_ml,
            "plasma_stability_pct_day_cleavage": pk["plasma_cleavage_pct_day"],
        },
        "therapeutic_index": {
            "ti_proxy":   ti_proxy,
            "ti_category": ti_category,
            "basis": "tumor Kd-weighted uptake / non-specific bystander cleavage model",
        },
    }

def compute_admet(payload, linker_design):
    """ADC-specific ADMET flags."""
    off_tox = payload["off_target_tox"]

    # Plasma stability: based on linker type
    plasma_stab = linker_design["plasma_stability_score"]
    plasma_ok = plasma_stab >= 3

    # Bystander killing radius estimate
    if payload["bystander_score"] == 0:
        bystander_radius = "< 1 cell diameter (no bystander)"
    elif payload["bystander_score"] == 1:
        bystander_radius = "1-3 cell diameters (limited bystander, charged metabolite)"
    elif payload["bystander_score"] == 2:
        bystander_radius = "3-10 cell diameters (membrane-permeable metabolite)"
    else:
        bystander_radius = "> 10 cell diameters (highly membrane-permeable, SN-38 class)"

    # Off-target toxicity flags
    tox_flags = []
    if "thrombocytopenia" in off_tox:
        tox_flags.append({"flag": "THROMBOCYTOPENIA_RISK", "severity": "MODERATE",
                           "class": payload["class"], "mitigation": "Monitor CBC q3w; dose reduce at Grade 3"})
    if "peripheral_neuropathy" in off_tox:
        tox_flags.append({"flag": "PERIPHERAL_NEUROPATHY", "severity": "MODERATE",
                           "class": "auristatin_MMAE", "mitigation": "Neurotoxicity monitoring; consider MMAF if CNS boundary needed"})
    if "hepatotoxicity" in off_tox:
        tox_flags.append({"flag": "HEPATOTOXICITY", "severity": "HIGH",
                           "class": payload["class"], "mitigation": "LFT monitoring; dose modify at ALT >3xULN"})
    if "sinusoidal_obstruction_syndrome" in off_tox:
        tox_flags.append({"flag": "SINUSOIDAL_OBSTRUCTION_SYNDROME", "severity": "HIGH",
                           "class": "calicheamicin", "mitigation": "Contraindicated pre-HSCT; fractionated dosing reduces risk"})
    if "interstitial_lung_disease" in off_tox:
        tox_flags.append({"flag": "INTERSTITIAL_LUNG_DISEASE", "severity": "HIGH",
                           "class": "camptothecin_SN38", "mitigation": "Pulmonary monitoring; permanently discontinue at Grade 2+"})

    return {
        "plasma_stability": {
            "score": plasma_stab,
            "assessment": "STABLE" if plasma_ok else "UNSTABLE — monitor for premature release",
            "cleavage_mechanism": linker_design["linker_mechanism"],
        },
        "bystander_killing_radius": bystander_radius,
        "off_target_toxicity_flags": tox_flags,
        "regulatory_classification": "Biologic + cytotoxic — dual IND/BLA path; CMC for ADC-specific analytics (DAR by HIC, free drug by ELISA)",
    }

# ─── Assemble results ─────────────────────────────────────────────────────────
top_payload    = top3[0]
linker_design  = design_linker(top_payload, expr_level, top_payload["dar_nominal"])
dar_report     = optimize_dar(top_payload, linker_design)
admet_report   = compute_admet(top_payload, linker_design)
pk_report      = compute_adc_pk(top_payload, top_payload["dar_nominal"])

# All 3 linker designs for comparison
linker_designs_all = [design_linker(p, expr_level, p["dar_nominal"]) for p in top3]

full_report = {
    "status": "completed",
    "input": {
        "target_antigen":          target_antigen,
        "indication":              indication,
        "antigen_expression_level": expr_level,
        "bystander_required":      bystander_req,
        "custom_smiles":           custom_smiles if custom_smiles != "null" else None,
    },
    "phase1_payload_selection": {
        "total_payloads_scored": len(scored),
        "top_3_payloads": [
            {
                "rank":            i + 1,
                "name":            p["name"],
                "class":           p["class"],
                "composite_score": p["composite_score"],
                "dar_nominal":     p["dar_nominal"],
                "kd_nm":           p["kd_nm"],
                "bystander":       p["bystander"],
                "linker_default":  p["linker_default"],
                "approved_example": p["approved_example"],
                "best_for":        p["best_for"],
            }
            for i, p in enumerate(top3)
        ],
        "recommendation": f"Primary recommendation: {top_payload['name']} (score {top_payload['composite_score']}/100) based on {indication} indication, {target_antigen} antigen, and {expr_level} expression level",
    },
    "phase2_linker_design": {
        "top_payload_linker": linker_design,
        "alternative_linkers": [
            {"payload": top3[i]["name"], "linker": ld}
            for i, ld in enumerate(linker_designs_all)
        ],
    },
    "phase3_dar_optimization": dar_report,
    "phase4_admet_pk": {
        "admet": admet_report,
        "pk_model": pk_report,
    },
    "design_recommendation": {
        "payload":      top_payload["name"],
        "linker":       linker_design["linker_name"],
        "conjugation":  linker_design["conjugation_site"],
        "dar_target":   top_payload["dar_nominal"],
        "dar_flag":     dar_report["dar_flag"],
        "aggregation":  dar_report["aggregation_category"],
        "ti_estimate":  pk_report["therapeutic_index"]["ti_category"],
        "summary":      (
            f"Recommend {top_payload['name']} conjugated via "
            f"{linker_design['conjugation_site'].replace('_',' ')} with "
            f"{linker_design['linker_name']} (DAR {top_payload['dar_nominal']:.0f}). "
            f"Aggregation risk: {dar_report['aggregation_category']}. "
            f"Estimated TI: {pk_report['therapeutic_index']['ti_category']}. "
            f"Closest approved analogue: {top_payload['approved_example']}."
        ),
    },
    "references": [
        "Hamblett et al. 2004 Clin Cancer Res 10:7063 (DAR-PK relationship)",
        "Junutula et al. 2008 Nat Biotechnol 26:925 (THIOMAB site-specific)",
        "Casi & Neri 2012 J Control Release 161:422 (linker chemistry review)",
        "Ogitani et al. 2016 Clin Cancer Res 22:5097 (DS-8201/Enhertu SN-38)",
        "LoRusso et al. 2011 Clin Cancer Res 17:6437 (T-DM1/Kadcyla DM1)",
        "Bardia et al. 2019 NEJM 380:741 (Trodelvy sacituzumab/SN-38)",
        "Senter & Sievers 2012 Nat Biotechnol 30:631 (SGN-35/Adcetris MMAE)",
    ],
}

# ─── Write adc_design_report.json ─────────────────────────────────────────────
with open("adc_design_report.json", "w") as f:
    json.dump(full_report, f, indent=2)

# ─── Write payload_ranking.csv ────────────────────────────────────────────────
csv_cols = [
    "rank", "name", "class", "composite_score", "dar_nominal",
    "kd_nm", "bystander", "clogp_proxy", "linker_default", "approved_example",
]
with open("payload_ranking.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=csv_cols, extrasaction="ignore")
    w.writeheader()
    for i, p in enumerate(scored):
        row = {k: p[k] for k in csv_cols if k in p}
        row["rank"] = i + 1
        w.writerow(row)

# ─── Write adc_pk_profile.json ────────────────────────────────────────────────
pk_profile = {
    "target_antigen":  target_antigen,
    "indication":      indication,
    "selected_payload": top_payload["name"],
    "dar":             top_payload["dar_nominal"],
    "two_analyte_model": pk_report,
    "dosing_recommendation": {
        "route":    "IV infusion",
        "interval": "Q3W (every 21 days)",
        "dose_range_mg_kg": "1.8–6.0 depending on payload class",
        "basis": "IgG1 PK with DAR-adjusted clearance (Hamblett 2004 model)",
    },
}
with open("adc_pk_profile.json", "w") as f:
    json.dump(pk_profile, f, indent=2)

# ─── Write adc_summary.txt ────────────────────────────────────────────────────
rec = full_report["design_recommendation"]
lines = [
    "╔══════════════════════════════════════════════════════════════════╗",
    "  ADC Design Report — BioMate AI Platform",
    f"  Target: {target_antigen}  |  Indication: {indication}",
    f"  Antigen expression: {expr_level}  |  Bystander: {bystander_req}",
    "╚══════════════════════════════════════════════════════════════════╝",
    "",
    "── DESIGN RECOMMENDATION ───────────────────────────────────────────",
    f"  Payload:         {rec['payload']}",
    f"  Linker:          {rec['linker']}",
    f"  Conjugation:     {rec['conjugation'].replace('_',' ')}",
    f"  DAR target:      {rec['dar_target']}",
    f"  DAR status:      {rec['dar_flag']}",
    f"  Aggregation:     {rec['aggregation']}",
    f"  Therapeutic TI:  {rec['ti_estimate']}",
    "",
    f"  Summary: {rec['summary']}",
    "",
    "── PHASE 1: PAYLOAD RANKING (Top 7) ────────────────────────────────",
    f"  {'Rank':<5} {'Score':<7} {'Name':<35} {'DAR':<5} {'Kd(nM)':<9} {'Bystander'}",
    "  " + "-" * 72,
]
for p in scored:
    lines.append(
        f"  {p['rank']:<5} {p['composite_score']:<7} {p['name']:<35} "
        f"{p['dar_nominal']:<5} {p['kd_nm']:<9} {'Yes' if p['bystander'] else 'No'}"
    )

lines += [
    "",
    "── PHASE 2: LINKER DESIGN ──────────────────────────────────────────",
    f"  Linker:            {linker_design['linker_name']}",
    f"  Mechanism:         {linker_design['linker_mechanism']}",
    f"  Cleavage site:     {linker_design['cleavage_site']}",
    f"  Plasma stability:  {linker_design['plasma_stability_score']}/5",
    f"  Bystander:         {linker_design['bystander_potential']}",
    f"  Conjugation:       {linker_design['conjugation_method']}",
    f"  DAR uniformity:    {linker_design['dar_uniformity']}",
    f"  Aggregation risk:  {linker_design['aggregation_risk']}",
    "",
    "── PHASE 3: DAR OPTIMIZATION ──────────────────────────────────────",
    f"  DAR nominal:       {dar_report['dar_nominal']}",
    f"  DAR flag:          {dar_report['dar_flag']}",
    f"  Aggregation score: {dar_report['aggregation_risk_score']} ({dar_report['aggregation_category']})",
    f"  PK impact:         {dar_report['pk_impact']}",
]
if dar_report["recommend_site_specific_conjugation"]:
    lines.append(f"  ** Site-specific conjugation RECOMMENDED: {dar_report['site_specific_reason']}")

lines += [
    "",
    "── PHASE 4: ADC ADMET & PK ─────────────────────────────────────────",
    f"  Plasma stability:  {admet_report['plasma_stability']['assessment']}",
    f"  Bystander radius:  {admet_report['bystander_killing_radius']}",
    "",
    "  Off-target toxicity flags:",
]
for flag in admet_report["off_target_toxicity_flags"]:
    lines.append(f"    [{flag['severity']}] {flag['flag']}: {flag['mitigation']}")
if not admet_report["off_target_toxicity_flags"]:
    lines.append("    None identified")

lines += [
    "",
    "  Two-Analyte PK Model:",
    f"    Intact ADC t½:       {pk_report['intact_adc']['t_half_days']} days",
    f"    Intact ADC CL:       {pk_report['intact_adc']['clearance_ml_day_kg']} mL/day/kg",
    f"    Free payload t½:     {pk_report['free_payload']['t_half_h']} h",
    f"    Plasma free drug Css: {pk_report['free_payload']['estimated_css_ng_ml']} ng/mL (estimated)",
    f"    Therapeutic index:   {pk_report['therapeutic_index']['ti_proxy']} ({pk_report['therapeutic_index']['ti_category']})",
    "",
    "── REFERENCES ──────────────────────────────────────────────────────",
]
for ref in full_report["references"]:
    lines.append(f"  · {ref}")

summary_text = "\\n".join(lines) + "\\n"
with open("adc_summary.txt", "w") as f:
    f.write(summary_text)

print(summary_text)
PYEOF

    python3 -c "print('adc_design: 1.0')" > versions.yml
    """
}

workflow ADC_DESIGN_WORKFLOW {
    take: meta_ch
    main: ADC_DESIGN(meta_ch)
    emit:
        design_report   = ADC_DESIGN.out.design_report
        summary         = ADC_DESIGN.out.summary
        payload_ranking = ADC_DESIGN.out.payload_ranking
        pk_profile      = ADC_DESIGN.out.pk_profile
}

workflow { meta = [id: 'adc_design_run']; Channel.value(meta) | ADC_DESIGN_WORKFLOW }
