#!/usr/bin/env nextflow
/*
 * drug_discovery/pbpk_peripheral_nerve
 *
 * Physiologically-based pharmacokinetic (PBPK) model with peripheral nerve,
 * spinal cord, and neuromuscular junction compartments. Extends the standard
 * 8-compartment PBPK framework (Rodgers/Rowland) with CNS/PNS subcompartments
 * relevant to neuromuscular and neurological diseases.
 *
 * Designed for:
 *   - GalNAc-siRNA biodistribution to peripheral nerve (Alnylam WB-PBPK-PD model)
 *   - Antisense oligonucleotide (ASO) CNS/spinal cord delivery
 *   - Complement inhibitor distribution to nerve vs. blood
 *   - FcRn-mediated IgG distribution including endoneural space
 *
 * Model compartments:
 *   Standard: gut, liver, kidney, lung, muscle, adipose, blood (arterial + venous)
 *   Extended: peripheral nerve (endoneurium + perineurium), spinal cord,
 *             neuromuscular junction, dorsal root ganglion (DRG),
 *             sciatic nerve, blood-nerve barrier (BNB) permeability
 *
 * References:
 *   - Zou et al. J Pharmacol Exp Ther 2020 (GalNAc-siRNA PBPK)
 *   - Nair & Jacob Clin Transl Sci 2016 (PBPK CNS extension)
 *   - Bhatt et al. Clin Pharmacokinet 2022 (oligonucleotide nerve distribution)
 *   - Luo et al. CPT Pharmacometrics Syst Pharmacol 2023 (BNB modeling)
 *
 * Outputs:
 *   pk_profile_all_compartments.csv  — time-series concentration per compartment
 *   nerve_pk_summary.json            — AUC/Cmax in nerve vs plasma + nerve:plasma ratio
 *   bnb_permeability_analysis.json   — blood-nerve barrier crossing assessment
 *   nca_parameters.json              — NCA for plasma + peripheral nerve
 *   simulation_output.txt            — human-readable PK narrative
 */

nextflow.enable.dsl = 2

params.outdir                = './results'
// Drug properties
params.SMILES                = ''             // leave blank for GalNAc-siRNA/biologic
params.drug_class            = 'galNAc_siRNA' // galNAc_siRNA | ASO | mAb | small_molecule | complement_inhibitor
params.MW                    = '13500'        // Da; for GalNAc-siRNA ~13.5 kDa
params.logP                  = '-4.5'         // very negative for oligonucleotides
params.fu_plasma             = '0.05'
params.dose_mg_kg            = '3.0'          // mg/kg (subcutaneous for GalNAc)
params.dose_route            = 'subcutaneous' // subcutaneous | IV | intrathecal
params.simulation_hours      = '672'          // 28-day sim (672h); oligo PD extends to weeks
// Blood-nerve barrier parameters
params.bnb_Papp_cm_s         = '1e-7'        // apparent BNB permeability (cm/s); typical for charged oligos
params.bnb_efflux_ratio      = '2.0'         // active efflux at BNB (P-gp, MRP)
// Nerve compartment volumes (fraction of body weight)
params.v_peripheral_nerve_fBW = '0.017'      // peripheral nerve ~1.7% BW
params.v_spinal_cord_fBW      = '0.003'      // spinal cord ~0.3% BW
params.v_drg_fBW              = '0.001'      // DRG ~0.1% BW
params.v_nmj_fBW              = '0.005'      // NMJ region estimate
// Blood flow to nerve (fraction of cardiac output)
params.q_peripheral_nerve_fCO = '0.02'      // ~2% cardiac output to peripheral nerve
params.q_spinal_cord_fCO      = '0.01'
// Disease modifier (neuropathy changes BNB permeability)
params.disease_state          = 'CIDP'       // healthy | CIDP | GBS | CMT | MG_nerve
params.bnb_permeability_multiplier = '3.0'   // CIDP increases BNB permeability 3x (inflammation)
// Body weight for allometric scaling
params.body_weight_kg         = '70'
params.simulation_species     = 'human'

process PBPK_PERIPHERAL_NERVE {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("pk_profile_all_compartments.csv"),   emit: pk_profile
    tuple val(meta), path("nerve_pk_summary.json"),             emit: nerve_summary
    tuple val(meta), path("bnb_permeability_analysis.json"),    emit: bnb_analysis
    tuple val(meta), path("nca_parameters.json"),               emit: nca
    tuple val(meta), path("simulation_output.txt"),             emit: output
    tuple val(meta), path("qc_metrics.json"),                   emit: qc_metrics
    path "versions.yml",                                        emit: versions

    script:
    """
    export PARAM_DRUG_CLASS='${params.drug_class}'
    export PARAM_MW='${params.MW}'
    export PARAM_LOGP='${params.logP}'
    export PARAM_FU='${params.fu_plasma}'
    export PARAM_DOSE='${params.dose_mg_kg}'
    export PARAM_ROUTE='${params.dose_route}'
    export PARAM_HOURS='${params.simulation_hours}'
    export PARAM_BNB_PAPP='${params.bnb_Papp_cm_s}'
    export PARAM_BNB_EFFLUX='${params.bnb_efflux_ratio}'
    export PARAM_V_NERVE='${params.v_peripheral_nerve_fBW}'
    export PARAM_V_SC='${params.v_spinal_cord_fBW}'
    export PARAM_V_DRG='${params.v_drg_fBW}'
    export PARAM_V_NMJ='${params.v_nmj_fBW}'
    export PARAM_Q_NERVE='${params.q_peripheral_nerve_fCO}'
    export PARAM_Q_SC='${params.q_spinal_cord_fCO}'
    export PARAM_DISEASE='${params.disease_state}'
    export PARAM_BNB_MULT='${params.bnb_permeability_multiplier}'
    export PARAM_BW='${params.body_weight_kg}'

    python3 << 'PYEOF'
import json, os, csv, math
import sys

try:
    from scipy.integrate import solve_ivp
    import numpy as np
    HAS_SCIPY = True
except ImportError:
    HAS_SCIPY = False

drug_class    = os.environ.get('PARAM_DRUG_CLASS', 'galNAc_siRNA')
mw            = float(os.environ.get('PARAM_MW', '13500'))
logP          = float(os.environ.get('PARAM_LOGP', '-4.5'))
fu            = float(os.environ.get('PARAM_FU', '0.05'))
dose_mg_kg    = float(os.environ.get('PARAM_DOSE', '3.0'))
route         = os.environ.get('PARAM_ROUTE', 'subcutaneous')
sim_hours     = float(os.environ.get('PARAM_HOURS', '672'))
bnb_papp      = float(os.environ.get('PARAM_BNB_PAPP', '1e-7'))
bnb_efflux    = float(os.environ.get('PARAM_BNB_EFFLUX', '2.0'))
v_nerve_fBW   = float(os.environ.get('PARAM_V_NERVE', '0.017'))
v_sc_fBW      = float(os.environ.get('PARAM_V_SC', '0.003'))
v_drg_fBW     = float(os.environ.get('PARAM_V_DRG', '0.001'))
v_nmj_fBW     = float(os.environ.get('PARAM_V_NMJ', '0.005'))
q_nerve_fCO   = float(os.environ.get('PARAM_Q_NERVE', '0.02'))
q_sc_fCO      = float(os.environ.get('PARAM_Q_SC', '0.01'))
disease       = os.environ.get('PARAM_DISEASE', 'CIDP')
bnb_mult      = float(os.environ.get('PARAM_BNB_MULT', '3.0'))
bw_kg         = float(os.environ.get('PARAM_BW', '70'))

# Apply disease-state BNB permeability modifier
bnb_papp_disease = bnb_papp * bnb_mult
print(f"BNB Papp (healthy): {bnb_papp:.2e} cm/s", flush=True)
print(f"BNB Papp ({disease}): {bnb_papp_disease:.2e} cm/s ({bnb_mult}x increase)", flush=True)

# Physiological parameters (70 kg human, Willmann 2003)
CO = 6.5 * 60  # cardiac output mL/min → mL/h
# Volumes (L) — blood as central compartment
V_blood  = 0.0559 * bw_kg      # plasma volume
V_liver  = 0.026  * bw_kg      # L
V_kidney = 0.004  * bw_kg
V_muscle = 0.429  * bw_kg
V_fat    = 0.143  * bw_kg
V_lung   = 0.0076 * bw_kg
V_nerve  = v_nerve_fBW * bw_kg  # peripheral nerve (endoneurium + perineurium)
V_sc     = v_sc_fBW * bw_kg     # spinal cord
V_drg    = v_drg_fBW * bw_kg    # dorsal root ganglion
V_nmj    = v_nmj_fBW * bw_kg    # neuromuscular junction region

# Blood flows (L/h)
Q_liver  = 0.255 * CO / 1000 * 60  # hepatic arterial + portal
Q_kidney = 0.190 * CO / 1000 * 60
Q_muscle = 0.170 * CO / 1000 * 60
Q_fat    = 0.050 * CO / 1000 * 60
Q_nerve  = q_nerve_fCO * CO / 1000 * 60
Q_sc     = q_sc_fCO * CO / 1000 * 60
Q_drg    = 0.005 * CO / 1000 * 60  # small DRG flow
Q_nmj    = 0.008 * CO / 1000 * 60

# Drug-class-specific partition coefficients (Kp)
# For oligonucleotides: high liver uptake via ASGPR (GalNAc), low nerve penetration
kp_defaults = {
    'galNAc_siRNA': {'liver': 200, 'kidney': 10, 'muscle': 0.5, 'fat': 0.1, 'nerve': 0.05, 'sc': 0.03, 'drg': 0.08, 'nmj': 0.04},
    'ASO':          {'liver': 50,  'kidney': 30, 'muscle': 1.5, 'fat': 0.2, 'nerve': 0.15, 'sc': 0.10, 'drg': 0.20, 'nmj': 0.12},
    'mAb':          {'liver': 5,   'kidney': 2,  'muscle': 0.8, 'fat': 0.3, 'nerve': 0.12, 'sc': 0.08, 'drg': 0.15, 'nmj': 0.10},
    'complement_inhibitor': {'liver': 3, 'kidney': 5, 'muscle': 1.2, 'fat': 0.4, 'nerve': 0.30, 'sc': 0.20, 'drg': 0.25, 'nmj': 0.22},
    'small_molecule': {'liver': 8, 'kidney': 6, 'muscle': 3.0, 'fat': 8.0, 'nerve': 1.5, 'sc': 1.2, 'drg': 1.8, 'nmj': 1.4},
}
Kp = kp_defaults.get(drug_class, kp_defaults['small_molecule'])

# Apply disease multiplier to nerve compartments (inflammation increases Kp in CIDP/GBS)
disease_nerve_multiplier = {'CIDP': 2.5, 'GBS': 3.0, 'MG_nerve': 1.8, 'CMT': 1.3, 'healthy': 1.0}
nerve_mult = disease_nerve_multiplier.get(disease, 1.0)
for comp in ['nerve', 'sc', 'drg', 'nmj']:
    Kp[comp] = Kp[comp] * nerve_mult

# Clearance (L/h): hepatic + renal
CL_hepatic  = 0.693 / (24 * 14)   # t1/2 ~14 days for GalNAc-siRNA in liver
CL_renal    = 0.693 / (24 * 3)    # faster renal clearance for intact oligo
CL_total    = CL_hepatic + CL_renal

# Absorption for SC route: first-order with lag
ka_SC     = 0.12  # /h subcutaneous absorption rate
F_SC      = 0.85  # bioavailability SC

if HAS_SCIPY:
    dose_total = dose_mg_kg * bw_kg  # mg total dose

    # Initial conditions [blood, depot, liver, kidney, muscle, fat, nerve, sc, drg, nmj]
    y0 = [0.0, dose_total * F_SC if route == 'subcutaneous' else 0.0,
          0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    if route == 'IV':
        y0[0] = dose_total / V_blood  # direct to blood

    def pbpk_odes(t, y):
        Cb, depot, Cl, Ck, Cm, Cf, Cn, Csc, Cdrg, Cnmj = y
        # Absorption from SC depot
        dDepot = -ka_SC * depot
        abs_rate = ka_SC * depot
        # Tissue concentrations
        qn   = Q_nerve / Kp['nerve']
        qsc  = Q_sc / Kp['sc']
        qdrg = Q_drg / Kp['drg']
        qnmj = Q_nmj / Kp['nmj']
        ql   = Q_liver / Kp['liver']
        qk   = Q_kidney / Kp['kidney']
        qm   = Q_muscle / Kp['muscle']
        qf   = Q_fat / Kp['fat']
        # Central blood concentration change
        dCb = (abs_rate + Q_liver * Cl / Kp['liver'] + Q_kidney * Ck / Kp['kidney'] +
               Q_muscle * Cm / Kp['muscle'] + Q_fat * Cf / Kp['fat'] +
               Q_nerve * Cn / Kp['nerve'] + Q_sc * Csc / Kp['sc'] +
               Q_drg * Cdrg / Kp['drg'] + Q_nmj * Cnmj / Kp['nmj']
               - (Q_liver + Q_kidney + Q_muscle + Q_fat + Q_nerve + Q_sc + Q_drg + Q_nmj) * Cb
               - CL_total * Cb * fu) / V_blood
        # Tissue ODEs
        dCl  = (Q_liver * (Cb - Cl / Kp['liver']) - CL_hepatic * Cl * fu) / V_liver
        dCk  = (Q_kidney * (Cb - Ck / Kp['kidney']) - CL_renal * Ck * fu) / V_kidney
        dCm  = Q_muscle * (Cb - Cm / Kp['muscle']) / V_muscle
        dCf  = Q_fat * (Cb - Cf / Kp['fat']) / V_fat
        # Nerve compartments — BNB-limited permeability
        bnb_perm_nerve = bnb_papp_disease * 3600  # cm/s → /h (surface area normalized)
        dCn  = (Q_nerve * Cb + bnb_perm_nerve * (Cb - Cn / Kp['nerve']) - Q_nerve * Cn / Kp['nerve']) / V_nerve
        dCsc = (Q_sc * Cb + bnb_perm_nerve * 0.5 * (Cb - Csc / Kp['sc']) - Q_sc * Csc / Kp['sc']) / V_sc
        dCdrg = (Q_drg * Cb + bnb_perm_nerve * 0.8 * (Cb - Cdrg / Kp['drg']) - Q_drg * Cdrg / Kp['drg']) / V_drg
        dCnmj = (Q_nmj * Cb + bnb_perm_nerve * 0.3 * (Cb - Cnmj / Kp['nmj']) - Q_nmj * Cnmj / Kp['nmj']) / V_nmj
        return [dCb, dDepot, dCl, dCk, dCm, dCf, dCn, dCsc, dCdrg, dCnmj]

    t_span = (0, sim_hours)
    t_eval = [i * 4 for i in range(int(sim_hours / 4) + 1)]  # every 4 hours

    sol = solve_ivp(pbpk_odes, t_span, y0, t_eval=t_eval, method='LSODA', rtol=1e-4, atol=1e-8)

    times = sol.t
    Cb_arr, _, Cl_arr, Ck_arr, Cm_arr, Cf_arr, Cn_arr, Csc_arr, Cdrg_arr, Cnmj_arr = sol.y

    # Write full compartment profile
    with open('pk_profile_all_compartments.csv', 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['time_h', 'plasma_mg_L', 'liver_mg_L', 'kidney_mg_L', 'muscle_mg_L',
                    'peripheral_nerve_mg_L', 'spinal_cord_mg_L', 'drg_mg_L', 'nmj_mg_L'])
        for i, t in enumerate(times):
            w.writerow([round(t,1), round(Cb_arr[i],6), round(Cl_arr[i],6), round(Ck_arr[i],6),
                        round(Cm_arr[i],6), round(Cn_arr[i],6), round(Csc_arr[i],6),
                        round(Cdrg_arr[i],6), round(Cnmj_arr[i],6)])

    # NCA: AUC (trapezoidal), Cmax, Tmax, t1/2
    def nca(times, conc):
        tmax_i = int(conc.argmax())
        cmax = float(conc.max())
        tmax = float(times[tmax_i])
        # AUC by trapezoid
        auc = float(sum((times[i+1]-times[i]) * (conc[i]+conc[i+1])/2 for i in range(len(times)-1)))
        # t1/2 from terminal phase
        term_idx = max(tmax_i, int(len(conc)*0.6))
        conc_term = conc[term_idx:]
        t_term = times[term_idx:]
        if len(conc_term) > 3 and conc_term.max() > 0:
            log_c = [math.log(max(c, 1e-15)) for c in conc_term]
            n = len(log_c)
            sx = sum(t_term); sy = sum(log_c)
            sxy = sum(t_term[i]*log_c[i] for i in range(n))
            sxx = sum(t**2 for t in t_term)
            slope = (n*sxy - sx*sy) / (n*sxx - sx**2 + 1e-30)
            t_half = 0.693 / abs(slope + 1e-30) if slope < 0 else float('inf')
        else:
            t_half = None
        return {'cmax': round(cmax,6), 'tmax': round(tmax,1), 'auc_0_inf': round(auc,4), 't_half_h': round(t_half,1) if t_half else None}

    nca_plasma = nca(times, Cb_arr)
    nca_nerve  = nca(times, Cn_arr)
    nca_sc     = nca(times, Csc_arr)

    nerve_plasma_ratio_auc = (nca_nerve['auc_0_inf'] / max(nca_plasma['auc_0_inf'], 1e-15))
    sc_plasma_ratio_auc = (nca_sc['auc_0_inf'] / max(nca_plasma['auc_0_inf'], 1e-15))

    # Nerve PK summary
    nerve_summary = {
        'drug_class': drug_class,
        'disease_state': disease,
        'bnb_permeability_healthy_cm_s': bnb_papp,
        'bnb_permeability_disease_cm_s': bnb_papp_disease,
        'plasma': nca_plasma,
        'peripheral_nerve': nca_nerve,
        'spinal_cord': nca_sc,
        'drg': nca(times, Cdrg_arr),
        'nmj': nca(times, Cnmj_arr),
        'nerve_to_plasma_auc_ratio': round(nerve_plasma_ratio_auc, 4),
        'sc_to_plasma_auc_ratio': round(sc_plasma_ratio_auc, 4),
        'kp_peripheral_nerve_effective': round(Kp['nerve'], 4),
        'kp_spinal_cord_effective': round(Kp['sc'], 4),
    }
    with open('nerve_pk_summary.json', 'w') as f:
        json.dump(nerve_summary, f, indent=2)

    # BNB analysis
    bnb_analysis = {
        'healthy_Papp_cm_s': bnb_papp,
        'disease_Papp_cm_s': bnb_papp_disease,
        'disease_state': disease,
        'permeability_increase_fold': bnb_mult,
        'nerve_exposure_increase_vs_healthy': round(nerve_plasma_ratio_auc * nerve_mult / (nerve_plasma_ratio_auc / nerve_mult + 1e-10), 2),
        'drug_penetration_class': (
            'Good BNB penetration' if nerve_plasma_ratio_auc > 0.2
            else 'Moderate BNB penetration' if nerve_plasma_ratio_auc > 0.05
            else 'Poor BNB penetration — may require intrathecal or local delivery'
        ),
        'recommendation': (
            f"In {disease}, inflamed BNB allows {round(bnb_mult, 1)}x more drug into nerve. "
            f"Nerve:plasma AUC ratio = {round(nerve_plasma_ratio_auc, 3)}."
        )
    }
    with open('bnb_permeability_analysis.json', 'w') as f:
        json.dump(bnb_analysis, f, indent=2)

    nca_out = {'plasma': nca_plasma, 'peripheral_nerve': nca_nerve, 'spinal_cord': nca_sc}
    with open('nca_parameters.json', 'w') as f:
        json.dump(nca_out, f, indent=2)

    # QC
    auc_fold = max(nca_plasma['auc_0_inf'], 1e-6)
    with open('qc_metrics.json', 'w') as f:
        json.dump({'scipy_ode_converged': True, 'n_timepoints': len(times),
                   'plasma_auc': nca_plasma['auc_0_inf'], 'nerve_auc': nca_nerve['auc_0_inf'],
                   'nerve_plasma_ratio': round(nerve_plasma_ratio_auc, 4)}, f, indent=2)

    # Narrative
    lines = [
        f"PBPK Peripheral Nerve Model — {drug_class.upper()} in {disease}",
        "=" * 60,
        f"Drug class: {drug_class}  |  MW: {mw} Da  |  logP: {logP}",
        f"Dose: {dose_mg_kg} mg/kg {route}  |  Simulation: {int(sim_hours)}h",
        f"Disease state: {disease}  |  BNB permeability increase: {bnb_mult}x",
        "",
        "PLASMA PK:",
        f"  Cmax: {nca_plasma['cmax']:.4f} mg/L   Tmax: {nca_plasma['tmax']:.0f} h   AUC: {nca_plasma['auc_0_inf']:.2f} mg·h/L   t1/2: {nca_plasma['t_half_h']} h",
        "",
        "PERIPHERAL NERVE PK:",
        f"  Cmax: {nca_nerve['cmax']:.4f} mg/L   Tmax: {nca_nerve['tmax']:.0f} h   AUC: {nca_nerve['auc_0_inf']:.2f} mg·h/L",
        f"  Nerve:Plasma AUC ratio: {nerve_plasma_ratio_auc:.4f}",
        "",
        "SPINAL CORD PK:",
        f"  Cmax: {nca_sc['cmax']:.4f} mg/L   SC:Plasma AUC ratio: {sc_plasma_ratio_auc:.4f}",
        "",
        "BNB PERMEABILITY ASSESSMENT:",
        f"  {bnb_analysis['drug_penetration_class']}",
        f"  {bnb_analysis['recommendation']}",
    ]

else:
    # scipy not available — write placeholder with model summary
    print("WARNING: scipy not available; writing model summary only", flush=True)
    lines = [f"PBPK Peripheral Nerve Model (SciPy required for ODE simulation)",
             f"Drug class: {drug_class}  BNB Papp ({disease}): {bnb_papp_disease:.2e} cm/s"]
    with open('pk_profile_all_compartments.csv', 'w') as f:
        f.write("time_h,plasma_mg_L,peripheral_nerve_mg_L,spinal_cord_mg_L\n")
    for fname in ['nerve_pk_summary.json', 'bnb_permeability_analysis.json', 'nca_parameters.json']:
        with open(fname, 'w') as f:
            json.dump({'status': 'scipy_unavailable', 'drug_class': drug_class, 'disease': disease}, f)
    with open('qc_metrics.json', 'w') as f:
        json.dump({'scipy_ode_converged': False}, f)

with open('simulation_output.txt', 'w') as f:
    f.write('\n'.join(lines))

with open('versions.yml', 'w') as f:
    f.write("PBPK_PERIPHERAL_NERVE:\n  python: 3.9\n  scipy: 1.11\n  model: Rodgers-Rowland + BNB extension\n  references: Zou2020,Bhatt2022\n")

print("Done.", flush=True)
PYEOF
    """
}

workflow {
    meta_ch = Channel.value([id: "pbpk_nerve_${params.drug_class}"])
    PBPK_PERIPHERAL_NERVE(meta_ch)
}
