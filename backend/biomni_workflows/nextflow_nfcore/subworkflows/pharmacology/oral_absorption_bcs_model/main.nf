#!/usr/bin/env nextflow
/*
 * pharmacology/oral_absorption_bcs_model
 *
 * BCS classification + oral absorption / dissolution modeling.
 * Predicts solubility (ESOL / Ali model), Caco-2 permeability (QSAR),
 * BCS class, dissolution profile (first-order kinetics), and oral
 * bioavailability (F%). Recommends formulation strategy.
 *
 * References:
 *   - ESOL: Delaney, J Chem Inf Comput Sci 2004
 *   - Caco-2 QSAR: Hou et al. J Chem Inf Model 2004
 *   - BCS: FDA 2017 Guidance on Waiver of In Vivo Bioavailability Studies
 *
 * Input:  SMILES, dose_mg (required), optional measured solubility/Caco-2
 * Output: bcs_classification.json, dissolution_profile.csv,
 *         pk_predictions.csv, formulation_recommendation.json
 */

nextflow.enable.dsl = 2

params.outdir                  = './results'
params.smiles_list             = '["CC(=O)OC1=CC=CC=C1C(=O)O"]'  // aspirin
params.dose_mg                 = '500'
params.measured_solubility_ugmL = 'null'
params.measured_Caco2_cm_s     = 'null'
params.pKa                     = 'null'
params.fed_fasted               = 'both'
params.formulation_type        = 'free_base'

process ORAL_ABSORPTION_BCS {
    tag "$meta.id"
    label 'process_low'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("oral_absorption_results.json"),      emit: results
    tuple val(meta), path("oral_absorption_output.txt"),        emit: output
    tuple val(meta), path("bcs_classification.json"),           emit: bcs
    tuple val(meta), path("dissolution_profile.csv"),           emit: dissolution
    tuple val(meta), path("pk_predictions.csv"),                emit: pk
    tuple val(meta), path("formulation_recommendation.json"),   emit: formulation
    path "versions.yml",                                        emit: versions

    script:
    """
    export PARAM_SMILES_LIST='${params.smiles_list}'
    export PARAM_DOSE_MG='${params.dose_mg}'
    export PARAM_SOL_UG_ML='${params.measured_solubility_ugmL}'
    export PARAM_CACO2='${params.measured_Caco2_cm_s}'
    export PARAM_PKA='${params.pKa}'
    export PARAM_FED_FASTED='${params.fed_fasted}'
    export PARAM_FORMULATION='${params.formulation_type}'

    python3 << 'PYEOF'
import json, os, csv, sys, math
import numpy as np
from rdkit import Chem
from rdkit.Chem import Descriptors, rdMolDescriptors, Crippen

def auto_convert(v):
    if v in (None,'','null','None'): return None
    try: return float(v)
    except: return v

def parse_smiles_input(raw):
    raw = raw.strip()
    if raw.startswith('['):
        try:
            lst = json.loads(raw)
            return [(str(i+1), s) for i, s in enumerate(lst)]
        except: pass
    return [('1', raw)]

# ── ESOL solubility model (Delaney 2004) ─────────────────────────────────────
def esol_logS(mol):
    """
    Predicted log10(solubility in mol/L).
    ESOL: logS = 0.16 - 0.63*cLogP - 0.0062*MW + 0.066*RingCount - 0.74*aromaticProportion
    """
    mw    = Descriptors.MolWt(mol)
    logp  = Crippen.MolLogP(mol)
    rings = rdMolDescriptors.CalcNumRings(mol)
    aro_atoms = sum(1 for a in mol.GetAromaticAtoms())
    total_atoms = mol.GetNumHeavyAtoms()
    aro_prop = aro_atoms / total_atoms if total_atoms > 0 else 0
    logS = 0.16 - 0.63*logp - 0.0062*mw + 0.066*rings - 0.74*aro_prop
    return logS

def logS_to_ugmL(logS, mw):
    solubility_mol_L = 10**logS
    return solubility_mol_L * mw * 1000  # µg/mL

# ── Caco-2 QSAR (simplified Hou et al. model) ────────────────────────────────
def predict_caco2(mol):
    """
    Simplified Caco-2 Papp prediction (×10⁻⁶ cm/s).
    Based on: logPapp = -4.6 + 0.11*logP - 0.012*TPSA - 0.26*HBD
    Rule-based: HIGH > 10e-6, MED 2-10e-6, LOW < 2e-6
    """
    logp  = Crippen.MolLogP(mol)
    tpsa  = rdMolDescriptors.CalcTPSA(mol)
    hbd   = rdMolDescriptors.CalcNumHBD(mol)
    mw    = Descriptors.MolWt(mol)

    log_papp = -4.6 + 0.11*logp - 0.012*tpsa - 0.26*hbd - 0.003*mw
    papp = 10**(log_papp) * 1e6  # in units of ×10⁻⁶ cm/s
    papp = max(0.01, min(papp, 50))  # clamp to physiological range
    return round(papp, 2)

def bcs_classify(sol_ugmL, papp_cm_s, mw, dose_mg):
    """
    BCS classification:
    - High solubility: dose/vol ≤ 250 mL @ pH 1-7.5 → need sol_mg/250 ≤ dose_mg/250
    - High permeability: Papp > 2×10⁻⁶ cm/s (FDA Guidance 2017)
    """
    # High solubility: sol_mg/mL × 250 mL ≥ dose_mg
    sol_mgmL = sol_ugmL / 1000
    high_sol = (sol_mgmL * 250) >= dose_mg

    # High permeability: Papp ≥ 2 × 10⁻⁶ cm/s (FDA threshold)
    high_perm = papp_cm_s >= 2.0

    if high_sol and high_perm:   return 'I',   'High Sol + High Perm', 'dissolution_not_limiting'
    if not high_sol and high_perm: return 'II',  'Low Sol + High Perm',  'dissolution_rate_limiting'
    if high_sol and not high_perm: return 'III', 'High Sol + Low Perm',  'permeability_limiting'
    return 'IV', 'Low Sol + Low Perm', 'both_limiting'

def dissolution_profile(sol_ugmL, dose_mg, perm_class, fed_fasted='both', formulation='free_base'):
    """First-order dissolution model in GI tract (simplified Wagner model)."""
    times = list(range(0, 241, 15))  # 0-240 min in 15-min steps

    # Dissolution rate constant (k_d) depends on solubility and formulation
    k_d_base = 0.005 * (sol_ugmL / 100)  # higher sol → faster dissolution
    k_d_fasted = k_d_base * 0.8
    k_d_fed    = k_d_base * 1.3

    # Absorption rate constant
    k_a = {'HIGH': 0.04, 'MEDIUM': 0.02, 'LOW': 0.005}.get(perm_class, 0.02)

    def profile(k_d):
        dissolved = []
        dose_remaining = 100.0  # % of dose
        absorbed_pct = 0.0
        for _ in times:
            diss_rate = k_d * dose_remaining
            abs_rate  = k_a * max(0, dissolved[-1] if dissolved else 0)
            dose_remaining = max(0, dose_remaining - diss_rate * 15)
            absorbed_pct   = min(100, absorbed_pct + abs_rate * 15)
            dissolved.append(min(100, 100 - dose_remaining))
        return dissolved, absorbed_pct

    d_fasted, f_fasted = profile(k_d_fasted)
    d_fed,    f_fed    = profile(k_d_fed)
    return times, d_fasted, d_fed, round(f_fasted, 1), round(f_fed, 1)

def formulation_recommendation(bcs_class, sol_ugmL, logp, f_pct_fasted):
    recs = {
        'I':   ('conventional_tablet', 'BCS I: standard immediate-release formulation; biowaiver eligible'),
        'II':  ('amorphous_dispersion_or_salt', f'BCS II: {("lipid-based formulation" if logp>4 else "amorphous spray-dried dispersion (ASD)")}; solubility enhancement required'),
        'III': ('plain_solution_or_HPC_film', 'BCS III: permeability-limited; consider absorption enhancers or tight-junction modulators'),
        'IV':  ('specialized_delivery', 'BCS IV: both limiting; nanoparticle or self-emulsifying drug delivery system (SEDDS) needed'),
    }
    form, rationale = recs.get(bcs_class, ('unknown',''))
    if bcs_class == 'II' and logp > 4.5:
        form = 'lipid_based_formulation'
    if f_pct_fasted < 20 and bcs_class in ('II','IV'):
        rationale += f'; current F estimate {f_pct_fasted}% is too low — ASD predicted to improve to ~{min(80,f_pct_fasted*3)}%'
    return form, rationale

# ── Process ───────────────────────────────────────────────────────────────────
raw_smiles = os.environ.get('PARAM_SMILES_LIST','["C"]')
dose_mg    = auto_convert(os.environ.get('PARAM_DOSE_MG')) or 100.0
sol_in     = auto_convert(os.environ.get('PARAM_SOL_UG_ML'))
caco2_in   = auto_convert(os.environ.get('PARAM_CACO2'))
fed_fasted = os.environ.get('PARAM_FED_FASTED','both')
formulation= os.environ.get('PARAM_FORMULATION','free_base')

smiles_pairs = parse_smiles_input(raw_smiles)
all_results = []
diss_rows   = [['compound','time_min','dissolved_pct_fasted','dissolved_pct_fed']]
pk_rows     = [['compound','BCS_class','F_pct_fasted','F_pct_fed','Caco2_papp_1e6_cm_s','solubility_ugmL']]

for cid, smi in smiles_pairs:
    mol = Chem.MolFromSmiles(smi) if smi else None
    if mol is None:
        print(f"WARNING: invalid SMILES {cid}", file=sys.stderr); continue

    mw    = Descriptors.MolWt(mol)
    logp  = Crippen.MolLogP(mol)
    tpsa  = rdMolDescriptors.CalcTPSA(mol)

    # Solubility
    logS = esol_logS(mol)
    sol_pred = logS_to_ugmL(logS, mw)
    sol_used = sol_in if sol_in is not None else sol_pred

    # Caco-2
    papp_pred = predict_caco2(mol)
    papp_used = caco2_in if caco2_in is not None else papp_pred
    perm_class = 'HIGH' if papp_used >= 10 else 'MEDIUM' if papp_used >= 2 else 'LOW'

    # BCS
    bcs_class, bcs_desc, limiting = bcs_classify(sol_used, papp_used, mw, dose_mg)

    # Dissolution
    times, d_fasted, d_fed, f_fast, f_fed = dissolution_profile(sol_used, dose_mg, perm_class, fed_fasted, formulation)
    for t, df, dfed in zip(times, d_fasted, d_fed):
        diss_rows.append([cid, t, round(df,1), round(dfed,1)])

    pk_rows.append([cid, bcs_class, f_fast, f_fed, papp_used, round(sol_used,1)])

    form, form_rationale = formulation_recommendation(bcs_class, sol_used, logp, f_fast)

    res = {
        'compound': cid, 'SMILES': smi,
        'bcs_class': bcs_class, 'bcs_description': bcs_desc,
        'absorption_limiting_step': limiting,
        'MW': round(mw,1), 'LogP': round(logp,2), 'TPSA': round(tpsa,1),
        'solubility_ugmL': round(sol_used,1),
        'solubility_source': 'measured' if sol_in else 'ESOL_predicted',
        'Caco2_papp': papp_used,
        'Caco2_source': 'measured' if caco2_in else 'QSAR_predicted',
        'F_pct_fasted': f_fast, 'F_pct_fed': f_fed,
        'formulation_recommended': form,
        'formulation_rationale': form_rationale
    }
    all_results.append(res)

# Write outputs
bcs_out = all_results[0] if len(all_results)==1 else all_results
with open('bcs_classification.json','w') as f:
    json.dump(bcs_out, f, indent=2)

with open('dissolution_profile.csv','w',newline='') as f:
    w = csv.writer(f); w.writerows(diss_rows)

with open('pk_predictions.csv','w',newline='') as f:
    w = csv.writer(f); w.writerows(pk_rows)

form_data = [{'compound':r['compound'],'recommended':r['formulation_recommended'],'rationale':r['formulation_rationale']} for r in all_results]
with open('formulation_recommendation.json','w') as f:
    json.dump(form_data[0] if len(form_data)==1 else form_data, f, indent=2)

summary = {'status':'completed','compounds':len(all_results),'results':all_results}
with open('oral_absorption_results.json','w') as f:
    json.dump(summary, f, indent=2)

report = ["=== ORAL ABSORPTION & BCS MODEL REPORT ===",""]
for r in all_results:
    report += [f"Compound {r['compound']}:",
               f"  BCS Class {r['bcs_class']}: {r['bcs_description']}",
               f"  Solubility: {r['solubility_ugmL']} µg/mL ({r['solubility_source']})",
               f"  Caco-2 Papp: {r['Caco2_papp']} ×10⁻⁶ cm/s ({r['Caco2_source']})",
               f"  F% fasted/fed: {r['F_pct_fasted']}% / {r['F_pct_fed']}%",
               f"  Formulation: {r['formulation_recommended']}",
               f"  → {r['formulation_rationale']}", ""]
with open('oral_absorption_output.txt','w') as f:
    f.write('\n'.join(report))
print('\n'.join(report))
PYEOF

    cat << 'EOF' > versions.yml
oral_absorption_bcs_model:
  python: "3.10"
  rdkit: ">=2023.9"
  numpy: ">=1.24"
EOF
    """
}

workflow ORAL_ABSORPTION_WORKFLOW {
    take: meta_ch
    main: ORAL_ABSORPTION_BCS(meta_ch)
    emit:
        results     = ORAL_ABSORPTION_BCS.out.results
        bcs         = ORAL_ABSORPTION_BCS.out.bcs
        formulation = ORAL_ABSORPTION_BCS.out.formulation
}

workflow {
    meta = [id: 'oral_absorption_run', single_end: false]
    Channel.value(meta) | ORAL_ABSORPTION_WORKFLOW
}
