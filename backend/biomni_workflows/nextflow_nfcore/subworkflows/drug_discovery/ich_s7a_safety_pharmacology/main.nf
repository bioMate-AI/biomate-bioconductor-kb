#!/usr/bin/env nextflow
/*
 * drug_discovery/ich_s7a_safety_pharmacology
 *
 * ICH S7A core battery safety pharmacology panel simulation.
 *
 * Split into 4 phases for BioMate UI phase cards:
 *   Phase A: VALIDATE_SAFETY_INPUTS
 *   Phase B: ICH_S7A_ASSESS_CV
 *   Phase C: ICH_S7A_ASSESS_CNS_RESP
 *   Phase D: GENERATE_FINAL_REPORT
 */

nextflow.enable.dsl = 2

params.outdir            = './results'
params.smiles            = 'null'
params.compound_name     = 'Compound_X'
params.dose_mg_kg        = '10'
params.exposure_cmax_ng_mL = '500'
params.route             = 'oral'
params.safety_margin     = '10'
params.indication        = 'oncology'

// ---------------------------------------------------------------------------
// Phase A: Input & Validation
// ---------------------------------------------------------------------------
process VALIDATE_SAFETY_INPUTS {
    tag 'validate'
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    output:
    path "validated_safety_params.json", emit: validated_params
    path "herg_margin_check.json",       emit: herg_check

    script:
    """
    python3 << 'PYEOF'
import json, math, random

def pf(v, d=10.0):
    try: return float(v)
    except: return d

smiles         = '${params.smiles}'
compound_name  = '${params.compound_name}'
dose_mg_kg     = pf('${params.dose_mg_kg}', 10.0)
cmax_ng_mL     = pf('${params.exposure_cmax_ng_mL}', 500.0)
route          = '${params.route}'
safety_margin_target = pf('${params.safety_margin}', 10.0)
indication     = '${params.indication}'

random.seed(42)

warnings = []

if cmax_ng_mL <= 0:
    warnings.append('Cmax must be > 0; set to 500')
    cmax_ng_mL = 500.0
if dose_mg_kg <= 0:
    warnings.append('dose_mg_kg must be > 0; set to 10')
    dose_mg_kg = 10.0

def _estimate_mw_from_smiles(smi):
    if not smi or smi == 'null':
        return 400.0
    atom_weights = {'C': 12.011, 'N': 14.007, 'O': 15.999, 'S': 32.06,
                    'F': 18.998, 'Cl': 35.45, 'Br': 79.904, 'I': 126.90,
                    'P': 30.974, 'H': 1.008}
    mw = 0.0
    i = 0
    while i < len(smi):
        if i + 2 <= len(smi) and smi[i:i+2] in atom_weights:
            mw += atom_weights[smi[i:i+2]]
            i += 2
        elif smi[i].upper() in atom_weights:
            ch = smi[i].upper()
            mw += atom_weights[ch]
            i += 1
        else:
            i += 1
    mw += atom_weights['H'] * max(2, len([c for c in smi if c.isalpha()]) * 0.8)
    return round(max(100.0, mw), 1)

def _estimate_logP(smi):
    if not smi or smi == 'null':
        return round(random.gauss(2.5, 1.5), 2)
    n_rings   = smi.count('c') + smi.count('1') + smi.count('2')
    n_O       = smi.count('O') + smi.count('o')
    n_N       = smi.count('N') + smi.count('n')
    n_Cl      = smi.count('Cl')
    n_F       = smi.count('F')
    n_S       = smi.count('S') + smi.count('s')
    n_hbond_d = smi.count('[NH') + smi.count('OH')
    logP = (n_rings * 0.35) - (n_O * 0.56) - (n_N * 0.48) + \
           (n_Cl * 0.72) + (n_F * 0.53) + (n_S * 0.39) - (n_hbond_d * 0.28) + 1.1
    return round(logP + random.gauss(0, 0.3), 2)

mw_da  = _estimate_mw_from_smiles(smiles)
logP   = _estimate_logP(smiles)

# cmax nM
cmax_nM    = (cmax_ng_mL / mw_da) * 1000.0
fu_plasma  = round(random.uniform(0.05, 0.30), 3)
cmax_free_nM = round(cmax_nM * fu_plasma, 2)

# Estimate hERG IC50 for margin check
indication_hERG_modifier = {
    'oncology': 1.8, 'autoimmune': 1.2, 'cns': 2.1, 'cardiovascular': 0.9,
}
mod = indication_hERG_modifier.get(indication, 1.2)
hERG_IC50_uM = round(10 ** (1.2 - 0.35 * logP) * mod * random.uniform(0.7, 1.4), 2)
hERG_IC50_nM = round(hERG_IC50_uM * 1000, 1)
hERG_safety_margin = round(hERG_IC50_nM / max(cmax_free_nM, 0.01), 1)

out = {
    'smiles': smiles,
    'compound_name': compound_name,
    'dose_mg_kg': dose_mg_kg,
    'cmax_ng_mL': cmax_ng_mL,
    'cmax_nM': round(cmax_nM, 2),
    'route': route,
    'safety_margin_target': safety_margin_target,
    'indication': indication,
    'mw_da': mw_da,
    'logP': logP,
    'fu_plasma': fu_plasma,
    'cmax_free_nM': cmax_free_nM,
    'bbb_penetrant': (logP > 1.0) and (mw_da < 500),
    'validation_warnings': warnings,
}

with open('validated_safety_params.json', 'w') as f:
    json.dump(out, f, indent=2)

herg_check = {
    'hERG_IC50_uM': hERG_IC50_uM,
    'hERG_IC50_nM': hERG_IC50_nM,
    'safety_margin_x': hERG_safety_margin,
    'safety_margin_flag': 'RED' if hERG_safety_margin < 10 else ('YELLOW' if hERG_safety_margin < 30 else 'GREEN'),
    'cipa_tier2_required': hERG_safety_margin < 30.0,
}

with open('herg_margin_check.json', 'w') as f:
    json.dump(herg_check, f, indent=2)

print('Safety validation: hERG margin={}x, flag={}'.format(
    hERG_safety_margin, herg_check['safety_margin_flag']))
PYEOF
    """
}

// ---------------------------------------------------------------------------
// Phase B: Core Computation (Cardiovascular Assessment)
// ---------------------------------------------------------------------------
process ICH_S7A_ASSESS_CV {
    tag 'cv_assess'
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    path validated_params
    path herg_check

    output:
    path "cv_assessment.json", emit: cv_json
    path "herg_analysis.csv",  emit: herg_csv

    script:
    """
    python3 << 'PYEOF'
import json, csv, math, random

with open('${validated_params}') as f:
    vp = json.load(f)
with open('${herg_check}') as f:
    hc = json.load(f)

random.seed(43)

cmax_nM       = vp['cmax_nM']
indication    = vp['indication']
route         = vp['route']
logP          = vp['logP']
fu_plasma     = vp['fu_plasma']
cmax_free_nM  = vp['cmax_free_nM']

hERG_IC50_uM  = hc['hERG_IC50_uM']
hERG_IC50_nM  = hc['hERG_IC50_nM']
hERG_safety_margin = hc['safety_margin_x']
cipa_tier2_required = hc['cipa_tier2_required']

hERG_inhibition_pct = round(100.0 / (1.0 + hERG_IC50_nM / max(cmax_nM, 0.01)), 1)
delta_QTc_ms = round(0.025 * hERG_inhibition_pct * random.uniform(0.8, 1.3), 1)
qtc_flag = 'RED' if delta_QTc_ms > 20 else ('YELLOW' if delta_QTc_ms > 5 else 'GREEN')

base_map = {'oral': random.gauss(-3.0, 5.0), 'iv': random.gauss(-6.0, 8.0)}
map_change_pct = round(base_map.get(route, random.gauss(-3.0, 5.0)) *
                       (1.1 if indication == 'cardiovascular' else 1.0), 1)
map_flag = 'RED' if abs(map_change_pct) > 20 else ('YELLOW' if abs(map_change_pct) > 10 else 'GREEN')

hr_change_bpm = round(random.gauss(-2.0, 8.0) * (1.2 if indication == 'cns' else 1.0), 1)
hr_flag = 'RED' if abs(hr_change_bpm) > 25 else ('YELLOW' if abs(hr_change_bpm) > 12 else 'GREEN')

cipa_reason = (
    'hERG margin {}x < 30x threshold; multi-ion channel + AP modelling recommended (CiPA Tier 2)'.format(hERG_safety_margin)
    if cipa_tier2_required else 'Not required (hERG margin >= 30x)'
)

cv_flags_all = [qtc_flag, map_flag, hr_flag, hc['safety_margin_flag']]
cv_composite = 'RED' if 'RED' in cv_flags_all else ('YELLOW' if 'YELLOW' in cv_flags_all else 'GREEN')

cv_assessment = {
    'hERG_IC50_uM': hERG_IC50_uM,
    'hERG_IC50_nM': hERG_IC50_nM,
    'hERG_inhibition_at_Cmax_pct': hERG_inhibition_pct,
    'hERG_safety_margin_x': hERG_safety_margin,
    'hERG_safety_margin_flag': hc['safety_margin_flag'],
    'delta_QTc_ms_Fridericia': delta_QTc_ms,
    'qtc_prolongation_flag': qtc_flag,
    'map_change_pct': map_change_pct,
    'map_flag': map_flag,
    'hr_change_bpm': hr_change_bpm,
    'hr_flag': hr_flag,
    'fu_plasma': fu_plasma,
    'cmax_free_nM': cmax_free_nM,
    'CiPA_tier2_required': cipa_tier2_required,
    'CiPA_escalation_rationale': cipa_reason,
    'composite_flag': cv_composite,
    'reason': '{} composite (hERG={}, QTc={}, MAP={}, HR={})'.format(
        cv_composite, hc['safety_margin_flag'], qtc_flag, map_flag, hr_flag),
}

with open('cv_assessment.json', 'w') as f:
    json.dump(cv_assessment, f, indent=2)

with open('herg_analysis.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['parameter', 'value', 'unit', 'flag', 'threshold_yellow', 'threshold_red'])
    w.writerow(['hERG_IC50', hERG_IC50_uM, 'uM', hc['safety_margin_flag'], 30.0, 10.0])
    w.writerow(['hERG_safety_margin', hERG_safety_margin, 'x', hc['safety_margin_flag'], 30.0, 10.0])
    w.writerow(['delta_QTc', delta_QTc_ms, 'ms', qtc_flag, 5.0, 20.0])
    w.writerow(['MAP_change', map_change_pct, '%', map_flag, 10.0, 20.0])
    w.writerow(['HR_change', hr_change_bpm, 'bpm', hr_flag, 12.0, 25.0])

print('CV assessment: composite={}'.format(cv_composite))
PYEOF
    """
}

// ---------------------------------------------------------------------------
// Phase C: Analysis & QC (CNS + Respiratory Assessment)
// ---------------------------------------------------------------------------
process ICH_S7A_ASSESS_CNS_RESP {
    tag 'cns_resp'
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    path validated_params

    output:
    path "cns_respiratory_assessment.json", emit: cns_resp_json

    script:
    """
    python3 << 'PYEOF'
import json, math, random

with open('${validated_params}') as f:
    vp = json.load(f)

random.seed(44)

indication    = vp['indication']
logP          = vp['logP']
mw_da         = vp['mw_da']
bbb_penetrant = vp['bbb_penetrant']
smiles        = vp['smiles']

cns_modifier = 1.8 if (indication == 'cns' or bbb_penetrant) else 0.7

irwin_base  = random.gauss(1.5, 0.8) * cns_modifier
irwin_score = round(max(0.0, min(6.0, irwin_base)), 1)
irwin_flag  = 'RED' if irwin_score >= 4.0 else ('YELLOW' if irwin_score >= 2.0 else 'GREEN')

sed_prob      = 1.0 / (1.0 + math.exp(-(irwin_score - 2.5) * 1.2))
sedation_pct  = round(sed_prob * 100, 1)
sedation_flag = 'RED' if sedation_pct > 60 else ('YELLOW' if sedation_pct > 30 else 'GREEN')

tremor_prob         = 1.0 / (1.0 + math.exp(-(irwin_score - 3.0) * 1.5)) * 0.6
tremor_risk_pct     = round(tremor_prob * 100, 1)
convulsion_risk_pct = round(tremor_prob * 0.3 * random.uniform(0.5, 1.5) * 100, 1)
tremor_flag = 'RED' if tremor_risk_pct > 30 else ('YELLOW' if tremor_risk_pct > 10 else 'GREEN')

tpsa_est = round(max(0, 140 - logP * 15 + random.gauss(0, 8)), 1) if smiles != 'null' \
           else round(random.gauss(60, 20), 1)
cns_mpo_score = round(min(6.0, max(0.0,
    (1 if logP <= 5 else 0) +
    (1 if logP <= 3 else 0) +
    (1 if mw_da <= 360 else 0.5 if mw_da <= 500 else 0) +
    (1 if tpsa_est <= 90 else 0.5 if tpsa_est <= 120 else 0) +
    (1 if bbb_penetrant else 0) +
    random.uniform(0, 1)
)), 1)
cns_mpo_flag = 'GREEN' if cns_mpo_score >= 4 else ('YELLOW' if cns_mpo_score >= 2.5 else 'RED')

cns_composite = 'RED' if 'RED' in [irwin_flag, sedation_flag, tremor_flag] else \
                ('YELLOW' if 'YELLOW' in [irwin_flag, sedation_flag, tremor_flag] else 'GREEN')

# Respiratory
resp_cns_link = irwin_score * cns_modifier * 0.4
rr_change_pct  = round(random.gauss(-resp_cns_link * 3.5, 4.0), 1)
tv_change_pct  = round(random.gauss(-resp_cns_link * 2.5, 3.5), 1)
spo2_change_pct = round(min(0.0, random.gauss(-resp_cns_link * 0.8, 0.5)), 2)

rr_flag   = 'RED' if abs(rr_change_pct) > 20 else ('YELLOW' if abs(rr_change_pct) > 10 else 'GREEN')
tv_flag   = 'RED' if abs(tv_change_pct) > 20 else ('YELLOW' if abs(tv_change_pct) > 10 else 'GREEN')
spo2_flag = 'RED' if spo2_change_pct < -3.0 else ('YELLOW' if spo2_change_pct < -1.5 else 'GREEN')

resp_composite = 'RED' if 'RED' in [rr_flag, tv_flag, spo2_flag] else \
                 ('YELLOW' if 'YELLOW' in [rr_flag, tv_flag, spo2_flag] else 'GREEN')

out = {
    'cns': {
        'bbb_penetrant_estimated': bbb_penetrant,
        'irwin_score_0_to_6': irwin_score,
        'irwin_flag': irwin_flag,
        'irwin_interpretation': {0:'normal',1:'minimal',2:'mild',3:'moderate',4:'marked',5:'severe',6:'life-threatening'
                                 }.get(int(irwin_score), 'marked'),
        'sedation_risk_pct': sedation_pct,
        'sedation_flag': sedation_flag,
        'tremor_risk_pct': tremor_risk_pct,
        'convulsion_risk_pct': convulsion_risk_pct,
        'tremor_flag': tremor_flag,
        'CNS_MPO_score': cns_mpo_score,
        'CNS_MPO_flag': cns_mpo_flag,
        'TPSA_estimated': tpsa_est,
        'composite_flag': cns_composite,
    },
    'respiratory': {
        'rr_change_pct': rr_change_pct,
        'rr_flag': rr_flag,
        'tv_change_pct': tv_change_pct,
        'tv_flag': tv_flag,
        'spo2_change_abs_pct': spo2_change_pct,
        'spo2_flag': spo2_flag,
        'composite_flag': resp_composite,
    },
}

with open('cns_respiratory_assessment.json', 'w') as f:
    json.dump(out, f, indent=2)

print('CNS/Resp assessment: CNS={}, Resp={}'.format(cns_composite, resp_composite))
PYEOF
    """
}

// ---------------------------------------------------------------------------
// Phase D: Report & Export
// ---------------------------------------------------------------------------
process GENERATE_FINAL_REPORT {
    tag 'report'
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    path validated_params
    path herg_check
    path cv_json
    path cns_resp_json

    output:
    path "ich_s7a_report.json",               emit: report_json
    path "safety_pharmacology_summary.html",   emit: html_report
    path "versions.yml",                       emit: versions

    script:
    """
    python3 << 'PYEOF'
import json

with open('${validated_params}') as f:
    vp = json.load(f)
with open('${herg_check}') as f:
    hc = json.load(f)
with open('${cv_json}') as f:
    cv = json.load(f)
with open('${cns_resp_json}') as f:
    cns_resp = json.load(f)

cv_flag   = cv['composite_flag']
cns_flag  = cns_resp['cns']['composite_flag']
resp_flag = cns_resp['respiratory']['composite_flag']

all_flags = [cv_flag, cns_flag, resp_flag]
overall_flag = 'RED' if 'RED' in all_flags else ('YELLOW' if 'YELLOW' in all_flags else 'GREEN')

risk_map = {
    'GREEN':  'No significant safety pharmacology concern identified',
    'YELLOW': 'Potential safety signal requiring further characterisation',
    'RED':    'Significant safety pharmacology concern; IND-enabling risk mitigation required',
}

next_steps = []
if cv.get('CiPA_tier2_required'):
    next_steps.append('CiPA Tier 2: multi-ion channel patch-clamp + AP modelling')
if cv_flag in ('RED', 'YELLOW'):
    next_steps.append('Conscious telemetry dog cardiovascular study')
if cns_flag == 'RED':
    next_steps.append('Quantitative Irwin battery in rat + FOB')
if resp_flag in ('RED', 'YELLOW'):
    next_steps.append('Plethysmography respiratory study in conscious rat')
if not next_steps:
    next_steps.append('Routine pre-IND package sufficient')

report = {
    'status': 'completed',
    'compound': {
        'name': vp['compound_name'],
        'smiles': vp['smiles'],
        'mw_da': vp['mw_da'],
        'logP_estimated': vp['logP'],
        'dose_mg_kg': vp['dose_mg_kg'],
        'Cmax_ng_mL': vp['cmax_ng_mL'],
        'indication': vp['indication'],
    },
    'core_battery': {
        'cardiovascular': cv,
        'cns': cns_resp['cns'],
        'respiratory': cns_resp['respiratory'],
    },
    'integrated_assessment': {
        'overall_flag': overall_flag,
        'risk_category': risk_map[overall_flag],
        'CiPA_tier2_required': cv.get('CiPA_tier2_required', False),
        'next_steps': next_steps,
    },
    'guideline': 'ICH S7A (2001) + ICH S7B (2005)',
    'references': [
        'ICH S7A Guideline (2001)',
        'ICH S7B Guideline (2005)',
        'Fossa 2015 Clin Pharmacol Ther 97(1):23-26',
        'Bass 2004 Regul Toxicol Pharmacol 40(3):256-264',
    ],
}

with open('ich_s7a_report.json', 'w') as f:
    json.dump(report, f, indent=2)

flag_color = {'GREEN': '#28a745', 'YELLOW': '#ffc107', 'RED': '#dc3545'}

def flag_badge(flag):
    color = flag_color.get(flag, '#6c757d')
    return '<span style="background:{};color:white;padding:2px 8px;border-radius:3px;font-weight:bold;">{}</span>'.format(color, flag)

html = '''<!DOCTYPE html>
<html>
<head><title>ICH S7A Safety Pharmacology</title>
<style>
  body {{ font-family: Arial, sans-serif; margin: 24px; }}
  h2 {{ color: #2c3e50; }}
  table {{ border-collapse: collapse; width: 80%; margin-bottom: 20px; }}
  th {{ background: #2c3e50; color: white; padding: 8px 12px; text-align: left; }}
  td {{ padding: 6px 12px; border-bottom: 1px solid #ddd; }}
  tr:nth-child(even) {{ background: #f9f9f9; }}
  .next-step {{ background: #fff3cd; padding: 4px 8px; margin: 2px 0; border-radius: 3px; }}
</style>
</head>
<body>
<h2>ICH S7A Safety Pharmacology: {compound}</h2>
<p><strong>Overall:</strong> {overall_badge} | {risk_cat}</p>
<p><strong>Compound:</strong> {compound} | MW: {mw} Da | logP: {logp} | Cmax: {cmax} ng/mL</p>
<h3>Core Battery (ICH S7A Section 2.3)</h3>
<table>
<tr><th>System</th><th>Flag</th><th>Key Finding</th></tr>
<tr><td>Cardiovascular</td><td>{cv_badge}</td><td>hERG IC50 {herg_ic50} uM, margin {margin}x, dQTc {qtc} ms</td></tr>
<tr><td>CNS</td><td>{cns_badge}</td><td>Irwin {irwin}/6, sedation {sed}%, tremor {trem}%</td></tr>
<tr><td>Respiratory</td><td>{resp_badge}</td><td>RR {rr}%, TV {tv}%, SpO2 {spo2}%</td></tr>
</table>
<h3>Recommended Next Steps</h3>
{steps_html}
<p style="font-size:11px;color:#666;margin-top:24px;">
Guideline: ICH S7A (2001) + ICH S7B (2005)
</p>
</body></html>'''.format(
    compound=vp['compound_name'],
    overall_badge=flag_badge(overall_flag),
    risk_cat=risk_map[overall_flag],
    mw=vp['mw_da'],
    logp=vp['logP'],
    cmax=vp['cmax_ng_mL'],
    cv_badge=flag_badge(cv_flag),
    cns_badge=flag_badge(cns_flag),
    resp_badge=flag_badge(resp_flag),
    herg_ic50=cv.get('hERG_IC50_uM', 'N/A'),
    margin=cv.get('hERG_safety_margin_x', 'N/A'),
    qtc=cv.get('delta_QTc_ms_Fridericia', 'N/A'),
    irwin=cns_resp['cns'].get('irwin_score_0_to_6', 'N/A'),
    sed=cns_resp['cns'].get('sedation_risk_pct', 'N/A'),
    trem=cns_resp['cns'].get('tremor_risk_pct', 'N/A'),
    rr=cns_resp['respiratory'].get('rr_change_pct', 'N/A'),
    tv=cns_resp['respiratory'].get('tv_change_pct', 'N/A'),
    spo2=cns_resp['respiratory'].get('spo2_change_abs_pct', 'N/A'),
    steps_html=''.join('<p class="next-step">{}</p>'.format(s) for s in next_steps),
)

with open('safety_pharmacology_summary.html', 'w') as f:
    f.write(html)

with open('versions.yml', 'w') as f:
    f.write('ich_s7a_safety_pharmacology:\\n  python: "3.10"\\n')

print('ICH S7A report generated: overall_flag={}'.format(overall_flag))
PYEOF
    """
}

// ---------------------------------------------------------------------------
// Named workflow
// ---------------------------------------------------------------------------
workflow ICH_S7A_WORKFLOW {
    take: meta_ch

    main:
    VALIDATE_SAFETY_INPUTS()
    ICH_S7A_ASSESS_CV(
        VALIDATE_SAFETY_INPUTS.out.validated_params,
        VALIDATE_SAFETY_INPUTS.out.herg_check
    )
    ICH_S7A_ASSESS_CNS_RESP(VALIDATE_SAFETY_INPUTS.out.validated_params)
    GENERATE_FINAL_REPORT(
        VALIDATE_SAFETY_INPUTS.out.validated_params,
        VALIDATE_SAFETY_INPUTS.out.herg_check,
        ICH_S7A_ASSESS_CV.out.cv_json,
        ICH_S7A_ASSESS_CNS_RESP.out.cns_resp_json
    )

    emit:
    report_json = GENERATE_FINAL_REPORT.out.report_json
    cv_json     = ICH_S7A_ASSESS_CV.out.cv_json
    html_report = GENERATE_FINAL_REPORT.out.html_report
}

workflow {
    meta = [id: 's7a_run']
    Channel.value(meta) | ICH_S7A_WORKFLOW
}
