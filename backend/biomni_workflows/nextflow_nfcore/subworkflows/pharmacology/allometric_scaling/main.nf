#!/usr/bin/env nextflow
/*
 * pharmacology/allometric_scaling
 *
 * Scales pharmacokinetic parameters from preclinical species to human using
 * allometric regression (power law), Rule of Exponents (Mahmood), and MLP/
 * brain-weight correction factors. Predicts human CL, Vd, t½ and generates
 * first-in-human (FIH) dose recommendations (MABEL / MRSD).
 *
 * Input:  JSON array of per-species PK data + optional NOEL for FIH dose
 * Output: allometric_regression.csv, human_pk_prediction.json,
 *         fih_dose_recommendation.json
 */

nextflow.enable.dsl = 2

params.outdir           = './results'
params.species_pk_data  = '[{"species":"rat","BW_kg":0.25,"CL_mL_min_kg":12.0,"Vd_L_kg":1.8,"t_half_h":null},{"species":"dog","BW_kg":10.0,"CL_mL_min_kg":6.0,"Vd_L_kg":2.1,"t_half_h":null}]'
params.human_BW_kg      = '70'
params.correction_method = 'simple'   // simple | MLP | brain_weight
params.dose_route       = 'oral'
params.toxicokinetic_NOEL_mg_kg = 'null'

process ALLOMETRIC_SCALING {
    tag "$meta.id"
    label 'process_low'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("allometric_scaling_results.json"),    emit: results
    tuple val(meta), path("allometric_scaling_output.txt"),      emit: output
    tuple val(meta), path("allometric_regression.csv"),          emit: regression
    tuple val(meta), path("human_pk_prediction.json"),           emit: human_pk
    tuple val(meta), path("fih_dose_recommendation.json"),       emit: fih_dose
    path "versions.yml",                                         emit: versions

    script:
    """
    export PARAM_SPECIES_PK_DATA='${params.species_pk_data}'
    export PARAM_HUMAN_BW_KG='${params.human_BW_kg}'
    export PARAM_CORRECTION_METHOD='${params.correction_method}'
    export PARAM_DOSE_ROUTE='${params.dose_route}'
    export PARAM_NOEL_MG_KG='${params.toxicokinetic_NOEL_mg_kg}'

    python3 << 'PYEOF'
import json, os, math, csv, sys
import numpy as np

def auto_convert(val):
    if val is None or val in ('', 'null', 'None'): return None
    try: return float(val)
    except: return val

# ── Load params ──────────────────────────────────────────────────────────────
raw_species   = os.environ.get('PARAM_SPECIES_PK_DATA', '[]')
human_bw      = float(os.environ.get('PARAM_HUMAN_BW_KG', '70') or 70)
method        = os.environ.get('PARAM_CORRECTION_METHOD', 'simple') or 'simple'
dose_route    = os.environ.get('PARAM_DOSE_ROUTE', 'oral') or 'oral'
noel_raw      = auto_convert(os.environ.get('PARAM_NOEL_MG_KG'))

try:
    species_data = json.loads(raw_species)
except Exception as e:
    print(f"ERROR parsing species_pk_data: {e}", file=sys.stderr)
    species_data = []

# ── Brain weights and MLP per species (Mahmood 2003) ─────────────────────────
BRAIN_WEIGHTS = {'mouse':0.0004,'rat':0.002,'dog':0.072,'monkey':0.097,'human':1.35}
MLP_YEARS     = {'mouse':3.5,'rat':4.5,'dog':20,'monkey':40,'human':93}
SPECIES_BW    = {'mouse':0.02,'rat':0.25,'dog':10,'monkey':7,'human':70}

def _fill_defaults(sp):
    """Impute missing BW from species name."""
    name = sp.get('species','').lower()
    if not sp.get('BW_kg') and name in SPECIES_BW:
        sp['BW_kg'] = SPECIES_BW[name]
    # Compute t½ if missing
    cl = sp.get('CL_mL_min_kg')
    vd = sp.get('Vd_L_kg')
    if cl and vd and not sp.get('t_half_h'):
        # t½ = 0.693 * Vd(mL/kg) / CL(mL/min/kg) / 60
        sp['t_half_h'] = round(0.693 * vd * 1000 / cl / 60, 3)
    return sp

species_data = [_fill_defaults(s) for s in species_data if s.get('CL_mL_min_kg')]

def power_law_regression(bw_list, param_list):
    """Returns (a, b) for param = a * BW^b via log-log linear regression."""
    if len(bw_list) < 2:
        return None, None
    log_bw = np.log(bw_list)
    log_p  = np.log(param_list)
    var_bw = np.var(log_bw)
    if var_bw == 0:
        return None, None  # all body weights identical — regression undefined
    b = np.cov(log_bw, log_p)[0,1] / var_bw
    a = np.exp(np.mean(log_p) - b * np.mean(log_bw))
    # R²
    pred = a * np.array(bw_list)**b
    ss_res = np.sum((np.array(param_list) - pred)**2)
    ss_tot = np.sum((np.array(param_list) - np.mean(param_list))**2)
    r2 = 1 - ss_res/ss_tot if ss_tot > 0 else 1.0
    return a, b, r2

# ── Regression per PK parameter ───────────────────────────────────────────────
bw_vals = [s['BW_kg'] for s in species_data]
cl_vals = [s['CL_mL_min_kg'] for s in species_data]
vd_vals = [s['Vd_L_kg'] for s in species_data if s.get('Vd_L_kg')]
vd_bw   = [s['BW_kg']  for s in species_data if s.get('Vd_L_kg')]

results_cl = power_law_regression(bw_vals, cl_vals)
results_vd = power_law_regression(vd_bw, vd_vals) if len(vd_bw) >= 2 else (None, None, None)

a_cl, b_cl, r2_cl = results_cl if len(results_cl)==3 else (results_cl[0], results_cl[1], None)
a_vd, b_vd, r2_vd = results_vd if len(results_vd)==3 else (results_vd[0], results_vd[1], None)

# ── Correction factor for CL (Rule of Exponents, Mahmood 2003) ───────────────
# b > 0.71 → no correction; 0.55-0.70 → MLP correction; < 0.55 → brain weight
correction_applied = 'none'
if b_cl is not None:
    if method == 'MLP' or (method == 'simple' and b_cl is not None and b_cl < 0.55):
        # Apply MLP correction: multiply by (MLP_human/MLP_species_avg)
        avg_mlp = np.mean([MLP_YEARS.get(s['species'].lower(), 20) for s in species_data])
        mlp_correction = MLP_YEARS['human'] / avg_mlp
        a_cl = a_cl * mlp_correction if a_cl else a_cl
        correction_applied = f'MLP (factor={mlp_correction:.2f})'
    elif method == 'brain_weight':
        avg_bw_species = np.mean([BRAIN_WEIGHTS.get(s['species'].lower(), 0.01) for s in species_data])
        bw_correction = BRAIN_WEIGHTS['human'] / avg_bw_species
        a_cl = a_cl * bw_correction if a_cl else a_cl
        correction_applied = f'brain_weight (factor={bw_correction:.2f})'

# ── Human PK predictions ──────────────────────────────────────────────────────
human_cl   = round(a_cl * human_bw**b_cl, 3) if a_cl and b_cl else None
human_vd   = round(a_vd * human_bw**b_vd, 3) if a_vd and b_vd else None
human_thalf = round(0.693 * human_vd * 1000 / human_cl / 60, 2) if human_cl and human_vd else None

# ── FIH dose recommendation (FDA 2005 guidance) ───────────────────────────────
# MRSD = NOEL(animal) * body_weight_factor * safety_factor(1/10)
# HED = animal_dose_mg_kg * (BW_animal/BW_human)^0.33  (FDA Guidance 2005)
fih = {}
if noel_raw:
    # Use rat as primary species for MRSD if available
    primary = next((s for s in species_data if 'rat' in s['species'].lower()), species_data[0] if species_data else None)
    if primary:
        hed_factor = (primary['BW_kg'] / human_bw) ** 0.33
        hed_mg_kg  = noel_raw * hed_factor
        mrsd_mg_kg = hed_mg_kg / 10  # 10× safety factor
        mrsd_total = round(mrsd_mg_kg * human_bw, 1)
        mabel_total = round(mrsd_total / 2, 1)  # MABEL = MRSD/2 (conservative)
        fih = {
            "NOEL_animal_mg_kg": noel_raw,
            "primary_species": primary['species'],
            "HED_mg_kg": round(hed_mg_kg, 3),
            "MRSD_mg_kg": round(mrsd_mg_kg, 3),
            "MRSD_total_mg": mrsd_total,
            "MABEL_total_mg": mabel_total,
            "basis": "1/10 NOEL × HED conversion (FDA 2005 Guidance)",
            "regulatory_basis": "FDA Guidance 2005: Estimating Maximum Safe Starting Dose in Initial Clinical Trials"
        }

# ── Write outputs ──────────────────────────────────────────────────────────────
# 1. allometric_regression.csv
with open('allometric_regression.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['species','BW_kg','CL_mL_min_kg','Vd_L_kg','t_half_h'])
    for s in species_data:
        w.writerow([s.get('species',''), s.get('BW_kg',''), s.get('CL_mL_min_kg',''),
                    s.get('Vd_L_kg',''), s.get('t_half_h','')])
    # Add human prediction row
    w.writerow(['human (predicted)', human_bw, human_cl, human_vd, human_thalf])

# 2. human_pk_prediction.json
pk_pred = {
    "CL_mL_min_kg_human": human_cl,
    "Vd_L_kg_human": human_vd,
    "t_half_h_human": human_thalf,
    "prediction_method": method,
    "correction_applied": correction_applied,
    "regression_CL": {"a": round(a_cl,4) if a_cl else None, "b": round(b_cl,3) if b_cl else None, "R2": round(r2_cl,3) if r2_cl else None},
    "regression_Vd": {"a": round(a_vd,4) if a_vd else None, "b": round(b_vd,3) if b_vd else None, "R2": round(r2_vd,3) if r2_vd else None},
    "species_count": len(species_data),
    "human_BW_kg": human_bw
}
with open('human_pk_prediction.json', 'w') as f:
    json.dump(pk_pred, f, indent=2)

# 3. fih_dose_recommendation.json
if not fih:
    fih = {"note": "No NOEL provided; MRSD/MABEL not calculated", "human_CL_mL_min_kg": human_cl}
with open('fih_dose_recommendation.json', 'w') as f:
    json.dump(fih, f, indent=2)

# 4. Summary results
summary = {
    "status": "completed",
    "human_CL_mL_min_kg": human_cl,
    "human_Vd_L_kg": human_vd,
    "human_t_half_h": human_thalf,
    "correction_method": correction_applied,
    "fih_MRSD_mg": fih.get("MRSD_total_mg"),
    "fih_MABEL_mg": fih.get("MABEL_total_mg")
}
with open('allometric_scaling_results.json', 'w') as f:
    json.dump(summary, f, indent=2)

# 5. Human-readable output
lines = [
    "=== ALLOMETRIC SCALING REPORT ===",
    f"Species used: {[s['species'] for s in species_data]}",
    f"Correction method: {correction_applied}",
    "",
    "--- Human PK Predictions ---",
    f"  CL:   {human_cl} mL/min/kg",
    f"  Vd:   {human_vd} L/kg",
    f"  t½:   {human_thalf} h",
    f"  CL allometry: CL = {round(a_cl,4) if a_cl else 'N/A'} × BW^{round(b_cl,3) if b_cl else 'N/A'} (R²={round(r2_cl,3) if r2_cl else 'N/A'})",
    "",
]
if fih.get("MRSD_total_mg"):
    lines += [
        "--- First-in-Human Dose ---",
        f"  NOEL (animal): {noel_raw} mg/kg ({fih['primary_species']})",
        f"  HED:           {fih['HED_mg_kg']} mg/kg",
        f"  MRSD:          {fih['MRSD_total_mg']} mg (1/10 × HED × 70 kg)",
        f"  MABEL:         {fih['MABEL_total_mg']} mg (conservative starting dose)",
    ]
with open('allometric_scaling_output.txt', 'w') as f:
    f.write('\n'.join(lines))

print('\n'.join(lines))

PYEOF

    cat versions.yml 2>/dev/null || cat << 'EOF' > versions.yml
allometric_scaling:
  python: "3.10"
  numpy: ">=1.24"
  scipy: ">=1.10"
EOF
    """
}

workflow ALLOMETRIC_SCALING_WORKFLOW {
    take: meta_ch
    main:
        ALLOMETRIC_SCALING(meta_ch)
    emit:
        results  = ALLOMETRIC_SCALING.out.results
        human_pk = ALLOMETRIC_SCALING.out.human_pk
        fih_dose = ALLOMETRIC_SCALING.out.fih_dose
}

workflow {
    meta = [id: 'allometric_scaling_run', single_end: false]
    Channel.value(meta) | ALLOMETRIC_SCALING_WORKFLOW
}
