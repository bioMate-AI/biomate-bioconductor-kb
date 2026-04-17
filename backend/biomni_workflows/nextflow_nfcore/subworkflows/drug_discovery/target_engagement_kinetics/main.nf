#!/usr/bin/env nextflow
/*
 * drug_discovery/target_engagement_kinetics
 *
 * Estimates drug-target binding kinetic rate constants (kon, koff) and
 * residence time (RT = 1/koff). Models receptor occupancy over time given
 * a PK profile. Particularly relevant for slow-binding or covalent mechanisms.
 *
 * kon/koff estimation: descriptor-based proxy from Copeland 2016;
 * Tummino & Copeland Drug Metab Dispos 2008.
 * Occupancy ODE: classic 1:1 binding kinetics D + T <-> DT.
 *
 * Input:  SMILES, target_name, optional IC50_nM and PK params
 * Output: kinetics_prediction.json, occupancy_profile.csv, recommendation.json
 */

nextflow.enable.dsl = 2

params.outdir         = './results'
params.smiles_list    = '["CC(=O)Oc1ccccc1C(=O)O"]'
params.target_name    = 'unknown'
params.IC50_nM        = 'null'
params.Kd_nM          = 'null'
params.pk_t_half_h    = '6'
params.pk_Cmax_nM     = '100'
params.pk_tmax_h      = '1'
params.occupancy_threshold_pct = '80'
params.simulation_hours = '48'

process TARGET_ENGAGEMENT_KINETICS {
    tag "$meta.id"
    label 'process_low'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("kinetics_results.json"),      emit: results
    tuple val(meta), path("kinetics_output.txt"),        emit: output
    tuple val(meta), path("kinetics_prediction.json"),   emit: kinetics
    tuple val(meta), path("occupancy_profile.csv"),      emit: occupancy
    tuple val(meta), path("recommendation.json"),        emit: recommendation
    path "versions.yml",                                 emit: versions

    script:
    """
    export PARAM_SMILES_LIST='${params.smiles_list}'
    export PARAM_TARGET='${params.target_name}'
    export PARAM_IC50='${params.IC50_nM}'
    export PARAM_KD='${params.Kd_nM}'
    export PARAM_T_HALF='${params.pk_t_half_h}'
    export PARAM_CMAX='${params.pk_Cmax_nM}'
    export PARAM_TMAX='${params.pk_tmax_h}'
    export PARAM_OCC_THRESH='${params.occupancy_threshold_pct}'
    export PARAM_SIM_H='${params.simulation_hours}'

    python3 << 'PYEOF'
import json, os, csv, sys, math
import numpy as np
from scipy.integrate import solve_ivp
from rdkit import Chem
from rdkit.Chem import Descriptors, rdMolDescriptors, Crippen

def auto_convert(v, default=None):
    if v in (None,'','null','None'): return default
    try: return float(v)
    except: return default

def parse_smiles_input(raw):
    raw = raw.strip()
    if raw.startswith('['):
        try:
            lst = json.loads(raw)
            return [(str(i+1), s) for i, s in enumerate(lst)]
        except: pass
    return [('1', raw)]

# -- Physicochemical -> kon/koff estimation ------------------------------------
# Reference: Copeland 2016 "Evaluation of enzyme inhibitors in drug discovery"
# + Tummino & Copeland 2008 heuristics
def estimate_kinetics(mol, kd_nM=None, ic50_nM=None):
    '''
    Estimate kon and koff from physicochemical properties.
    Typical range: kon 1e3-1e6 M-1s-1, koff 1e-5 to 1e-1 s-1
    '''
    mw   = Descriptors.ExactMolWt(mol)
    logp = Crippen.MolLogP(mol)
    tpsa = rdMolDescriptors.CalcTPSA(mol)
    hbd  = rdMolDescriptors.CalcNumHBD(mol)
    rot  = rdMolDescriptors.CalcNumRotatableBonds(mol)

    # Diffusion-limited association rate decreases with MW
    # kon ~ 1e6 M-1s-1 for small rigid molecules; lower for large flexible ones
    kon_log = 5.5 - 0.003*(mw-250) - 0.05*rot
    kon = 10**max(3.0, min(6.5, kon_log))  # M-1s-1

    # If Kd provided, compute koff from koff = kon * Kd
    if kd_nM is not None:
        kd_M = kd_nM * 1e-9
        koff = kon * kd_M
    elif ic50_nM is not None:
        # IC50 ~ Kd for competitive inhibitors at [S] << Km
        kd_M = ic50_nM * 1e-9
        koff = kon * kd_M
    else:
        # No affinity data -- estimate from TPSA/HBD (more H-bonds -> slower koff)
        hbond_contrib = hbd * 0.3 + tpsa * 0.005
        koff = 10**(-3 - hbond_contrib)  # s-1, slower with more H-bonds

    kd_est_nM = (koff / kon) * 1e9
    rt_min     = (1 / koff) / 60  # residence time in minutes

    confidence = 'HIGH' if kd_nM or ic50_nM else 'MEDIUM'
    return {
        'kon_M_inv_s_inv': round(kon, 1),
        'koff_s_inv': round(koff, 6),
        'Kd_nM': round(kd_est_nM, 2),
        'residence_time_min': round(rt_min, 1),
        'confidence': confidence,
        'input_Kd_nM': kd_nM, 'input_IC50_nM': ic50_nM
    }

# -- PK model: 1-compartment oral absorption -----------------------------------
def pk_profile(cmax_nM, t_half_h, tmax_h, t_eval):
    '''Biexponential PK: absorption + elimination.'''
    ke = math.log(2) / t_half_h   # elimination rate constant
    ka = math.log(2) / (tmax_h * 0.7) if tmax_h > 0 else ke * 3  # absorption rate
    cp = np.array([cmax_nM * (math.exp(-ke*t) - math.exp(-ka*t)) / (1 - math.exp(-ka*tmax_h + ke*tmax_h))
                   if t > 0 else 0 for t in t_eval])
    # Normalize to observed Cmax
    if cp.max() > 0:
        cp = cp / cp.max() * cmax_nM
    return np.maximum(0, cp)

# -- Receptor occupancy ODE ----------------------------------------------------
# d[DT]/dt = kon * [D](t) * (Rtot - [DT]) - koff * [DT]
# Assume Rtot << [D] (excess drug -- common at clinical doses)
def occupancy_ode(cp_interp, kon_M, koff_s, t_eval, rtot_nM=10):
    '''
    Solves occupancy ODE with time-varying drug concentration from PK.
    cp_interp: callable Cp(t) in nM
    '''
    def ode(t, y):
        dt = y[0]
        cp_nM = max(0, float(cp_interp(t)))
        cp_M  = cp_nM * 1e-9
        rtot_M = rtot_nM * 1e-9
        ddt = kon_M * cp_M * (rtot_M - dt) - koff_s * dt
        return [ddt]

    y0 = [0.0]
    sol = solve_ivp(ode, [t_eval[0], t_eval[-1]], y0, t_eval=t_eval,
                    method='RK45', rtol=1e-5, dense_output=False)
    if not sol.success:
        import sys as _sys
        print(f"WARNING: occupancy ODE failed: {sol.message}", file=_sys.stderr)
        return np.zeros(len(t_eval))
    occupancy_pct = np.array(sol.y[0]) / (rtot_nM * 1e-9) * 100
    return np.clip(occupancy_pct, 0, 100)

# -- Process -------------------------------------------------------------------
raw_smiles     = os.environ.get('PARAM_SMILES_LIST','["C"]')
target_name    = os.environ.get('PARAM_TARGET','unknown')
ic50_nM        = auto_convert(os.environ.get('PARAM_IC50'))
kd_nM          = auto_convert(os.environ.get('PARAM_KD'))
t_half_h       = auto_convert(os.environ.get('PARAM_T_HALF'), 6)
cmax_nM        = auto_convert(os.environ.get('PARAM_CMAX'), 100)
tmax_h         = auto_convert(os.environ.get('PARAM_TMAX'), 1)
occ_thresh     = auto_convert(os.environ.get('PARAM_OCC_THRESH'), 80)
sim_h          = auto_convert(os.environ.get('PARAM_SIM_H'), 48)

smiles_pairs = parse_smiles_input(raw_smiles)
all_kinetics, all_recommendations = [], []
occ_rows = [['compound','time_h','occupancy_pct','Cp_nM']]

for cid, smi in smiles_pairs:
    mol = Chem.MolFromSmiles(smi) if smi else None
    if mol is None:
        print(f"WARNING: invalid SMILES {cid}", file=sys.stderr); continue

    kin = estimate_kinetics(mol, kd_nM=kd_nM, ic50_nM=ic50_nM)
    all_kinetics.append({'compound': cid, 'SMILES': smi, **kin})

    # Compute PK profile
    t_eval = np.linspace(0, sim_h, int(sim_h * 10) + 1)
    cp_arr = pk_profile(cmax_nM, t_half_h, tmax_h, t_eval)
    cp_interp = lambda t: float(np.interp(t, t_eval, cp_arr))

    # Compute occupancy
    occ_arr = occupancy_ode(cp_interp, kin['kon_M_inv_s_inv'], kin['koff_s_inv'], t_eval)
    for i in range(0, len(t_eval), max(1, len(t_eval)//100)):
        occ_rows.append([cid, round(t_eval[i],2), round(occ_arr[i],1), round(cp_arr[i],1)])

    # Duration above threshold occupancy
    above_thresh = t_eval[occ_arr >= occ_thresh]
    duration_h = round(float(above_thresh[-1] - above_thresh[0]), 1) if len(above_thresh) > 1 else 0
    peak_occ   = round(float(occ_arr.max()), 1)

    # Dosing frequency recommendation
    rt_min = kin['residence_time_min']
    if rt_min >= 360:
        dosing_rec = f'RT={rt_min:.0f}min supports QD or BID dosing'
        adequate = True
    elif rt_min >= 120:
        dosing_rec = f'RT={rt_min:.0f}min supports BID dosing; QD may have coverage gaps'
        adequate = True
    elif rt_min >= 30:
        dosing_rec = f'RT={rt_min:.0f}min may require TID/QID; optimize for longer RT'
        adequate = False
    else:
        dosing_rec = f'RT={rt_min:.0f}min too short for practical dosing; increase binding affinity/RT'
        adequate = False

    all_recommendations.append({
        'compound': cid,
        'peak_occupancy_pct': peak_occ,
        'duration_above_{:.0f}pct_h'.format(occ_thresh): duration_h,
        'residence_time_min': rt_min,
        'adequate_for_qd_dosing': rt_min >= 360,
        'recommendation': dosing_rec
    })

with open('kinetics_prediction.json','w') as f:
    out = all_kinetics[0] if len(all_kinetics)==1 else all_kinetics
    json.dump(out, f, indent=2)

with open('occupancy_profile.csv','w',newline='') as f:
    w = csv.writer(f); w.writerows(occ_rows)

with open('recommendation.json','w') as f:
    out = all_recommendations[0] if len(all_recommendations)==1 else all_recommendations
    json.dump(out, f, indent=2)

full = {'status':'completed', 'target': target_name,
        'PK_params': {'t_half_h': t_half_h, 'Cmax_nM': cmax_nM, 'tmax_h': tmax_h},
        'kinetics': all_kinetics, 'recommendations': all_recommendations}
with open('kinetics_results.json','w') as f:
    json.dump(full, f, indent=2)

report = [f"=== TARGET ENGAGEMENT KINETICS: {target_name} ===",""]
for k, r in zip(all_kinetics, all_recommendations):
    report += [f"Compound {k['compound']}:",
               f"  kon={k['kon_M_inv_s_inv']:.2e} M-1s-1 | koff={k['koff_s_inv']:.2e} s-1 | Kd={k['Kd_nM']:.1f} nM",
               f"  Residence time: {k['residence_time_min']:.0f} min | Confidence: {k['confidence']}",
               f"  Peak occupancy: {r['peak_occupancy_pct']}% | {r['recommendation']}", ""]
with open('kinetics_output.txt','w') as f:
    f.write('\n'.join(report))
print('\n'.join(report))
PYEOF

    cat << 'EOF' > versions.yml
target_engagement_kinetics:
  python: "3.10"
  numpy: ">=1.24"
  scipy: ">=1.10"
  rdkit: ">=2023.9"
EOF
    """
}

workflow TARGET_ENGAGEMENT_WORKFLOW {
    take: meta_ch
    main: TARGET_ENGAGEMENT_KINETICS(meta_ch)
    emit:
        results     = TARGET_ENGAGEMENT_KINETICS.out.results
        kinetics    = TARGET_ENGAGEMENT_KINETICS.out.kinetics
        occupancy   = TARGET_ENGAGEMENT_KINETICS.out.occupancy
}

workflow {
    meta = [id: 'target_kinetics_run', single_end: false]
    Channel.value(meta) | TARGET_ENGAGEMENT_WORKFLOW
}
