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
// [Phase A] Safety Input Validation
process VALIDATE_SAFETY_INPUTS {
    tag 'validate'
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/workflow-tools:x86' : 'biomate/workflow-tools:latest'

    output:
    path "validated_safety_params.json", emit: validated_params
    path "herg_margin_check.json",       emit: herg_check

    // integrity: was an RNG stub fabricating results; honest-fail (no real implementation).
    script:
    """
    python3 << 'PYEOF'
import sys
sys.stderr.write("ERROR: ich_s7a_safety_pharmacology is not implemented against real measurement/tool — it requires real hERG patch-clamp electrophysiology + in vivo cardiovascular telemetry (QTc/MAP/HR) + a functional-observational/Irwin battery per ICH S7A. Refusing to emit fabricated results.\\n")
sys.exit(1)
PYEOF
    """
}

// ---------------------------------------------------------------------------
// Phase B: Core Computation (Cardiovascular Assessment)
// ---------------------------------------------------------------------------
// [Phase B] Cardiovascular Assessment (hERG / QTc)
process ICH_S7A_ASSESS_CV {
    tag 'cv_assess'
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/workflow-tools:x86' : 'biomate/workflow-tools:latest'

    input:
    path validated_params
    path herg_check

    output:
    path "cv_assessment.json", emit: cv_json
    path "herg_analysis.csv",  emit: herg_csv
    path "qc_metrics.json",    emit: qc_metrics

    // integrity: was an RNG stub fabricating results; honest-fail (no real implementation).
    script:
    """
    python3 << 'PYEOF'
import sys
sys.stderr.write("ERROR: ich_s7a_safety_pharmacology (cardiovascular assessment) is not implemented against real measurement/tool — it requires real hERG patch-clamp IC50 + in vivo cardiovascular telemetry (QTc/MAP/HR). Refusing to emit fabricated results.\\n")
sys.exit(1)
PYEOF
    """
}

// ---------------------------------------------------------------------------
// Phase C: Analysis & QC (CNS + Respiratory Assessment)
// ---------------------------------------------------------------------------
// [Phase C] CNS & Respiratory Assessment
process ICH_S7A_ASSESS_CNS_RESP {
    tag 'cns_resp'
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/workflow-tools:x86' : 'biomate/workflow-tools:latest'

    input:
    path validated_params

    output:
    path "cns_respiratory_assessment.json", emit: cns_resp_json

    // integrity: was an RNG stub fabricating results; honest-fail (no real implementation).
    script:
    """
    python3 << 'PYEOF'
import sys
sys.stderr.write("ERROR: ich_s7a_safety_pharmacology (CNS/respiratory assessment) is not implemented against real measurement/tool — it requires a real functional-observational/Irwin battery in vivo plus whole-body plethysmography respiratory measurements. Refusing to emit fabricated results.\\n")
sys.exit(1)
PYEOF
    """
}

// ---------------------------------------------------------------------------
// Phase D: Report & Export
// ---------------------------------------------------------------------------
// [Phase D] ICH S7A Core Battery Report
process GENERATE_FINAL_REPORT {
    tag 'report'
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/workflow-tools:x86' : 'biomate/workflow-tools:latest'

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
