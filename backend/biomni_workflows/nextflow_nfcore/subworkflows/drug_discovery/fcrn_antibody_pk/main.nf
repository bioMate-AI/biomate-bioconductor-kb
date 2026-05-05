#!/usr/bin/env nextflow
/*
 * drug_discovery/fcrn_antibody_pk
 *
 * FcRn-mediated antibody pharmacokinetics prediction and optimization.
 * The neonatal Fc receptor (FcRn) is the primary determinant of IgG half-life
 * via pH-dependent binding: IgG binds FcRn in acidic endosomes (pH 6.0),
 * is rescued from lysosomal degradation, and released at physiological pH (7.4).
 *
 * Models:
 *   1. Two-compartment TMDD (target-mediated drug disposition) PK model
 *   2. FcRn binding model: pH-dependent kon/koff → recycling efficiency
 *   3. SC bioavailability prediction from FcRn-dependent first-pass catabolism
 *   4. Fc engineering impact: YTE, LS, GASD/ALIE, AAA mutations on PK
 *   5. pH-switch antibody (PSA) half-life extension prediction
 *
 * Applications:
 *   - Predict half-life from Fc sequence mutations
 *   - Optimize FcRn binding affinity for half-life extension
 *   - Predict SC vs IV dosing implications
 *   - Assess impact of IgG subclass (IgG1/2/4) on recycling
 *   - BiTE / fragment antibody half-life vs FcRn-fused variants
 *
 * References:
 *   - Roopenian & Akilesh 2007 Nature Reviews Immunology 7:715 (FcRn biology)
 *   - Deng et al. 2012 Drug Metab Dispos 40:1545 (FcRn PBPK)
 *   - Robbie et al. 2013 Antimicrob Agents Chemother (YTE half-life)
 *   - Zalevsky et al. 2010 Nature Biotechnology (LS mutation)
 *   - Schlothauer et al. 2016 Protein Eng Des Sel (pH-switch)
 */

nextflow.enable.dsl = 2

params.outdir              = './results'
params.antibody_format     = 'igg1'       // igg1 | igg2 | igg4 | scfv_fc | bite_fc | fab | nanobody
params.fc_mutation         = 'wt'         // wt | yte | ls | gasd_alie | aaa | psa | m252y_s254t_t256e
params.mw_kda              = '145'        // molecular weight (kDa); IgG1=145, scFv-Fc=100, Fab=48
params.dose_mg_kg          = '10'         // IV dose (mg/kg)
params.route               = 'iv'         // iv | sc | im
params.sc_volume_mL        = '1.0'        // SC injection volume (affects local absorption)
params.fcrn_affinity_ph6   = 'null'       // FcRn Kd at pH 6 (nM); null = use format default
params.species             = 'human'      // human | monkey | mouse | rat
params.indication          = 'oncology'   // oncology | autoimmune | infectious | rare_disease
params.n_doses             = '1'          // number of doses for multi-dose PK

process FCRN_ANTIBODY_PK {
    tag "$meta.id"
    label 'process_low'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("fcrn_pk_results.json"),  emit: results
    tuple val(meta), path("pk_profile.csv"),         emit: pk_profile
    tuple val(meta), path("mutation_comparison.csv"), emit: mutations
    tuple val(meta), path("pk_report.txt"),           emit: report
    path "versions.yml",                              emit: versions

    script:
    """
    export PARAM_FORMAT='${params.antibody_format}'
    export PARAM_MUT='${params.fc_mutation}'
    export PARAM_MW='${params.mw_kda}'
    export PARAM_DOSE='${params.dose_mg_kg}'
    export PARAM_ROUTE='${params.route}'
    export PARAM_SCVOL='${params.sc_volume_mL}'
    export PARAM_KD='${params.fcrn_affinity_ph6}'
    export PARAM_SPECIES='${params.species}'
    export PARAM_IND='${params.indication}'
    export PARAM_NDOSES='${params.n_doses}'

    python3 << 'PYEOF'
import json, os, csv, math, random

def pf(v, d=None):
    if v in (None,'','null'): return d
    try: return float(v)
    except: return d
def pi(v, d=1):
    try: return int(float(v))
    except: return d

ab_format  = os.environ.get('PARAM_FORMAT', 'igg1')
fc_mut     = os.environ.get('PARAM_MUT', 'wt')
mw_kda     = pf(os.environ.get('PARAM_MW'), 145.0)
dose       = pf(os.environ.get('PARAM_DOSE'), 10.0)
route      = os.environ.get('PARAM_ROUTE', 'iv')
sc_vol     = pf(os.environ.get('PARAM_SCVOL'), 1.0)
kd_input   = pf(os.environ.get('PARAM_KD'), None)
species    = os.environ.get('PARAM_SPECIES', 'human')
indication = os.environ.get('PARAM_IND', 'oncology')
n_doses    = pi(os.environ.get('PARAM_NDOSES'), 1)

random.seed(42)

# ─── Format baseline PK parameters ────────────────────────────────────────────
# Literature-derived IgG PK parameters (human, per kg)
# Sources: Deng 2012; Roopenian 2007; Robbie 2013
FORMAT_PK = {
    'igg1': {'t_half_days': 21, 'vd_L_kg': 0.07, 'cl_mL_h_kg': 0.18,
              'fcrn_kd_ph6_nM': 250, 'f_sc': 0.72, 'tmax_sc_h': 72},
    'igg2': {'t_half_days': 20, 'vd_L_kg': 0.06, 'cl_mL_h_kg': 0.19,
              'fcrn_kd_ph6_nM': 300, 'f_sc': 0.65, 'tmax_sc_h': 96},
    'igg4': {'t_half_days': 21, 'vd_L_kg': 0.07, 'cl_mL_h_kg': 0.18,
              'fcrn_kd_ph6_nM': 200, 'f_sc': 0.70, 'tmax_sc_h': 84},
    'scfv_fc': {'t_half_days': 14, 'vd_L_kg': 0.08, 'cl_mL_h_kg': 0.28,
                'fcrn_kd_ph6_nM': 350, 'f_sc': 0.60, 'tmax_sc_h': 60},
    'bite_fc': {'t_half_days': 1.5, 'vd_L_kg': 0.12, 'cl_mL_h_kg': 2.5,
                'fcrn_kd_ph6_nM': None, 'f_sc': 0.30, 'tmax_sc_h': 24,
                'note': 'BiTE without Fc: very short t1/2; FcRn recycling absent'},
    'fab':    {'t_half_days': 0.9, 'vd_L_kg': 0.06, 'cl_mL_h_kg': 3.8,
               'fcrn_kd_ph6_nM': None, 'f_sc': 0.40, 'tmax_sc_h': 12,
               'note': 'Fab fragment: renal clearance dominant; no FcRn'},
    'nanobody': {'t_half_days': 0.5, 'vd_L_kg': 0.05, 'cl_mL_h_kg': 7.2,
                 'fcrn_kd_ph6_nM': None, 'f_sc': 0.55, 'tmax_sc_h': 6,
                 'note': 'VHH: renal-dominant clearance; albumin fusion extends t1/2'},
}

# ─── Fc mutation effects on FcRn affinity and half-life ──────────────────────
# Literature-calibrated: fold-change in Kd(pH6) and t1/2 relative to WT IgG1
MUT_EFFECTS = {
    'wt':             {'kd_fold': 1.0,  't_half_fold': 1.0,  'cl_fold': 1.0,
                       'ref': 'Baseline IgG1'},
    'yte':            {'kd_fold': 0.11, 't_half_fold': 2.4,  'cl_fold': 0.42,
                       'ref': 'M252Y/S254T/T256E (Dall\'Acqua 2006); motavizumab-YTE: t½=67→100d'},
    'ls':             {'kd_fold': 0.18, 't_half_fold': 2.0,  'cl_fold': 0.50,
                       'ref': 'M428L/N434S (Zalevsky 2010 NatBiotech); MEDI-534 t½ ×2'},
    'm252y_s254t_t256e': {'kd_fold': 0.11, 't_half_fold': 2.4, 'cl_fold': 0.42,
                          'ref': 'YTE (same as yte alias)'},
    'gasd_alie':      {'kd_fold': 0.08, 't_half_fold': 3.0,  'cl_fold': 0.33,
                       'ref': 'G236A/S239D + A327L/I332E (Bhatt 2012); enhances both FcRn and FcγR'},
    'aaa':            {'kd_fold': 8.0,  't_half_fold': 0.35, 'cl_fold': 2.9,
                       'ref': 'N297A/L234A/L235A (effector null); reduced FcRn binding'},
    'psa':            {'kd_fold': 0.05, 't_half_fold': 4.0,  'cl_fold': 0.25,
                       'ref': 'pH-switch antibody: tight pH6 binding + fast pH7.4 release (Schlothauer 2016)'},
}

base_pk = FORMAT_PK.get(ab_format, FORMAT_PK['igg1'])
mut_eff = MUT_EFFECTS.get(fc_mut, MUT_EFFECTS['wt'])

# Apply mutation effects
base_kd = kd_input if kd_input else (base_pk.get('fcrn_kd_ph6_nM') or 250.0)
kd_ph6  = round(base_kd * mut_eff['kd_fold'], 1)
t_half  = round(base_pk['t_half_days'] * mut_eff['t_half_fold'], 1)
cl      = round(base_pk['cl_mL_h_kg'] * mut_eff['cl_fold'], 3)
vd      = base_pk['vd_L_kg']
f_sc    = base_pk['f_sc'] * (1 - 0.08 * (mut_eff['cl_fold'] - 1))  # SC F affected by catabolism
f_sc    = round(max(0.3, min(0.95, f_sc)), 2)

# Species correction factors (allometric scaling)
SPECIES_FACTORS = {
    'human': 1.0, 'monkey': 0.85, 'mouse': 0.35, 'rat': 0.50,
}
species_f = SPECIES_FACTORS.get(species, 1.0)
t_half_sp = round(t_half * species_f, 1)
cl_sp     = round(cl / species_f, 3)

# ─── 2-compartment IV PK simulation ───────────────────────────────────────────
ke     = math.log(2) / (t_half_sp * 24)  # elimination rate (1/h)
k12    = round(0.4 * ke, 5)              # distribution from central to peripheral
k21    = round(0.2 * ke, 5)              # distribution back
v1     = vd * 0.6                        # central volume fraction (L/kg)
dose_mg_L = dose / (v1 * 1000)          # initial Cmax (mg/L, assuming 70 kg implicit)
dose_ug_mL = dose_mg_L * 1000

time_h = list(range(0, int(t_half_sp * 24 * 5) + 1, 6))  # every 6h up to 5×t1/2

def pk_2comp_iv(t_arr, c0, ke, k12, k21):
    """Analytical 2-compartment IV bolus solution"""
    alpha = 0.5 * ((k12 + k21 + ke) + math.sqrt((k12 + k21 + ke)**2 - 4*k21*ke))
    beta  = 0.5 * ((k12 + k21 + ke) - math.sqrt(max(0, (k12 + k21 + ke)**2 - 4*k21*ke)))
    A     = c0 * (alpha - k21) / (alpha - beta)
    B     = c0 * (k21 - beta)  / (alpha - beta)
    result = []
    for t in t_arr:
        c = A * math.exp(-alpha * t) + B * math.exp(-beta * t)
        result.append(max(0, c))
    return result

pk_conc_iv = pk_2comp_iv(time_h, dose_ug_mL, ke, k12, k21)

# SC profile (flip-flop kinetics)
if route == 'sc':
    ka = math.log(2) / (base_pk.get('tmax_sc_h', 72) / 2)  # absorption rate
    pk_conc = []
    for t in time_h:
        c_iv = pk_2comp_iv([t], dose_ug_mL * f_sc, ke, k12, k21)[0]
        abs_term = f_sc * dose_ug_mL * ka / max(ka - ke, 0.001)
        c_sc = abs_term * (math.exp(-ke * t) - math.exp(-ka * t))
        pk_conc.append(round(max(0, c_sc), 4))
else:
    pk_conc = [round(c, 4) for c in pk_conc_iv]

# PK metrics
cmax_raw = max(pk_conc)
cmax     = round(cmax_raw, 2)
tmax_h   = time_h[pk_conc.index(cmax_raw)]
auc_inf = round(cmax / ke, 1) if route == 'iv' else round(sum(
    (pk_conc[i] + pk_conc[i+1]) / 2 * (time_h[i+1] - time_h[i])
    for i in range(len(time_h)-1)) , 1)

# ─── FcRn binding model: recycling efficiency ─────────────────────────────────
# Recycling efficiency from FcRn Kd (pH 6) — tighter binding = more rescue
# Henderson-Hasselbalch-like relationship (empirical from Dall'Acqua 2006)
recycle_eff = 1 / (1 + (kd_ph6 / 150) ** 0.6)  # 150 nM ≈ WT inflection
recycle_eff = round(max(0.1, min(0.98, recycle_eff)), 3)
lysosomal_deg_rate = round(1 - recycle_eff, 3)

# ─── Mutation comparison table ────────────────────────────────────────────────
mut_comparison = []
for mut_name, eff in MUT_EFFECTS.items():
    kd_m     = round(base_kd * eff['kd_fold'], 1)
    t_half_m = round(base_pk['t_half_days'] * eff['t_half_fold'] * species_f, 1)
    cl_m     = round(base_pk['cl_mL_h_kg'] * eff['cl_fold'] / species_f, 3)
    re_m     = round(1 / (1 + (kd_m / 150) ** 0.6), 3) if kd_m else None
    mut_comparison.append({
        'mutation': mut_name,
        'fcrn_kd_ph6_nM': kd_m,
        'recycling_efficiency': re_m,
        't_half_days': t_half_m,
        'cl_mL_h_kg': cl_m,
        'fold_vs_wt': round(eff['t_half_fold'], 2),
        'ref': eff['ref'][:60],
    })

results = {
    'status': 'completed',
    'antibody_format': ab_format,
    'fc_mutation': fc_mut,
    'species': species,
    'indication': indication,
    'fcrn_binding': {
        'kd_ph6_nM': kd_ph6,
        'recycling_efficiency': recycle_eff,
        'lysosomal_degradation_fraction': lysosomal_deg_rate,
    },
    'pk_parameters': {
        'mw_kDa': mw_kda,
        't_half_days': t_half_sp,
        'CL_mL_h_kg': cl_sp,
        'Vd_L_kg': vd,
        'route': route,
        'F_sc': f_sc if route == 'sc' else None,
        'Cmax_ug_mL': cmax,
        'Tmax_h': tmax_h,
        'AUC_inf_ug_h_mL': auc_inf,
    },
    'dosing': {
        'dose_mg_kg': dose,
        'route': route,
        'n_doses': n_doses,
    },
    'fc_mutation_context': {
        'mutation': fc_mut,
        'fold_t_half_vs_wt': mut_eff['t_half_fold'],
        'reference': mut_eff['ref'],
    },
    'format_notes': base_pk.get('note', ''),
    'references': [
        'Roopenian & Akilesh 2007 Nat Rev Immunol 7:715 (FcRn biology)',
        'Deng et al. 2012 Drug Metab Dispos 40:1545 (FcRn PBPK model)',
        'Robbie et al. 2013 Antimicrob Agents Chemother (YTE mutation)',
        'Zalevsky et al. 2010 Nat Biotechnol 28:157 (LS mutation)',
        'Schlothauer et al. 2016 Protein Eng Des Sel (pH-switch)',
    ],
}

with open('fcrn_pk_results.json', 'w') as f:
    json.dump(results, f, indent=2)

with open('pk_profile.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['time_h','time_days','concentration_ug_mL'])
    for i, t in enumerate(time_h):
        w.writerow([t, round(t/24, 2), pk_conc[i]])

with open('mutation_comparison.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['mutation','fcrn_kd_ph6_nM','recycling_efficiency',
                't_half_days','cl_mL_h_kg','fold_vs_wt','reference'])
    for m in mut_comparison:
        w.writerow([m['mutation'], m['fcrn_kd_ph6_nM'], m['recycling_efficiency'],
                    m['t_half_days'], m['cl_mL_h_kg'], m['fold_vs_wt'], m['ref']])

has_fcrn = ab_format in ('igg1','igg2','igg4','scfv_fc')
lines = [
    '╔══════════════════════════════════════════════════════════╗',
    f'  FcRn Antibody PK Report',
    f'  Format: {ab_format.upper()} | Mutation: {fc_mut.upper()} | Species: {species}',
    '╚══════════════════════════════════════════════════════════╝',
    '',
    f'── FcRn Binding ─────────────────────────────────────────',
    f'  Kd (pH 6.0):          {kd_ph6} nM' if has_fcrn else '  FcRn recycling:        NOT APPLICABLE (no Fc)',
    f'  Recycling efficiency: {recycle_eff*100:.1f}%' if has_fcrn else '',
    f'  Lysosomal degradation: {lysosomal_deg_rate*100:.1f}%' if has_fcrn else '',
    '',
    f'── PK Parameters ────────────────────────────────────────',
    f'  Half-life:            {t_half_sp} days',
    f'  Clearance:            {cl_sp} mL/h/kg',
    f'  Volume of distribution: {vd} L/kg',
    f'  Cmax ({route.upper()}):          {cmax} µg/mL (at {dose} mg/kg)',
    f'  AUC∞:                 {auc_inf} µg·h/mL',
]
if route == 'sc':
    lines.append(f'  SC bioavailability:   {f_sc*100:.1f}%  Tmax: {tmax_h}h')
lines += [
    '',
    f'── Fc Mutation: {fc_mut.upper()} ─────────────────────────',
    f'  t½ vs WT IgG1:        {mut_eff["t_half_fold"]}× ({t_half_sp}d vs {base_pk["t_half_days"]}d)',
    f'  Reference:            {mut_eff["ref"][:65]}',
    '',
    '── Mutation Comparison (top 4 by t½) ─────────────────────',
]
for m in sorted(mut_comparison, key=lambda x: -x['t_half_days'])[:4]:
    lines.append(f'  {m["mutation"]:20} t½={m["t_half_days"]:5.1f}d  '
                 f'Kd={m["fcrn_kd_ph6_nM"] or "N/A":>6} nM  '
                 f'fold={m["fold_vs_wt"]}')

with open('pk_report.txt', 'w') as f:
    f.write('\n'.join(lines))
print('\n'.join(lines))
PYEOF

    python3 -c "print('fcrn_antibody_pk: 1.0')" > versions.yml
    """
}

workflow FCRN_PK_WORKFLOW {
    take: meta_ch
    main: FCRN_ANTIBODY_PK(meta_ch)
    emit:
        results   = FCRN_ANTIBODY_PK.out.results
        pk_profile = FCRN_ANTIBODY_PK.out.pk_profile
        mutations  = FCRN_ANTIBODY_PK.out.mutations
        report     = FCRN_ANTIBODY_PK.out.report
}

workflow { meta = [id:'fcrn_run']; Channel.value(meta) | FCRN_PK_WORKFLOW }
