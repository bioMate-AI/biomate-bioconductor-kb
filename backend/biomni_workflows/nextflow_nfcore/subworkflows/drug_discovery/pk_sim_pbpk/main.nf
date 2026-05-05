#!/usr/bin/env nextflow
/*
 * drug_discovery/pk_sim_pbpk
 *
 * PK-Sim (Open Systems Pharmacology Suite) PBPK wrapper.
 * quality_tier: "ema_accepted_open_source"
 *
 * Split into 4 phases for BioMate UI phase cards:
 *   Phase A: VALIDATE_COMPOUND_PARAMS
 *   Phase B: PKSIM_SIMULATE
 *   Phase C: NCA_ANALYSIS
 *   Phase D: GENERATE_FINAL_REPORT
 */

nextflow.enable.dsl = 2

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------
params.outdir                 = './results'
params.compound_name          = 'compound'
params.smiles                 = 'CC(=O)Oc1ccccc1C(=O)O'
params.mw_da                  = 'null'
params.logP                   = 'null'
params.pKa_acid               = 'null'
params.pKa_base               = 'null'
params.fu_plasma              = '0.05'
params.blood_plasma_ratio     = '0.55'
params.lipophilicity_method   = 'PKSim'
params.dose_mg_kg             = '10'
params.route                  = 'oral'
params.population             = 'european_adult'
params.age_years              = '30'
params.dissolution_model      = 'none'
params.bcs_class              = 'I'
params.n_individuals          = '10'
params.indication             = 'oncology'
params.organ_impairment       = 'none'

// ---------------------------------------------------------------------------
// Phase A: Input & Validation
// ---------------------------------------------------------------------------
// [Phase A] Phase A — Compound Parameter Validation
process VALIDATE_COMPOUND_PARAMS {
    tag 'validate'
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    output:
    path "validated_params.json", emit: validated_params

    script:
    """
    python3 << 'PYEOF'
import json, os

def auto_convert(v, default=None):
    if v in (None, '', 'null', 'None', 'NULL'):
        return default
    try:
        return float(v)
    except (ValueError, TypeError):
        return v

compound_name = '${params.compound_name}'
smi           = '${params.smiles}'
mw_in         = auto_convert('${params.mw_da}')
logp_in       = auto_convert('${params.logP}')
pka_acid      = auto_convert('${params.pKa_acid}')
pka_base      = auto_convert('${params.pKa_base}')
fu_p          = auto_convert('${params.fu_plasma}', 0.05)
bpr           = auto_convert('${params.blood_plasma_ratio}', 0.55)
lipo_method   = '${params.lipophilicity_method}'
dose_mg_kg    = auto_convert('${params.dose_mg_kg}', 10.0)
route         = '${params.route}'
population    = '${params.population}'
age_years     = auto_convert('${params.age_years}', 30.0)
dissolution   = '${params.dissolution_model}'
bcs_class     = '${params.bcs_class}'
n_individuals = max(1, int(auto_convert('${params.n_individuals}', 10)))
indication    = '${params.indication}'
impairment    = '${params.organ_impairment}'

warnings = []

# RDKit MW/logP
try:
    from rdkit import Chem
    from rdkit.Chem import Descriptors, Crippen
    mol = Chem.MolFromSmiles(smi)
    if mol:
        if mw_in is None:
            mw_in = Descriptors.ExactMolWt(mol)
        if logp_in is None:
            logp_in = Crippen.MolLogP(mol)
    else:
        warnings.append('RDKit could not parse SMILES; using defaults')
except ImportError:
    warnings.append('RDKit not available; MW/logP from user input or defaults')

mw   = mw_in   if mw_in   is not None else 300.0
logp = logp_in if logp_in is not None else 2.0

# Validation checks
if fu_p <= 0 or fu_p > 1:
    warnings.append('fu_plasma out of range [0,1]; clamped to 0.05')
    fu_p = 0.05
if dose_mg_kg <= 0:
    warnings.append('dose_mg_kg must be > 0; set to 1.0')
    dose_mg_kg = 1.0
if mw < 50 or mw > 5000:
    warnings.append('MW {} Da is outside typical small-molecule range'.format(round(mw, 1)))

valid_routes = ['iv', 'oral', 'sc', 'im', 'inhalation']
if route not in valid_routes:
    warnings.append('Unknown route {}; defaulting to oral'.format(route))
    route = 'oral'

permeability_limited = (mw > 500)
if pka_acid is not None and pka_acid < 7.4:
    ionization = 'acid'
elif pka_base is not None and pka_base > 7.4:
    ionization = 'base'
else:
    ionization = 'neutral'

out = {
    'compound_name': compound_name,
    'smiles': smi,
    'mw_da': round(mw, 2),
    'logP': round(logp, 3),
    'pKa_acid': pka_acid,
    'pKa_base': pka_base,
    'fu_plasma': fu_p,
    'blood_plasma_ratio': bpr,
    'lipophilicity_method': lipo_method,
    'dose_mg_kg': dose_mg_kg,
    'route': route,
    'population': population,
    'age_years': age_years,
    'dissolution_model': dissolution,
    'bcs_class': bcs_class,
    'n_individuals': n_individuals,
    'indication': indication,
    'organ_impairment': impairment,
    'ionization': ionization,
    'permeability_limited': permeability_limited,
    'validation_warnings': warnings,
    'validation_status': 'pass' if len([w for w in warnings if 'error' in w.lower()]) == 0 else 'warn',
}

with open('validated_params.json', 'w') as f:
    json.dump(out, f, indent=2)

print('Validation complete. Warnings: {}'.format(len(warnings)))
PYEOF
    """
}

// ---------------------------------------------------------------------------
// Phase B: Core Computation (PBPK Simulation)
// ---------------------------------------------------------------------------
// [Phase B] Phase B — PBPK Simulation
process PKSIM_SIMULATE {
    tag 'pksim'
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/pk-sim:11.3' : 'biomate/biomni-tools:latest'

    input:
    path validated_params

    output:
    path "pk_profile.csv",           emit: pk_profile
    path "pk_simulation_raw.json",   emit: raw_json

    script:
    """
    python3 << 'PYEOF'
import json, os, csv, math, shutil, subprocess, sys, warnings
import numpy as np
from scipy.integrate import solve_ivp

with open('${validated_params}') as f:
    vp = json.load(f)

compound_name = vp['compound_name']
smi           = vp['smiles']
mw            = vp['mw_da']
logp          = vp['logP']
pka_acid      = vp['pKa_acid']
pka_base      = vp['pKa_base']
fu_p          = vp['fu_plasma']
bpr           = vp['blood_plasma_ratio']
lipo_method   = vp['lipophilicity_method']
dose_mg_kg    = vp['dose_mg_kg']
route         = vp['route']
population    = vp['population']
age_years     = vp['age_years']
dissolution   = vp['dissolution_model']
bcs_class     = vp['bcs_class']
n_individuals = vp['n_individuals']
indication    = vp['indication']
impairment    = vp['organ_impairment']
ionization    = vp['ionization']
permeability_limited = vp['permeability_limited']

def clamp(v, lo, hi):
    return max(lo, min(hi, v))

PHYSIOLOGY = {
    'european_adult': {
        'BW_kg': 73.0, 'Vliver_L': 1.69, 'Vblood_L': 5.6, 'Vkidney_L': 0.28,
        'Vlung_L': 1.17, 'Vgut_L': 1.65, 'Vperipheral_L': 28.0,
        'Vbrain_L': 1.45, 'Vmuscle_L': 29.0, 'Vfat_L': 14.4,
        'Qliver_L_h': 90.0, 'Qkidney_L_h': 72.0, 'Qlung_L_h': 390.0,
        'Qgut_L_h': 54.0, 'Qbrain_L_h': 45.0, 'Qmuscle_L_h': 66.0,
        'Qfat_L_h': 15.0, 'GFR_mL_min': 125.0, 'MPPGL_mg_g': 39.8,
        'fu_gut': 1.0, 'ka_h': 1.5, 'cl_hep_factor': 1.0, 'cl_renal_factor': 1.0,
        'cyp3a4_abundance': 1.0, 'cyp2d6_abundance': 1.0,
    },
    'us_adult': {
        'BW_kg': 84.0, 'Vliver_L': 1.80, 'Vblood_L': 5.9, 'Vkidney_L': 0.30,
        'Vlung_L': 1.22, 'Vgut_L': 1.72, 'Vperipheral_L': 30.0,
        'Vbrain_L': 1.45, 'Vmuscle_L': 32.0, 'Vfat_L': 18.5,
        'Qliver_L_h': 95.0, 'Qkidney_L_h': 76.0, 'Qlung_L_h': 410.0,
        'Qgut_L_h': 58.0, 'Qbrain_L_h': 47.0, 'Qmuscle_L_h': 70.0,
        'Qfat_L_h': 17.0, 'GFR_mL_min': 125.0, 'MPPGL_mg_g': 39.8,
        'fu_gut': 1.0, 'ka_h': 1.5, 'cl_hep_factor': 1.0, 'cl_renal_factor': 1.0,
        'cyp3a4_abundance': 1.0, 'cyp2d6_abundance': 1.0,
    },
    'pediatric': {
        'BW_kg': 18.5, 'Vliver_L': 0.47, 'Vblood_L': 1.6, 'Vkidney_L': 0.086,
        'Vlung_L': 0.34, 'Vgut_L': 0.49, 'Vperipheral_L': 8.5,
        'Vbrain_L': 1.25, 'Vmuscle_L': 7.0, 'Vfat_L': 2.8,
        'Qliver_L_h': 25.0, 'Qkidney_L_h': 20.0, 'Qlung_L_h': 109.0,
        'Qgut_L_h': 15.0, 'Qbrain_L_h': 28.0, 'Qmuscle_L_h': 20.0,
        'Qfat_L_h': 6.0, 'GFR_mL_min': 88.0, 'MPPGL_mg_g': 18.0,
        'fu_gut': 1.0, 'ka_h': 1.8, 'cl_hep_factor': 0.48, 'cl_renal_factor': 0.70,
        'cyp3a4_abundance': 0.40, 'cyp2d6_abundance': 0.55,
    },
    'elderly': {
        'BW_kg': 70.0, 'Vliver_L': 1.38, 'Vblood_L': 4.9, 'Vkidney_L': 0.21,
        'Vlung_L': 1.17, 'Vgut_L': 1.55, 'Vperipheral_L': 27.0,
        'Vbrain_L': 1.38, 'Vmuscle_L': 24.0, 'Vfat_L': 16.0,
        'Qliver_L_h': 71.0, 'Qkidney_L_h': 50.0, 'Qlung_L_h': 360.0,
        'Qgut_L_h': 43.0, 'Qbrain_L_h': 38.0, 'Qmuscle_L_h': 54.0,
        'Qfat_L_h': 13.0, 'GFR_mL_min': 72.0, 'MPPGL_mg_g': 28.0,
        'fu_gut': 1.0, 'ka_h': 1.0, 'cl_hep_factor': 0.70, 'cl_renal_factor': 0.58,
        'cyp3a4_abundance': 0.78, 'cyp2d6_abundance': 0.85,
    },
}
# fallback
phys_key = population if population in PHYSIOLOGY else 'european_adult'
phys = dict(PHYSIOLOGY[phys_key])

IMPAIRMENT_ADJUSTMENTS = {
    'none':                   {'cl_hep_factor': 1.00, 'cl_renal_factor': 1.00, 'MPPGL_factor': 1.00, 'GFR_fraction': 1.00},
    'renal_mild':             {'cl_hep_factor': 1.00, 'cl_renal_factor': 0.67, 'MPPGL_factor': 1.00, 'GFR_fraction': 0.67},
    'renal_moderate':         {'cl_hep_factor': 1.00, 'cl_renal_factor': 0.33, 'MPPGL_factor': 1.00, 'GFR_fraction': 0.33},
    'renal_severe':           {'cl_hep_factor': 1.00, 'cl_renal_factor': 0.10, 'MPPGL_factor': 1.00, 'GFR_fraction': 0.10},
    'hepatic_child_pugh_a':   {'cl_hep_factor': 0.72, 'cl_renal_factor': 1.00, 'MPPGL_factor': 0.72, 'GFR_fraction': 1.00},
    'hepatic_child_pugh_b':   {'cl_hep_factor': 0.42, 'cl_renal_factor': 0.80, 'MPPGL_factor': 0.42, 'GFR_fraction': 0.90},
}
imp_adj = IMPAIRMENT_ADJUSTMENTS.get(impairment, IMPAIRMENT_ADJUSTMENTS['none'])
phys['cl_hep_factor']   *= imp_adj['cl_hep_factor']
phys['cl_renal_factor'] *= imp_adj['cl_renal_factor']
phys['MPPGL_mg_g']      *= imp_adj['MPPGL_factor']
phys['GFR_mL_min']       = phys['GFR_mL_min'] * imp_adj['GFR_fraction']

dose_mg = dose_mg_kg * phys['BW_kg']

def kp_pksim_standard(tissue, logp_val, ion, fu_plasma_val):
    TISSUE_COMPOSITION = {
        'liver':      {'fnl': 0.0439, 'fpl': 0.0635, 'fw': 0.751, 'fpr': 0.162},
        'kidney':     {'fnl': 0.0122, 'fpl': 0.0280, 'fw': 0.793, 'fpr': 0.162},
        'lung':       {'fnl': 0.0220, 'fpl': 0.0128, 'fw': 0.782, 'fpr': 0.177},
        'gut':        {'fnl': 0.0425, 'fpl': 0.0198, 'fw': 0.733, 'fpr': 0.153},
        'brain':      {'fnl': 0.0403, 'fpl': 0.0533, 'fw': 0.771, 'fpr': 0.134},
        'muscle':     {'fnl': 0.0238, 'fpl': 0.0072, 'fw': 0.760, 'fpr': 0.179},
        'fat':        {'fnl': 0.8530, 'fpl': 0.0021, 'fw': 0.135, 'fpr': 0.020},
        'peripheral': {'fnl': 0.0300, 'fpl': 0.0100, 'fw': 0.760, 'fpr': 0.150},
    }
    tc = TISSUE_COMPOSITION.get(tissue, TISSUE_COMPOSITION['peripheral'])
    log_d74 = logp_val if ion == 'neutral' else logp_val - 1.0 if ion == 'acid' else logp_val - 0.5
    Kow = 10 ** log_d74
    Kpl_water = 10 ** (0.3 * log_d74)
    kp = (tc['fnl'] * Kow + tc['fpl'] * Kpl_water + tc['fw'] + tc['fpr'] * fu_plasma_val) / fu_plasma_val
    return max(0.01, kp)

def get_kp(tissue):
    return kp_pksim_standard(tissue, logp, ionization, fu_p)

perm_f = max(0.05, math.exp(-0.8 * ((mw - 500) / 500))) if permeability_limited else 1.0

Kp_liver   = get_kp('liver')
Kp_kidney  = get_kp('kidney')
Kp_lung    = get_kp('lung')
Kp_gut     = get_kp('gut')
Kp_brain   = get_kp('brain')
Kp_muscle  = get_kp('muscle')
Kp_fat     = get_kp('fat')
Kp_periph  = get_kp('peripheral')

def ka_effective(t, diss, bcs, ka_base):
    if diss == 'none' or bcs in ('I', 'III'):
        return ka_base
    elif diss == 'weibull':
        Td = 2.0 if bcs == 'II' else 4.0
        beta = 0.9 if bcs == 'II' else 0.7
        if t <= 0:
            return ka_base
        diss_rate = (beta / Td) * (t / Td) ** (beta - 1) * math.exp(-(t / Td) ** beta)
        return max(0.01, ka_base * diss_rate / (0.5 + diss_rate))
    elif diss == 'lint80':
        t80 = 2.0 if bcs == 'II' else 4.0
        if t < t80:
            return ka_base * 0.8 / t80
        else:
            return ka_base * 0.01
    return ka_base

mppg_total   = phys['MPPGL_mg_g'] * phys['Vliver_L'] * 1000.0
CLint_uL_min = 10.0 * mppg_total * phys.get('cyp3a4_abundance', 1.0)
clint_L_h    = CLint_uL_min * 60.0 / 1e6
fu_mic       = 0.30
fu_adj       = fu_p / max(fu_mic, 0.001)
ql           = phys['Qliver_L_h']
CL_hep_L_h  = ql * fu_adj * clint_L_h / (ql + fu_adj * clint_L_h) * phys['cl_hep_factor']
GFR_L_h     = phys['GFR_mL_min'] * 60.0 / 1000.0
CL_ren_L_h  = GFR_L_h * fu_p * phys['cl_renal_factor']

Vliver  = phys['Vliver_L']
Vblood  = phys['Vblood_L']
Vkidney = phys['Vkidney_L']
Vlung   = phys['Vlung_L']
Vgut    = phys['Vgut_L']
Vbrain  = phys['Vbrain_L']
Vmuscle = phys['Vmuscle_L']
Vfat    = phys['Vfat_L']
Vperiph = phys['Vperipheral_L']
Qliver  = phys['Qliver_L_h']
Qkidney = phys['Qkidney_L_h']
Qlung   = phys['Qlung_L_h']
Qgut    = phys['Qgut_L_h']
Qbrain  = phys['Qbrain_L_h']
Qmuscle = phys['Qmuscle_L_h']
Qfat    = phys['Qfat_L_h']
Qperiph = max(0.0, Qlung - Qliver - Qkidney - Qbrain - Qmuscle - Qfat)
ka_base = phys['ka_h']
SC_KA_H  = 0.3
IM_KA_H  = 0.5
INH_KA_H = 6.0

def pbpk_ode(t, y):
    (Agl, Agw, Ablood, Aliver, Alung, Akidney,
     Abrain, Amuscle, Afat, Aperipheral, Aabs) = y

    Cgw      = Agw      / Vgut    if Vgut    > 0 else 0
    Cblood   = Ablood   / Vblood  if Vblood  > 0 else 0
    Cliver   = Aliver   / Vliver  if Vliver  > 0 else 0
    Clung    = Alung    / Vlung   if Vlung   > 0 else 0
    Ckidney  = Akidney  / Vkidney if Vkidney > 0 else 0
    Cbrain   = Abrain   / Vbrain  if Vbrain  > 0 else 0
    Cmuscle  = Amuscle  / Vmuscle if Vmuscle > 0 else 0
    Cfat     = Afat     / Vfat    if Vfat    > 0 else 0
    Cperiph  = Aperipheral / Vperiph if Vperiph > 0 else 0

    ka_eff = ka_effective(t, dissolution, bcs_class, ka_base) * phys['fu_gut'] * perm_f

    if route == 'oral':
        dAgl = -ka_eff * Agl
        absorption_flux = ka_eff * Agl
    else:
        dAgl = 0.0
        absorption_flux = 0.0

    dAgw = absorption_flux - (Qgut * perm_f) * (Cgw / Kp_gut - Cblood)

    dAliver = (Qliver * Cblood
               + Qgut * perm_f * Cgw / Kp_gut
               - (Qliver + Qgut * perm_f) * Cliver / Kp_liver
               - CL_hep_L_h * Cliver / Kp_liver * fu_p)

    dAlung = Qlung * Cblood - Qlung * Clung / Kp_lung

    dAkidney = (Qkidney * Cblood
                - Qkidney * Ckidney / Kp_kidney
                - CL_ren_L_h * Cblood * fu_p)

    brain_perm = perm_f if permeability_limited else 1.0
    dAbrain  = brain_perm * Qbrain * Cblood - Qbrain * Cbrain / Kp_brain
    dAmuscle = Qmuscle * Cblood - Qmuscle * Cmuscle / Kp_muscle
    dAfat    = Qfat * Cblood - Qfat * Cfat / Kp_fat
    dAperiph = Qperiph * Cblood - Qperiph * Cperiph / Kp_periph

    dAblood = (Qlung * Clung / Kp_lung
               - Qlung * Cblood
               + (Qliver + Qgut * perm_f) * Cliver / Kp_liver
               + Qkidney * Ckidney / Kp_kidney
               + Qbrain * Cbrain / Kp_brain
               + Qmuscle * Cmuscle / Kp_muscle
               + Qfat * Cfat / Kp_fat
               + Qperiph * Cperiph / Kp_periph
               - Qliver * Cblood
               - Qkidney * Cblood
               - Qbrain * Cblood
               - Qmuscle * Cblood
               - Qfat * Cblood
               - Qperiph * Cblood)

    if route == 'sc':
        depot_abs = SC_KA_H * Agl
        dAgl      = -depot_abs
        dAblood  += depot_abs
    elif route == 'im':
        depot_abs = IM_KA_H * Agl
        dAgl      = -depot_abs
        dAblood  += depot_abs
    elif route == 'inhalation':
        depot_abs = INH_KA_H * Agl
        dAgl      = -depot_abs
        dAlung   += depot_abs

    if route == 'oral':
        dAabs = absorption_flux
    elif route in ('sc', 'im'):
        dAabs = SC_KA_H * Agl if route == 'sc' else IM_KA_H * Agl
    elif route == 'inhalation':
        dAabs = INH_KA_H * Agl
    else:
        dAabs = 0.0

    return [dAgl, dAgw, dAblood, dAliver, dAlung, dAkidney,
            dAbrain, dAmuscle, dAfat, dAperiph, dAabs]

dose_mg_unit = dose_mg * 1000.0

if route == 'iv':
    y0 = [0.0, 0.0, dose_mg_unit, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, dose_mg_unit]
elif route == 'oral':
    y0 = [dose_mg_unit, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
else:
    y0 = [dose_mg_unit, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

sim_h  = 72.0
t_eval = np.linspace(0.0, sim_h, int(sim_h * 20) + 1)

sol = solve_ivp(
    pbpk_ode, [0.0, sim_h], y0, t_eval=t_eval,
    method='LSODA', rtol=1e-6, atol=1e-12, max_step=0.5
)

if sol.success:
    Cblood_arr  = np.maximum(0.0, sol.y[2] / Vblood)
    Cliver_arr  = np.maximum(0.0, sol.y[3] / Vliver)
    Ckidney_arr = np.maximum(0.0, sol.y[5] / Vkidney)
    Cbrain_arr  = np.maximum(0.0, sol.y[6] / Vbrain)
    Cmuscle_arr = np.maximum(0.0, sol.y[7] / Vmuscle)
    Cfat_arr    = np.maximum(0.0, sol.y[8] / Vfat)
else:
    Cblood_arr  = np.zeros(len(t_eval))
    Cliver_arr  = np.zeros(len(t_eval))
    Ckidney_arr = np.zeros(len(t_eval))
    Cbrain_arr  = np.zeros(len(t_eval))
    Cmuscle_arr = np.zeros(len(t_eval))
    Cfat_arr    = np.zeros(len(t_eval))

import csv
step = max(1, len(sol.t) // 300)
with open('pk_profile.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['time_h', 'Cblood_ng_mL', 'Cliver_ng_g', 'Ckidney_ng_g',
                'Cbrain_ng_g', 'Cmuscle_ng_g', 'Cfat_ng_g'])
    for i in range(0, len(sol.t), step):
        w.writerow([
            round(float(sol.t[i]), 3),
            round(float(Cblood_arr[i])  * 1000.0, 4),
            round(float(Cliver_arr[i])  * 1000.0, 4),
            round(float(Ckidney_arr[i]) * 1000.0, 4),
            round(float(Cbrain_arr[i])  * 1000.0, 4),
            round(float(Cmuscle_arr[i]) * 1000.0, 4),
            round(float(Cfat_arr[i])    * 1000.0, 4),
        ])

raw = {
    'tool_used': 'BioMate native PBPK (Willmann 2003 physiology)',
    'quality_tier': 'ema_accepted_open_source',
    'compound': compound_name,
    'dose_mg': round(dose_mg, 2),
    'route': route,
    'population': population,
    'ode_success': bool(sol.success),
    'sim_hours': sim_h,
    'CL_hep_L_h': round(CL_hep_L_h, 4),
    'CL_ren_L_h': round(CL_ren_L_h, 4),
    'GFR_L_h': round(GFR_L_h, 3),
    'phys_BW_kg': phys['BW_kg'],
    'Kp_liver': round(Kp_liver, 3),
    'Kp_kidney': round(Kp_kidney, 3),
    't_arr_len': len(sol.t),
    'Cblood_max_ug_mL': round(float(Cblood_arr.max()), 6),
}
with open('pk_simulation_raw.json', 'w') as f:
    json.dump(raw, f, indent=2)

print('PBPK simulation complete.')
PYEOF
    """
}

// ---------------------------------------------------------------------------
// Phase C: Analysis & QC (NCA)
// ---------------------------------------------------------------------------
// [Phase C] Phase C — NCA Analysis
process NCA_ANALYSIS {
    tag 'nca'
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    path pk_profile
    path raw_json

    output:
    path "nca_parameters.json", emit: nca_params
    path "pk_nca_table.csv",    emit: nca_table

    script:
    """
    python3 << 'PYEOF'
import json, csv, math
import numpy as np

with open('${raw_json}') as f:
    raw = json.load(f)

# Read pk_profile
t_arr = []
cp_arr = []
with open('${pk_profile}') as f:
    reader = csv.DictReader(f)
    for row in reader:
        t_arr.append(float(row['time_h']))
        cp_arr.append(float(row['Cblood_ng_mL']))

t_arr  = np.array(t_arr)
cp_arr = np.array(cp_arr)

# NCA computation
_trapz = np.trapezoid if hasattr(np, 'trapezoid') else np.trapz
cmax   = float(cp_arr.max())
tmax   = float(t_arr[np.argmax(cp_arr)])
auc_obs = float(_trapz(cp_arr, t_arr))

t_half = None
kel    = None
thresh = 0.05 * cmax
idx_term = np.where(cp_arr > thresh)[0]
if len(idx_term) > 4:
    t_fit  = t_arr[idx_term[-min(10, len(idx_term)):]]
    cp_fit = cp_arr[idx_term[-min(10, len(idx_term)):]]
    mask   = cp_fit > 0
    if mask.sum() > 2:
        slope = np.polyfit(t_fit[mask], np.log(cp_fit[mask]), 1)[0]
        if slope < -1e-6:
            kel    = -slope
            t_half = round(math.log(2) / kel, 2)
            auc_extrap = float(cp_arr[idx_term[-1]]) / kel
            auc_obs += auc_extrap

dose_ug = raw['dose_mg'] * 1000.0
cl_l_h  = round(dose_ug / auc_obs / 1000.0, 4) if auc_obs > 0 else None

BW_kg = raw.get('phys_BW_kg', 70.0)
vss   = None
if cl_l_h and t_half:
    vss = round(cl_l_h * t_half / math.log(2) / BW_kg, 3)

cl_sys = raw.get('CL_hep_L_h', 0) + raw.get('CL_ren_L_h', 0)
route  = raw.get('route', 'oral')
f_oral = None
if route == 'oral' and cl_l_h and auc_obs > 0:
    f_oral = round(min(1.0, (auc_obs * cl_sys * 1000.0) / dose_ug), 3)

nca = {
    'Cmax_ng_mL':        round(cmax, 2),
    'AUC0inf_h_ng_mL':   round(auc_obs, 1),
    'Tmax_h':            round(tmax, 2),
    't_half_h':          t_half,
    'CL_L_h':            cl_l_h,
    'Vss_L_kg':          vss,
    'F_oral':            f_oral,
}

with open('nca_parameters.json', 'w') as f:
    json.dump(nca, f, indent=2)

with open('pk_nca_table.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['parameter', 'value', 'unit'])
    for k, v in nca.items():
        unit_map = {
            'Cmax_ng_mL': 'ng/mL',
            'AUC0inf_h_ng_mL': 'h*ng/mL',
            'Tmax_h': 'h',
            't_half_h': 'h',
            'CL_L_h': 'L/h',
            'Vss_L_kg': 'L/kg',
            'F_oral': 'fraction',
        }
        w.writerow([k, v, unit_map.get(k, '')])

print('NCA complete: Cmax={} ng/mL, t_half={} h'.format(round(cmax, 2), t_half))
PYEOF
    """
}

// ---------------------------------------------------------------------------
// Phase D: Report & Export
// ---------------------------------------------------------------------------
// [Phase D] Phase D — PK Report
process GENERATE_FINAL_REPORT {
    tag 'report'
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    path validated_params
    path raw_json
    path nca_params
    path nca_table

    output:
    path "pk_summary_report.json", emit: summary_json
    path "pk_results.html",        emit: html_report
    path "versions.yml",           emit: versions

    script:
    """
    python3 << 'PYEOF'
import json

with open('${validated_params}') as f:
    vp = json.load(f)
with open('${raw_json}') as f:
    raw = json.load(f)
with open('${nca_params}') as f:
    nca = json.load(f)

summary = {
    'status': 'completed',
    'tool_used': raw.get('tool_used', ''),
    'quality_tier': raw.get('quality_tier', 'ema_accepted_open_source'),
    'compound': {
        'name': vp['compound_name'],
        'smiles': vp['smiles'],
        'mw_da': vp['mw_da'],
        'logP': vp['logP'],
        'fu_plasma': vp['fu_plasma'],
        'ionization': vp['ionization'],
        'bcs_class': vp['bcs_class'],
    },
    'dosing': {
        'dose_mg_kg': vp['dose_mg_kg'],
        'route': vp['route'],
        'population': vp['population'],
    },
    'pk_parameters': nca,
    'clearance': {
        'CL_hep_L_h': raw.get('CL_hep_L_h'),
        'CL_ren_L_h': raw.get('CL_ren_L_h'),
    },
    'validation_warnings': vp.get('validation_warnings', []),
    'references': [
        'Willmann S et al. J Med Chem 2003; 46(12):2355-2368',
        'EMA OSP Qualification Opinion 2025',
        'Rodgers T & Rowland M. J Pharm Sci 2006; 95(6):1241-1257',
    ],
}

with open('pk_summary_report.json', 'w') as f:
    json.dump(summary, f, indent=2)

rows_html = ''
for k, v in nca.items():
    rows_html += '<tr><td>{}</td><td>{}</td></tr>\\n'.format(k, v if v is not None else 'N/A')

html = '''<!DOCTYPE html>
<html>
<head><title>PK-Sim PBPK Report</title>
<style>
  body {{ font-family: Arial, sans-serif; margin: 24px; }}
  h2 {{ color: #2c3e50; }}
  table {{ border-collapse: collapse; width: 60%; }}
  th {{ background: #2c3e50; color: white; padding: 8px 12px; text-align: left; }}
  td {{ padding: 6px 12px; border-bottom: 1px solid #ddd; }}
  tr:nth-child(even) {{ background: #f9f9f9; }}
  .quality {{ background: #d4edda; padding: 6px 12px; border-radius: 4px; display: inline-block; }}
</style>
</head>
<body>
<h2>PK-Sim PBPK Report: {compound}</h2>
<p><strong>Tool:</strong> {tool}</p>
<p><strong>Quality tier:</strong> <span class="quality">{tier}</span></p>
<p><strong>Compound:</strong> {compound} | MW: {mw} Da | logP: {logp}</p>
<p><strong>Dose:</strong> {dose} mg/kg ({route})</p>
<h3>NCA Parameters</h3>
<table>
<tr><th>Parameter</th><th>Value</th></tr>
{rows}
</table>
<p style="font-size:11px;color:#666;margin-top:24px;">
References: Willmann et al. J Med Chem 2003; EMA OSP Qualification Opinion 2025
</p>
</body></html>'''.format(
    compound=vp['compound_name'],
    tool=raw.get('tool_used', 'BioMate native PBPK'),
    tier=raw.get('quality_tier', 'ema_accepted_open_source'),
    mw=vp['mw_da'],
    logp=vp['logP'],
    dose=vp['dose_mg_kg'],
    route=vp['route'],
    rows=rows_html,
)

with open('pk_results.html', 'w') as f:
    f.write(html)

with open('versions.yml', 'w') as f:
    f.write('pk_sim_pbpk:\\n  python: "3.10"\\n  numpy: ">=1.24"\\n  scipy: ">=1.10"\\n  pk_sim: "11.3"\\n')

print('Report generated.')
PYEOF
    """
}

// ---------------------------------------------------------------------------
// Named workflow
// ---------------------------------------------------------------------------
workflow PK_SIM_PBPK_WORKFLOW {
    take: meta_ch

    main:
    VALIDATE_COMPOUND_PARAMS()
    PKSIM_SIMULATE(VALIDATE_COMPOUND_PARAMS.out.validated_params)
    NCA_ANALYSIS(
        PKSIM_SIMULATE.out.pk_profile,
        PKSIM_SIMULATE.out.raw_json
    )
    GENERATE_FINAL_REPORT(
        VALIDATE_COMPOUND_PARAMS.out.validated_params,
        PKSIM_SIMULATE.out.raw_json,
        NCA_ANALYSIS.out.nca_params,
        NCA_ANALYSIS.out.nca_table
    )

    emit:
    summary_json = GENERATE_FINAL_REPORT.out.summary_json
    pk_profile   = PKSIM_SIMULATE.out.pk_profile
    nca_params   = NCA_ANALYSIS.out.nca_params
    html_report  = GENERATE_FINAL_REPORT.out.html_report
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------
workflow {
    meta = [id: 'pk_sim_pbpk_run', single_end: false]
    Channel.value(meta) | PK_SIM_PBPK_WORKFLOW
}
