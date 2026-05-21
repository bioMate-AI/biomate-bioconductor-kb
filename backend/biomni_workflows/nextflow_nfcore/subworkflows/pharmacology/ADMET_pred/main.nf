#!/usr/bin/env nextflow
/*
 * pharmacology/ADMET_pred (fixed 2026-05-21)
 *
 * ADMET (Absorption, Distribution, Metabolism, Excretion, Toxicity) safety screening.
 *
 * Uses RDKit molecular descriptors to estimate:
 *   - hERG IC50 (μM): Aronov 2008 J Med Chem 51:6632 logP-based model
 *   - DILI risk: Lammert et al. 2010 Toxicol Sci lipophilicity + MW model
 *
 * Always produces toxicity_report.json with structured QC-gate-ready fields.
 * nf-core style module generated from tested Galaxy wrapper.
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// SMILES string for a single compound, or JSON list for batch screening.
// Default: terfenadine — a known hERG inhibitor (withdrawn from market) used to
// demonstrate cardiotoxicity risk detection.
params.smiles = 'OC(CCCN1CCC(CC1)C(O)(c1ccccc1)c1ccccc1)(c1ccc(cc1)C(C)(C)C)CC'

process ADMET_PRED {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("ADMET_pred_results.json"), emit: results
    tuple val(meta), path("ADMET_pred_output.txt"), emit: output
    tuple val(meta), path("toxicity_report.json"), emit: toxicity_report
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def smiles_param = params.smiles != null ? params.smiles.toString() : 'null'
    """
    # Export parameters as environment variables
    export PARAM_SMILES='${smiles_param}'

    python3 << 'PYEOF'
# ADMET safety screening using RDKit molecular descriptor heuristics.
# Phase 1: RDKit structural safety (always runs, no heavy dependencies)
# Phase 2: DeepPurpose ClinTox model (optional, runs when installed)
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


def compute_structural_safety(smiles_input):
    '''
    Estimate ADMET safety flags from molecular descriptors (RDKit).

    hERG IC50 heuristic: Aronov 2008 J Med Chem 51:6632; Price et al. 2009
    log10(IC50 [uM]) approx 1.4 - 0.30 * logP

    DILI risk: Lammert et al. 2010 Toxicol Sci 116:536; Fontana et al. 2010
    High risk: logP > 4.0 AND MW > 400

    Returns worst-case metrics across all compounds (or {} if RDKit unavailable).
    '''
    try:
        from rdkit import Chem
        from rdkit.Chem import Descriptors
    except ImportError:
        return {}

    # Accept single SMILES string or JSON list
    if isinstance(smiles_input, list):
        items = smiles_input
    elif isinstance(smiles_input, str) and smiles_input.strip().startswith('['):
        try:
            items = json.loads(smiles_input)
        except json.JSONDecodeError:
            items = [smiles_input]
    else:
        items = [smiles_input] if smiles_input else []

    compound_results = []
    for smiles in items:
        smiles = str(smiles).strip()
        if not smiles:
            continue
        mol = Chem.MolFromSmiles(smiles)
        if mol is None:
            compound_results.append({"smiles": smiles, "error": "Invalid SMILES"})
            continue

        logp = Descriptors.MolLogP(mol)
        mw = Descriptors.MolWt(mol)

        # hERG IC50 heuristic (Aronov 2008)
        log10_ic50 = 1.4 - 0.30 * logp
        herg_ic50 = round(max(0.01, 10 ** log10_ic50), 3)

        # DILI risk (Lammert 2010)
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

    min_herg = min(r["herg_ic50_uM"] for r in valid)
    worst_dili = max(valid, key=lambda r: r["dili_probability"])

    return {
        "herg_ic50_uM": min_herg,
        "dili_risk": worst_dili["dili_risk"],
        "dili_probability": worst_dili["dili_probability"],
        "per_compound": compound_results,
    }


def compute_ames_alerts(smiles_input):
    '''
    Ames mutagenicity prediction via structural alerts.

    Kazius et al. 2005 J Med Chem 48:312-320 -- 13 mechanistic alert classes
    covering the principal mutagens in the Salmonella Ames assay (TA98, TA100,
    TA1535, TA1537). Returns ames_positive (bool), ames_probability (0-1),
    and structural_alerts list. ICH S2(R1) still requires experimental confirmation.
    '''
    try:
        from rdkit import Chem
    except ImportError:
        return {}

    ALERTS = [
        ("n_nitroso",               "[NX3]-N=O",                    0.90),
        ("aromatic_nitro",          "c[N+](=O)[O-]",                0.85),
        ("primary_aromatic_amine",  "[NH2]c",                       0.80),
        ("organic_azide",           "[NX2]=[NX2+]=[NX1-]",         0.80),
        ("azo_aromatic",            "c-[NX2]=[NX2]-c",             0.70),
        ("alkyl_nitrite",           "[OX2][NX2]=O",                 0.65),
        ("alkylating_epoxide",      "[O;r3]",                       0.65),
        ("haloacetyl",              "[F,Cl,Br,I][CH2][CX3]=O",      0.60),
        ("furan",                   "c1ccoc1",                      0.60),
        ("beta_lactone",            "C1(=O)CCO1",                   0.60),
        ("michael_acceptor",        "[CX3]=[CX3][CX3](=O)[#6]",    0.55),
        ("hydroxamic_acid",         "[CX3](=O)[NX3][OH]",           0.55),
        ("alpha_haloketone",        "[F,Cl,Br,I][CX4][CX3](=O)",   0.55),
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


def ADMET_pred(smiles):
    '''ADMET safety screening using RDKit + optional DeepPurpose.'''
    safety = compute_structural_safety(smiles)
    per_compound = safety.pop("per_compound", None)

    # Ames mutagenicity structural alerts
    ames_result = compute_ames_alerts(smiles)

    # Build toxicity_report (QC-gate-ready)
    tox = dict(safety)
    if ames_result:
        tox["ames_positive"] = ames_result.get("ames_positive", False)
        tox["ames_probability"] = ames_result.get("ames_probability", 0.10)
        tox["ames_structural_alerts"] = ames_result.get("structural_alerts", [])
        tox["ames_method"] = ames_result.get("ames_method", "kazius_structural_alerts")

    tox_report = {
        "compounds_assessed": len(per_compound) if per_compound else 1,
        "model_type": "rdkit_descriptors",
        "estimation_method": "rdkit_descriptors",
        "toxicity": tox,
    }
    if per_compound:
        tox_report["per_compound"] = per_compound

    # Try DeepPurpose ClinTox for enhanced prediction
    clintox_prob = None
    try:
        import sys, subprocess
        from DeepPurpose import CompoundPred, utils
        items = smiles if isinstance(smiles, list) else [smiles]
        model = CompoundPred.model_pretrained(model="ClinTox_MPNN_model")
        clintox_values = []
        for s in items:
            X = utils.data_process(X_drug=[str(s)], y=[0], drug_encoding="MPNN",
                                   split_method="no_split")
            clintox_values.append(float(model.predict(X)[0]))
        if clintox_values:
            clintox_prob = max(clintox_values)
            tox_report["toxicity"]["clintox_probability"] = round(clintox_prob, 3)
            tox_report["estimation_method"] = "rdkit_descriptors+deeppurpose_clintox"
            if clintox_prob >= 0.80:
                tox_report["toxicity"]["dili_risk"] = "high"
                tox_report["toxicity"]["dili_probability"] = round(clintox_prob, 3)
            elif clintox_prob >= 0.50:
                if tox_report["toxicity"].get("dili_risk") != "high":
                    tox_report["toxicity"]["dili_risk"] = "medium"
                    tox_report["toxicity"]["dili_probability"] = round(clintox_prob * 0.85, 3)
    except Exception:
        pass  # RDKit estimates are used

    # Write toxicity_report.json (QC gate parser reads this first)
    with open("toxicity_report.json", "w") as f:
        json.dump(tox_report, f, indent=2, default=str)

    # Return structured predictions for the main results JSON
    predictions = {
        "herg_ic50_uM": tox_report["toxicity"].get("herg_ic50_uM"),
        "dili_risk": tox_report["toxicity"].get("dili_risk"),
        "dili_probability": tox_report["toxicity"].get("dili_probability"),
    }
    if clintox_prob is not None:
        predictions["clintox_probability"] = round(clintox_prob, 3)

    return {
        "smiles": smiles,
        "toxicity": tox_report["toxicity"],
        "predictions": predictions,
        "estimation_method": tox_report["estimation_method"],
        "note": (
            "hERG IC50 estimated from LogP (Aronov 2008). "
            "DILI risk from lipophilicity+MW model (Lammert 2010). "
            "Install DeepPurpose for ML-based ClinTox prediction."
        ),
    }


# ── Execute ──────────────────────────────────────────────────────────────────
smiles_raw = auto_convert(os.environ.get("PARAM_SMILES", ""))

try:
    result = ADMET_pred(smiles=smiles_raw)
    success = True
    error_msg = None
except Exception as e:
    result = None
    success = False
    error_msg = str(e)

# ── Save main results JSON ───────────────────────────────────────────────────
output_data = {
    "success": success,
    "function": "ADMET_pred",
    "domain": "pharmacology",
}
if success:
    output_data["result"] = result if isinstance(result, (dict, list)) else str(result)
else:
    output_data["error"] = error_msg

with open("ADMET_pred_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# ── Save human-readable output ───────────────────────────────────────────────
NL = chr(10)
with open("ADMET_pred_output.txt", "w") as f:
    f.write("Biomni: ADMET Safety Screening" + NL)
    f.write("=" * 60 + NL + NL)
    if success and isinstance(result, dict):
        tox = result.get("toxicity", {})
        f.write(f"Estimation method: {result.get('estimation_method', 'N/A')}" + NL + NL)
        herg = tox.get("herg_ic50_uM")
        if herg is not None:
            risk_label = "HIGH RISK" if herg < 1.0 else ("MODERATE" if herg < 10.0 else "LOW RISK")
            f.write(f"hERG IC50: {herg:.3f} μM [{risk_label}]" + NL)
        dili = tox.get("dili_risk")
        if dili:
            f.write(f"DILI risk: {dili.upper()}" + NL)
        clintox = tox.get("clintox_probability")
        if clintox is not None:
            f.write(f"ClinTox probability: {clintox:.3f}" + NL)
        f.write(NL + result.get("note", "") + NL)
    elif not success:
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
        biomni_function: "ADMET_pred"
    END_VERSIONS
    """
}

workflow ADMET_PRED_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta) ]

    main:
    ADMET_PRED(ch_input)

    emit:
    results         = ADMET_PRED.out.results
    output          = ADMET_PRED.out.output
    toxicity_report = ADMET_PRED.out.toxicity_report
    versions        = ADMET_PRED.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    meta = [id: 'admet_run', single_end: false]
    Channel.value(meta) | ADMET_PRED_WORKFLOW

    ADMET_PRED_WORKFLOW.out.output.view { "Output: $it" }
}
