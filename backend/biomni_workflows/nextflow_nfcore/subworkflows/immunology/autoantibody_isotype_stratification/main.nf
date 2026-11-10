#!/usr/bin/env nextflow
/*
 * immunology/autoantibody_isotype_stratification
 *
 * Stratify autoantibody-driven autoimmune patients (Myasthenia Gravis, SLE,
 * Sjogren's) by autoantibody ISOTYPE composition, to predict FcRn-inhibitor
 * responsiveness and flag BAFF/APRIL-pathway (telitacicept) candidates.
 *
 * Rationale (tailored to the Vor Bio / telitacicept pilot):
 *   - FcRn inhibitors (efgartigimod, rozanolixizumab) recycle/clear IgG ONLY;
 *     they do not affect IgA or IgM autoantibodies.
 *   - Patients whose pathogenic autoantibody pool has a meaningful IgA/IgM
 *     contribution are therefore at risk of FcRn non-response (~30% of gMG
 *     patients are FcRn non-responders; the isotype hypothesis is a leading
 *     explanation).
 *   - BAFF/APRIL inhibition (telitacicept) depletes B cells AND plasma cells,
 *     lowering ALL isotypes including IgA/IgM — so the FcRn-refractory,
 *     IgA/IgM-contributing subgroup is the rational telitacicept population.
 *   - IgG subclass also matters: IgG1/IgG3 fix complement (AChR-MG);
 *     IgG4-predominant disease (e.g. MuSK-MG) is mechanistically distinct.
 *
 * References: Wolfe/Vincent AChR isotype heterogeneity; efgartigimod IgG-selective
 * pharmacology (Neurology N2 2023); telitacicept BAFF/APRIL Phase 3 gMG (Vor Bio 2026).
 *
 * INPUT (real patient serology panel — REQUIRED; no synthetic fallback):
 *   CSV with per-patient columns (missing cells allowed):
 *     patient_id, autoantibody_target, igg_total, igg1, igg2, igg3, igg4,
 *     iga, igm, baff, april, plasmablast_pct, prior_fcrn_mgadl_delta
 * OUTPUT:
 *   patient_stratification.csv, cohort_summary.json, stratification_report.md,
 *   stratification_results.json, versions.yml
 */

nextflow.enable.dsl = 2

params.outdir            = './results'
params.serology_file     = 'NONE'      // REQUIRED path to real patient serology CSV
params.cohort            = 'unspecified cohort'

// Fraction of the autoantibody pool contributed by non-IgG (IgA+IgM) at/above
// which a patient is flagged FcRn-refractory-risk / telitacicept candidate.
params.non_igg_threshold = '0.20'
// IgG4 fraction above which disease is flagged mechanistically distinct (MuSK-like).
params.igg4_threshold    = '0.50'
// BAFF or APRIL z-score/level above which the BAFF-APRIL axis is called elevated
// (only used if those columns are present).
params.baff_april_high   = '1.0'

process AUTOANTIBODY_ISOTYPE_STRATIFICATION {
    tag "$meta.id"
    label 'process_low'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/workflow-tools:x86' : 'biomate/workflow-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("stratification_results.json"),   emit: results
    tuple val(meta), path("patient_stratification.csv"),    emit: stratification
    tuple val(meta), path("cohort_summary.json"),           emit: summary
    tuple val(meta), path("stratification_report.md"),      emit: report
    path "versions.yml",                                    emit: versions

    script:
    """
    export PARAM_SEROLOGY='${params.serology_file}'
    export PARAM_COHORT='${params.cohort.toString().replace("'", "'\\''")}'
    export PARAM_NONIGG_T='${params.non_igg_threshold}'
    export PARAM_IGG4_T='${params.igg4_threshold}'
    export PARAM_BAFFAPRIL_H='${params.baff_april_high}'

    python3 << 'PYEOF'
import os, sys, json, csv

def _f(v, default=None):
    if v in (None, '', 'null', 'None', 'NA', 'nan'): return default
    try: return float(v)
    except Exception: return default

cohort      = os.environ.get('PARAM_COHORT', 'unspecified cohort')
non_igg_t   = _f(os.environ.get('PARAM_NONIGG_T'), 0.20)
igg4_t      = _f(os.environ.get('PARAM_IGG4_T'), 0.50)
ba_high     = _f(os.environ.get('PARAM_BAFFAPRIL_H'), 1.0)
serology    = os.environ.get('PARAM_SEROLOGY', 'NONE')

if (not serology) or serology in ('NONE', '') or not os.path.exists(serology):
    sys.stderr.write("ERROR: --serology_file is required and must point to a real "
                     "patient serology CSV (patient_id, igg_total, iga, igm, ...). "
                     "No synthetic data is generated.\\n")
    with open('stratification_results.json','w') as f:
        json.dump({'status':'failed','error':'serology_file missing or not found',
                   'patients':[]}, f, indent=2)
    sys.exit(1)

with open(serology, newline='') as fh:
    rows = list(csv.DictReader(fh))

def g(row, *names):
    for n in names:
        if n in row and row[n] not in ('', None):
            return _f(row[n])
    return None

patients = []
for row in rows:
    pid = (row.get('patient_id') or row.get('id') or row.get('sample') or '').strip()
    if not pid:
        continue
    target = (row.get('autoantibody_target') or row.get('target') or '').strip()
    igg_total = g(row, 'igg_total', 'igg', 'IgG', 'igg_titer')
    igg1 = g(row, 'igg1', 'IgG1'); igg2 = g(row, 'igg2', 'IgG2')
    igg3 = g(row, 'igg3', 'IgG3'); igg4 = g(row, 'igg4', 'IgG4')
    iga  = g(row, 'iga', 'IgA', 'iga_titer')
    igm  = g(row, 'igm', 'IgM', 'igm_titer')
    baff = g(row, 'baff', 'BAFF'); april = g(row, 'april', 'APRIL')
    plasmablast = g(row, 'plasmablast_pct', 'plasmablast', 'plasma_cell_pct')
    prior_fcrn = g(row, 'prior_fcrn_mgadl_delta', 'fcrn_response')

    # If igg_total absent but subclasses present, sum them
    if igg_total is None:
        subs = [x for x in (igg1, igg2, igg3, igg4) if x is not None]
        igg_total = sum(subs) if subs else None

    igg_val = igg_total or 0.0
    iga_val = iga or 0.0
    igm_val = igm or 0.0
    denom = igg_val + iga_val + igm_val

    # --- isotype composition -------------------------------------------------
    non_igg_fraction = None
    coverage = []
    if denom > 0 and (iga is not None or igm is not None):
        non_igg_fraction = round((iga_val + igm_val) / denom, 4)
        coverage.append('isotype')

    # --- IgG subclass profile ------------------------------------------------
    igg4_fraction = None
    sub_sum = sum(x for x in (igg1, igg2, igg3, igg4) if x is not None)
    if igg4 is not None and sub_sum > 0:
        igg4_fraction = round(igg4 / sub_sum, 4)
        coverage.append('subclass')

    complement_fixing = None
    if (igg1 is not None or igg3 is not None) and sub_sum > 0:
        complement_fixing = round(((igg1 or 0) + (igg3 or 0)) / sub_sum, 4)

    # --- BAFF/APRIL axis -----------------------------------------------------
    baff_april_elevated = None
    if baff is not None or april is not None:
        baff_april_elevated = (max(baff or 0, april or 0) >= ba_high)
        coverage.append('baff_april')

    # --- classification ------------------------------------------------------
    predicted_fcrn = 'unknown'
    telitacicept_candidate = False
    reasons = []

    if non_igg_fraction is not None:
        if non_igg_fraction >= non_igg_t:
            predicted_fcrn = 'refractory_risk'
            telitacicept_candidate = True
            reasons.append('non-IgG (IgA/IgM) fraction %.0f%% >= %.0f%% — FcRn blockade '
                           'cannot clear these isotypes' % (non_igg_fraction*100, non_igg_t*100))
        else:
            predicted_fcrn = 'likely_responsive'
            reasons.append('IgG-dominant (non-IgG %.0f%%) — FcRn blockade expected to '
                           'lower pathogenic pool' % (non_igg_fraction*100))

    if igg4_fraction is not None and igg4_fraction >= igg4_t:
        reasons.append('IgG4-predominant (%.0f%%) — mechanistically distinct (MuSK-like); '
                       'complement-independent' % (igg4_fraction*100))

    if baff_april_elevated:
        reasons.append('BAFF/APRIL elevated — additional rationale for dual BAFF-APRIL '
                       'blockade (telitacicept)')
        if predicted_fcrn in ('refractory_risk', 'unknown'):
            telitacicept_candidate = True

    if prior_fcrn is not None and prior_fcrn > -2.0 and non_igg_fraction is not None \\
            and non_igg_fraction >= non_igg_t:
        reasons.append('prior FcRn MG-ADL delta %.1f (sub-threshold) consistent with '
                       'isotype-driven non-response' % prior_fcrn)

    confidence = round(len(set(coverage)) / 3.0, 2)  # of 3 evidence classes

    patients.append({
        'patient_id': pid,
        'autoantibody_target': target,
        'non_igg_fraction': non_igg_fraction,
        'igg4_fraction': igg4_fraction,
        'complement_fixing_fraction': complement_fixing,
        'baff_april_elevated': baff_april_elevated,
        'predicted_fcrn_response': predicted_fcrn,
        'telitacicept_candidate': telitacicept_candidate,
        'confidence': confidence,
        'rationale': '; '.join(reasons) if reasons else 'insufficient isotype data',
        'evidence_classes': sorted(set(coverage)),
    })

# --- cohort-level summary (the number Vor Bio cares about) ------------------
n = len(patients)
scored = [p for p in patients if p['predicted_fcrn_response'] != 'unknown']
n_refractory = sum(1 for p in patients if p['predicted_fcrn_response'] == 'refractory_risk')
n_candidate  = sum(1 for p in patients if p['telitacicept_candidate'])
n_igg4       = sum(1 for p in patients if (p['igg4_fraction'] or 0) >= igg4_t)

summary = {
    'cohort': cohort,
    'n_patients': n,
    'n_evaluable_for_isotype': len(scored),
    'n_predicted_fcrn_refractory': n_refractory,
    'pct_predicted_fcrn_refractory': round(100.0 * n_refractory / len(scored), 1) if scored else None,
    'n_telitacicept_candidates': n_candidate,
    'pct_telitacicept_candidates': round(100.0 * n_candidate / n, 1) if n else None,
    'n_igg4_predominant': n_igg4,
    'thresholds': {'non_igg_fraction': non_igg_t, 'igg4_fraction': igg4_t,
                   'baff_april_high': ba_high},
    'interpretation': ('Patients flagged FcRn-refractory-risk carry an IgA/IgM '
                       'autoantibody contribution that FcRn inhibitors cannot clear, '
                       'and are the rational BAFF/APRIL (telitacicept) population.'),
}

with open('cohort_summary.json', 'w') as f:
    json.dump(summary, f, indent=2)

with open('stratification_results.json', 'w') as f:
    json.dump({'status': 'completed', 'cohort': cohort, 'summary': summary,
               'patients': patients}, f, indent=2)

cols = ['patient_id','autoantibody_target','non_igg_fraction','igg4_fraction',
        'complement_fixing_fraction','baff_april_elevated','predicted_fcrn_response',
        'telitacicept_candidate','confidence','rationale']
with open('patient_stratification.csv', 'w', newline='') as f:
    w = csv.writer(f); w.writerow(cols)
    for p in patients:
        w.writerow([p.get(c) if p.get(c) is not None else '' for c in cols])

def fmt(v): return '—' if v is None else (f'{v:.2f}' if isinstance(v, float) else str(v))
L = []
L.append(f'# Autoantibody-Isotype Stratification — {cohort}')
L.append('')
L.append(f'**Patients:** {n}  |  **Evaluable for isotype:** {len(scored)}  |  '
         f'**Predicted FcRn-refractory:** {n_refractory}'
         + (f' ({summary["pct_predicted_fcrn_refractory"]}%)' if scored else ''))
L.append('')
L.append('Stratifies an autoantibody-driven cohort by isotype composition to predict '
         'FcRn-inhibitor response and flag the BAFF/APRIL (telitacicept) population. '
         'FcRn blockade clears IgG only; a meaningful IgA/IgM contribution predicts '
         'non-response and is addressable by dual BAFF-APRIL depletion.')
L.append('')
L.append(f'> **Cohort readout:** {summary["pct_telitacicept_candidates"]}% of patients '
         f'({n_candidate}/{n}) are flagged as telitacicept candidates on isotype/BAFF-APRIL '
         'evidence — the FcRn-refractory subgroup this pathway is positioned to capture.')
L.append('')
L.append('## Per-patient stratification')
L.append('')
L.append('| Patient | Target | non-IgG | IgG4 | FcRn prediction | Telitacicept candidate |')
L.append('|---------|--------|--------:|-----:|-----------------|:----------------------:|')
for p in patients:
    L.append(f"| {p['patient_id']} | {p['autoantibody_target'] or '—'} | "
             f"{fmt(p['non_igg_fraction'])} | {fmt(p['igg4_fraction'])} | "
             f"{p['predicted_fcrn_response']} | {'YES' if p['telitacicept_candidate'] else '—'} |")
L.append('')
L.append('## Rationale (per flagged patient)')
L.append('')
for p in patients:
    if p['telitacicept_candidate']:
        L.append(f"- **{p['patient_id']}** ({p['autoantibody_target'] or 'target n/a'}, "
                 f"confidence {p['confidence']:.0%}): {p['rationale']}")
L.append('')
L.append('## Method')
L.append('')
L.append('non-IgG fraction = (IgA + IgM) / (IgG + IgA + IgM). Patients at/above the '
         f'non-IgG threshold ({non_igg_t:.0%}) are flagged FcRn-refractory-risk. IgG4 '
         f'fraction >= {igg4_t:.0%} flags mechanistically distinct (MuSK-like) disease. '
         'BAFF/APRIL elevation adds telitacicept rationale. Confidence reflects how many '
         'of three evidence classes (isotype, subclass, BAFF/APRIL) were available. '
         'Rankings are a decision aid — clinical review required.')

with open('stratification_report.md', 'w') as f:
    f.write('\\n'.join(L) + '\\n')

print(f'=== ISOTYPE STRATIFICATION: {cohort} — {n} patients, '
      f'{n_candidate} telitacicept candidates ({summary["pct_telitacicept_candidates"]}%) ===')
for p in patients:
    print(f"  {p['patient_id']:8} nonIgG={fmt(p['non_igg_fraction']):>5} "
          f"{p['predicted_fcrn_response']:16} telitacicept={'Y' if p['telitacicept_candidate'] else '-'}")

with open('versions.yml', 'w') as f:
    f.write('autoantibody_isotype_stratification:\\n')
    f.write('  python: "3.10"\\n')
    f.write('  basis: "FcRn IgG-selectivity + BAFF/APRIL isotype-broad depletion"\\n')
PYEOF
    """
}

workflow AUTOANTIBODY_ISOTYPE_WORKFLOW {
    take: meta_ch
    main: AUTOANTIBODY_ISOTYPE_STRATIFICATION(meta_ch)
    emit:
        results        = AUTOANTIBODY_ISOTYPE_STRATIFICATION.out.results
        stratification = AUTOANTIBODY_ISOTYPE_STRATIFICATION.out.stratification
        report         = AUTOANTIBODY_ISOTYPE_STRATIFICATION.out.report
}

workflow {
    meta = [id: 'isotype_run', single_end: false]
    Channel.value(meta) | AUTOANTIBODY_ISOTYPE_WORKFLOW
}
