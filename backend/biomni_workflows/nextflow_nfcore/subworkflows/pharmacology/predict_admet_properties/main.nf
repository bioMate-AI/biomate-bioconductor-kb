#!/usr/bin/env nextflow
/*
 * pharmacology/predict_admet_properties
 *
 * Predicts ADMET (Absorption, Distribution, Metabolism, Excretion, Toxicity)
 * properties for a list of compounds using:
 *   1. RDKit molecular descriptors (hERG IC50 estimate, DILI risk) — always runs
 *   2. DeepPurpose MPNN/CNN/Morgan pretrained models (ClinTox, solubility, etc.)
 *      — optional; runs when DeepPurpose is installed in the container.
 *
 * Always produces toxicity_report.json with structured QC-gate-ready fields.
 * nf-core style module generated from tested Galaxy wrapper.
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: aspirin (safe control) + terfenadine (known hERG risk — withdrawn from market)
// Demonstrates QC gate triggering for hERG cardiotoxicity risk.
params.smiles_list = '["CC(=O)OC1=CC=CC=C1C(=O)O", "OC(CCCN1CCC(CC1)C(O)(c1ccccc1)c1ccccc1)(c1ccc(cc1)C(C)(C)C)CC"]'
params.ADMET_model_type = 'MPNN'

process PREDICT_ADMET_PROPERTIES {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // biomni-tools has RDKit + AWS CLI baked in (biomni-pharma:x86 is stale, lacks aws)
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("predict_admet_properties_results.json"), emit: results
    tuple val(meta), path("predict_admet_properties_output.txt"), emit: output
    tuple val(meta), path("toxicity_report.json"), emit: toxicity_report
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_SMILES_LIST="${params.smiles_list?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_ADMET_MODEL_TYPE="${params.ADMET_model_type?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper — self-contained implementation
# Phase 1: RDKit structural safety (always runs, no heavy dependencies)
# Phase 2: DeepPurpose MPNN predictions (optional, runs when installed)
import subprocess
import sys
import json
import os
import re

def auto_convert(val):
    if val is None or val == '' or val == 'null':
        return None
    if isinstance(val, str) and val.lower() in ('true', 'false'):
        return val.lower() == 'true'
    if isinstance(val, str) and val.strip().startswith(('[', '{')):
        try:
            return json.loads(val)
        except json.JSONDecodeError:
            pass
    try:
        if isinstance(val, str) and '.' not in val:
            return int(val)
    except ValueError:
        pass
    try:
        return float(val)
    except ValueError:
        pass
    return val


def compute_structural_safety(smiles_list):
    '''
    Estimate toxicity flags from molecular descriptors (RDKit).

    Provides literature-backed heuristic estimates for:
      - hERG IC50 (μM):  logP-based model (Aronov 2008 J Med Chem 51:6632;
                          Price et al. 2009 Bioorg Med Chem 17:3028)
      - DILI risk:        Lipophilicity + MW model (Lammert et al. 2010
                          Toxicol Sci 116:536; Fontana et al. 2010 Hepatology)

    Returns worst-case metrics across all compounds, or {} if RDKit unavailable.
    '''
    try:
        from rdkit import Chem
        from rdkit.Chem import Descriptors
    except ImportError:
        return {}

    items = smiles_list if isinstance(smiles_list, list) else [str(smiles_list)]
    compound_results = []

    for smiles in items:
        smiles = str(smiles).strip()
        if not smiles:
            continue
        mol = Chem.MolFromSmiles(smiles)
        if mol is None:
            compound_results.append({
                "smiles": smiles,
                "error": "Invalid SMILES — could not parse structure",
            })
            continue

        logp = Descriptors.MolLogP(mol)
        mw = Descriptors.MolWt(mol)

        # ── hERG IC50 heuristic ──────────────────────────────────────────────
        # Linear relationship between LogP and hERG activity is well-established.
        # Simplified model: log10(IC50 [μM]) ≈ 1.4 - 0.30 * logP
        # Valid range: logP -2 to 8 (covers most drug-like space)
        log10_ic50 = 1.4 - 0.30 * logp
        herg_ic50 = round(max(0.01, 10 ** log10_ic50), 3)

        # ── DILI risk ────────────────────────────────────────────────────────
        # Lammert et al. (2010): LogP > 3 AND daily dose > threshold → DILI risk
        # Without dose information, use LogP + MW as proxy:
        if logp > 4.0 and mw > 400:
            dili_risk = "high"
            dili_prob = round(min(0.90, 0.55 + 0.05 * (logp - 4.0)), 3)
        elif logp > 2.5 or mw > 350:
            dili_risk = "medium"
            dili_prob = round(min(0.70, 0.30 + 0.04 * max(0, logp)), 3)
        else:
            dili_risk = "low"
            dili_prob = round(max(0.05, 0.08 + 0.02 * max(0, logp)), 3)

        compound_results.append({
            "smiles": smiles,
            "logP": round(logp, 2),
            "mw": round(mw, 1),
            "herg_ic50_uM": herg_ic50,
            "dili_risk": dili_risk,
            "dili_probability": dili_prob,
        })

    valid = [r for r in compound_results if "error" not in r]
    if not valid:
        return {}

    min_herg_ic50 = min(r["herg_ic50_uM"] for r in valid)
    worst_dili = max(valid, key=lambda r: r["dili_probability"])

    return {
        "herg_ic50_uM": min_herg_ic50,
        "dili_risk": worst_dili["dili_risk"],
        "dili_probability": worst_dili["dili_probability"],
        "per_compound": compound_results,
    }


def compute_ames_alerts(smiles_input):
    '''
    Ames mutagenicity prediction via structural alerts.

    Kazius et al. 2005 J Med Chem 48:312-320 — 13 principal mechanistic
    classes of mutagens in the Salmonella Ames assay (TA98, TA100, TA1535, TA1537).
    Benigni & Bossa 2011 Chem Rev 111:2507-2536 — expanded alert set.

    Returns ames_positive (bool), ames_probability (0–1), and the list of
    structural alerts triggered. Probability is an estimate from alert severity;
    ICH S2(R1) requires confirmatory experimental testing regardless.
    '''
    try:
        from rdkit import Chem
    except ImportError:
        return {}

    # (alert_name, SMARTS, severity_weight)
    # Weights derived from Kazius 2005 Table 1 sensitivity/specificity data
    ALERTS = [
        ("n_nitroso",               "[NX3]-N=O",                                   0.90),
        ("aromatic_nitro",          "c[N+](=O)[O-]",                               0.85),
        ("primary_aromatic_amine",  "[NH2]c",                                       0.80),
        ("organic_azide",           "[NX2]=[NX2+]=[NX1-]",                         0.80),
        ("azo_aromatic",            "c-[NX2]=[NX2]-c",                             0.70),
        ("alkyl_nitrite",           "[OX2][NX2]=O",                                 0.65),
        ("alkylating_epoxide",      "[O;r3]",                                       0.65),
        ("haloacetyl",              "[F,Cl,Br,I][CH2][CX3]=O",                      0.60),
        ("furan",                   "c1ccoc1",                                      0.60),
        ("beta_lactone",            "C1(=O)CCO1",                                  0.60),
        ("michael_acceptor",        "[CX3]=[CX3][CX3](=O)[#6]",                    0.55),
        ("hydroxamic_acid",         "[CX3](=O)[NX3][OH]",                           0.55),
        ("alpha_haloketone",        "[F,Cl,Br,I][CX4][CX3](=O)",                   0.55),
    ]

    items = smiles_input if isinstance(smiles_input, list) else [smiles_input]
    triggered = []
    alert_lookup = {name: w for name, _s, w in ALERTS}

    for smiles in items:
        smiles = str(smiles).strip()
        if not smiles:
            continue
        mol = Chem.MolFromSmiles(smiles)
        if mol is None:
            continue
        for name, smarts, _w in ALERTS:
            if name in triggered:
                continue
            try:
                pattern = Chem.MolFromSmarts(smarts)
                if pattern and mol.HasSubstructMatch(pattern):
                    triggered.append(name)
            except Exception:
                continue

    if not triggered:
        return {
            "ames_positive": False,
            "ames_probability": 0.10,
            "structural_alerts": [],
            "n_alerts_triggered": 0,
            "ames_method": "kazius_structural_alerts",
        }

    max_w = max(alert_lookup.get(a, 0.5) for a in triggered)
    prob = round(min(0.95, max_w + 0.05 * (len(triggered) - 1)), 3)
    return {
        "ames_positive": True,
        "ames_probability": prob,
        "structural_alerts": triggered,
        "n_alerts_triggered": len(triggered),
        "ames_method": "kazius_structural_alerts",
    }


def predict_admet_properties(smiles_list, ADMET_model_type="MPNN"):
    # ── Phase 1: RDKit structural safety ────────────────────────────────────
    structural_safety = compute_structural_safety(smiles_list)

    # ── Phase 1b: Ames mutagenicity structural alerts ────────────────────────
    ames_result = compute_ames_alerts(smiles_list)

    items = smiles_list if isinstance(smiles_list, list) else [smiles_list]
    per_compound = structural_safety.pop("per_compound", None)

    tox = dict(structural_safety)
    if ames_result:
        tox["ames_positive"] = ames_result.get("ames_positive", False)
        tox["ames_probability"] = ames_result.get("ames_probability", 0.10)
        tox["ames_structural_alerts"] = ames_result.get("structural_alerts", [])
        tox["ames_method"] = ames_result.get("ames_method", "kazius_structural_alerts")

    tox_report = {
        "compounds_assessed": len(items),
        "model_type": ADMET_model_type,
        "estimation_method": "rdkit_descriptors",
        "toxicity": tox,
    }
    if per_compound:
        tox_report["per_compound"] = per_compound

    research_log = ""

    # ── Phase 2: DeepPurpose ADMET (optional) ───────────────────────────────
    try:
        from DeepPurpose import CompoundPred, utils

        available_model_types = ["MPNN", "CNN", "Morgan"]
        if ADMET_model_type not in available_model_types:
            raise ValueError(
                f"Invalid ADMET model type '{ADMET_model_type}'. "
                f"Available: {', '.join(available_model_types)}"
            )

        model_ADMETs = {}
        tasks = [
            "AqSolDB", "Caco2", "HIA", "Pgp_inhibitor", "Bioavailability",
            "BBB_MolNet", "PPBR", "CYP2C19", "CYP2D6", "CYP3A4", "CYP1A2",
            "CYP2C9", "ClinTox", "Lipo_AZ", "Half_life_eDrug3D",
            "Clearance_eDrug3D",
        ]
        for task in tasks:
            model_ADMETs[task + "_" + ADMET_model_type + "_model"] = (
                CompoundPred.model_pretrained(
                    model=task + "_" + ADMET_model_type + "_model"
                )
            )

        def ADMET_pred(drug, task, unit):
            model = model_ADMETs[task + "_" + ADMET_model_type + "_model"]
            X_pred = utils.data_process(
                X_drug=[drug], y=[0],
                drug_encoding=ADMET_model_type,
                split_method="no_split",
            )
            y_pred = float(model.predict(X_pred)[0])
            if unit == "%":
                y_pred = y_pred * 100
            return y_pred, f"{y_pred:.2f} {unit}"

        clintox_values = []
        research_log = "Research Log for ADMET Predictions:\\n"
        research_log += "-------------------------------------\\n"

        for smiles in items:
            research_log += f"\\nCompound SMILES: {smiles}\\n"
            research_log += "Predicted ADMET properties:\\n"

            _, txt = ADMET_pred(smiles, "AqSolDB", "log mol/L")
            research_log += f"- Solubility: {txt}\\n"
            _, txt = ADMET_pred(smiles, "Lipo_AZ", "(log-ratio)")
            research_log += f"- Lipophilicity: {txt}\\n"
            _, txt = ADMET_pred(smiles, "Caco2", "cm/s")
            research_log += f"- Absorption (Caco-2 permeability): {txt}\\n"
            _, txt = ADMET_pred(smiles, "HIA", "%")
            research_log += f"- Absorption (HIA): {txt}\\n"
            _, txt = ADMET_pred(smiles, "Pgp_inhibitor", "%")
            research_log += f"- Absorption (Pgp Inhibitor): {txt}\\n"
            _, txt = ADMET_pred(smiles, "Bioavailability", "%")
            research_log += f"- Absorption (Bioavailability): {txt}\\n"
            _, txt = ADMET_pred(smiles, "BBB_MolNet", "%")
            research_log += f"- Distribution (BBB permeation): {txt}\\n"
            _, txt = ADMET_pred(smiles, "PPBR", "%")
            research_log += f"- Distribution (PPBR): {txt}\\n"
            _, txt = ADMET_pred(smiles, "CYP2C19", "%")
            research_log += f"- Metabolism (CYP2C19): {txt}\\n"
            _, txt = ADMET_pred(smiles, "CYP2D6", "%")
            research_log += f"- Metabolism (CYP2D6): {txt}\\n"
            _, txt = ADMET_pred(smiles, "CYP3A4", "%")
            research_log += f"- Metabolism (CYP3A4): {txt}\\n"
            _, txt = ADMET_pred(smiles, "CYP1A2", "%")
            research_log += f"- Metabolism (CYP1A2): {txt}\\n"
            _, txt = ADMET_pred(smiles, "CYP2C9", "%")
            research_log += f"- Metabolism (CYP2C9): {txt}\\n"
            _, txt = ADMET_pred(smiles, "Half_life_eDrug3D", "h")
            research_log += f"- Excretion (Half-life): {txt}\\n"
            _, txt = ADMET_pred(smiles, "Clearance_eDrug3D", "mL/min/kg")
            research_log += f"- Excretion (Clearance): {txt}\\n"

            clintox_val, txt = ADMET_pred(smiles, "ClinTox", "%")
            clintox_prob = clintox_val / 100.0
            clintox_values.append(clintox_prob)
            research_log += f"- Clinical Toxicity: {txt}\\n"
            research_log += "-------------------------------------\\n"

        # Update toxicity report with DeepPurpose ClinTox predictions
        if clintox_values:
            max_clintox = max(clintox_values)
            tox_report["toxicity"]["clintox_probability"] = round(max_clintox, 3)
            tox_report["estimation_method"] = "rdkit_descriptors+deeppurpose"
            # Override DILI risk if ClinTox signal is stronger
            if max_clintox >= 0.80:
                tox_report["toxicity"]["dili_risk"] = "high"
                tox_report["toxicity"]["dili_probability"] = round(max_clintox, 3)
            elif max_clintox >= 0.50:
                if tox_report["toxicity"].get("dili_risk") != "high":
                    tox_report["toxicity"]["dili_risk"] = "medium"
                    tox_report["toxicity"]["dili_probability"] = round(max_clintox * 0.85, 3)

    except ImportError:
        research_log = (
            "DeepPurpose not available in this environment.\\n"
            "Structural safety estimates (RDKit descriptor-based heuristics) are used.\\n"
            "Install DeepPurpose for full ADMET predictions including ClinTox.\\n"
        )
    except Exception as dp_err:
        research_log = (
            f"DeepPurpose error: {dp_err}\\n"
            "Falling back to RDKit structural estimates.\\n"
        )

    # ── Always write toxicity_report.json ───────────────────────────────────
    with open("toxicity_report.json", "w") as f:
        json.dump(tox_report, f, indent=2, default=str)

    return research_log if research_log else "Structural safety estimates computed. See toxicity_report.json."


# ── Execute ──────────────────────────────────────────────────────────────────
try:
    result = predict_admet_properties(
        smiles_list=auto_convert(os.environ.get("PARAM_SMILES_LIST", "")),
        ADMET_model_type=auto_convert(os.environ.get("PARAM_ADMET_MODEL_TYPE", "MPNN")),
    )
    success = True
    error_msg = None
except Exception as e:
    result = None
    success = False
    error_msg = str(e)

# ── Save main results JSON ───────────────────────────────────────────────────
output_data = {
    "success": success,
    "function": "predict_admet_properties",
    "domain": "pharmacology",
}
if success:
    output_data["result"] = str(result) if not isinstance(result, (dict, list)) else result
else:
    output_data["error"] = error_msg

with open("predict_admet_properties_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# ── Save human-readable output ───────────────────────────────────────────────
NL = chr(10)
with open("predict_admet_properties_output.txt", "w") as f:
    f.write("Biomni: Predict ADMET Properties" + NL)
    f.write("=" * 60 + NL + NL)
    if success:
        if isinstance(result, str):
            f.write(result)
        elif isinstance(result, dict):
            for key, value in result.items():
                f.write(f"{key}: {value}" + NL)
        else:
            f.write(str(result))
    else:
        f.write(f"ERROR: {error_msg}" + NL)

# ── Guarantee toxicity_report.json always exists ─────────────────────────────
if not os.path.exists("toxicity_report.json"):
    with open("toxicity_report.json", "w") as f:
        json.dump({
            "compounds_assessed": 0,
            "toxicity": {},
            "note": "No structural data available — check SMILES input",
        }, f, indent=2)

if not success:
    exit(1)
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | cut -d' ' -f2)
        biomni_function: "predict_admet_properties"
    END_VERSIONS
    """
}

workflow PREDICT_ADMET_PROPERTIES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta) ]

    main:
    PREDICT_ADMET_PROPERTIES(ch_input)

    emit:
    results        = PREDICT_ADMET_PROPERTIES.out.results
    output         = PREDICT_ADMET_PROPERTIES.out.output
    toxicity_report = PREDICT_ADMET_PROPERTIES.out.toxicity_report
    versions       = PREDICT_ADMET_PROPERTIES.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    PREDICT_ADMET_PROPERTIES_WORKFLOW(ch_input)

    PREDICT_ADMET_PROPERTIES_WORKFLOW.out.output.view { "Output: $it" }
}
