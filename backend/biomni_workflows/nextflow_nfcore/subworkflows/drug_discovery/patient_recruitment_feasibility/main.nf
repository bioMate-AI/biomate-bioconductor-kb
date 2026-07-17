#!/usr/bin/env nextflow
/*
 * drug_discovery/patient_recruitment_feasibility
 *
 * Assesses patient recruitment feasibility for rare autoimmune and
 * neuromuscular disease trials. Queries:
 *   - ClinicalTrials.gov API v2 for competing active trials + historic
 *     enrollment rates by condition
 *   - Orphanet API for disease prevalence estimates by country
 *   - GBD-derived prevalence fallback for conditions not in Orphanet
 *
 * Outputs:
 *   feasibility_report.json     — overall go/caution/stop recommendation
 *   competing_trials.csv        — active trials on same condition
 *   prevalence_estimates.json   — population pool by region
 *   enrollment_benchmarks.json  — historic enrollment rate by trial phase
 */

nextflow.enable.dsl = 2

params.outdir           = './results'
params.condition        = 'Myasthenia Gravis'        // disease name for CT.gov search
params.orpha_code       = '589'                      // Orphanet numeric code (MG=589)
params.target_n         = '100'                      // required trial sample size
params.n_sites          = '20'                       // planned investigator sites
params.trial_phase      = 'Phase 2'                  // Phase 1|2|3
params.trial_duration_months = '24'                  // planned enrollment window
params.countries        = 'US,EU'                    // comma-separated region filter

process PATIENT_RECRUITMENT_FEASIBILITY {
    tag "$meta.id"
    label 'process_low'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("feasibility_report.json"),      emit: report
    tuple val(meta), path("competing_trials.csv"),         emit: trials
    tuple val(meta), path("prevalence_estimates.json"),    emit: prevalence
    tuple val(meta), path("enrollment_benchmarks.json"),   emit: benchmarks
    tuple val(meta), path("recruitment_output.txt"),       emit: output
    tuple val(meta), path("qc_metrics.json"),              emit: qc_metrics
    path "versions.yml",                                   emit: versions

    script:
    """
    export PARAM_CONDITION='${params.condition}'
    export PARAM_ORPHA_CODE='${params.orpha_code}'
    export PARAM_TARGET_N='${params.target_n}'
    export PARAM_N_SITES='${params.n_sites}'
    export PARAM_PHASE='${params.trial_phase}'
    export PARAM_DURATION='${params.trial_duration_months}'
    export PARAM_COUNTRIES='${params.countries}'

    python3 << 'PYEOF'
import json, os, csv, sys, math
try:
    import urllib.request as urlreq
    import urllib.parse as urlparse
except ImportError:
    pass

# -- Params --------------------------------------------------------------------
condition  = os.environ.get('PARAM_CONDITION', 'Myasthenia Gravis')
orpha_code = os.environ.get('PARAM_ORPHA_CODE', '589')
target_n   = int(os.environ.get('PARAM_TARGET_N', '100'))
n_sites    = int(os.environ.get('PARAM_N_SITES', '20'))
phase      = os.environ.get('PARAM_PHASE', 'Phase 2')
duration_m = int(os.environ.get('PARAM_DURATION', '24'))
countries  = os.environ.get('PARAM_COUNTRIES', 'US,EU')

# -- ClinicalTrials.gov API v2 -------------------------------------------------
def query_ct_gov(condition, phase, max_results=50):
    try:
        q = urlparse.quote(condition)
        phase_map = {'Phase 1': 'PHASE1', 'Phase 2': 'PHASE2', 'Phase 3': 'PHASE3'}
        phase_filter = phase_map.get(phase, 'PHASE2')
        url = (f"https://clinicaltrials.gov/api/v2/studies"
               f"?query.cond={q}&filter.overallStatus=RECRUITING,NOT_YET_RECRUITING,ACTIVE_NOT_RECRUITING"
               f"&filter.phase={phase_filter}&pageSize={max_results}&format=json")
        req  = urlreq.Request(url, headers={'Accept': 'application/json', 'User-Agent': 'BioMate/1.0'})
        with urlreq.urlopen(req, timeout=15) as r:
            data = json.load(r)
        studies = data.get('studies', [])
        trials = []
        for s in studies:
            proto = s.get('protocolSection', {})
            id_mod    = proto.get('identificationModule', {})
            status_mod= proto.get('statusModule', {})
            design_mod= proto.get('designModule', {})
            enroll_mod= status_mod.get('enrollmentInfo', {})
            trials.append({
                'nct_id':      id_mod.get('nctId', ''),
                'title':       id_mod.get('briefTitle', '')[:80],
                'status':      status_mod.get('overallStatus', ''),
                'phase':       ', '.join(design_mod.get('phases', [])),
                'enrollment':  enroll_mod.get('count', ''),
                'enroll_type': enroll_mod.get('type', ''),
                'start_date':  status_mod.get('startDateStruct', {}).get('date', ''),
            })
        return trials, None
    except Exception as e:
        return [], str(e)

# -- Orphanet prevalence -------------------------------------------------------
def query_orphanet(orpha_code):
    try:
        url = f"https://api.orphacode.org/EN/ClinicalEntity/orphacode/{orpha_code}/Prevalence"
        req = urlreq.Request(url, headers={'Accept': 'application/json', 'apiKey': 'default'})
        with urlreq.urlopen(req, timeout=10) as r:
            data = json.load(r)
        prevalences = []
        for item in data.get('Prevalence', []):
            prev_class = item.get('PrevalenceClass', {}).get('Name', '')
            prev_type  = item.get('PrevalenceType', {}).get('Name', '')
            geo        = item.get('PrevalenceGeographic', {}).get('Name', '')
            prevalences.append({'type': prev_type, 'class': prev_class, 'geography': geo})
        return prevalences, None
    except Exception as e:
        return [], str(e)

# Known rare disease prevalence fallbacks (per 100k, from published literature)
PREVALENCE_FALLBACK = {
    'myasthenia gravis':   {'per_100k': 20.0,  'source': 'Gilhus 2019, Neurology'},
    'cidp':                {'per_100k': 8.9,   'source': 'Broers 2019, J Neurol'},
    'mmn':                 {'per_100k': 1.0,   'source': 'Van Asseldonk 2005'},
    'gbs':                 {'per_100k': 1.2,   'source': 'Sejvar 2011 (annual incidence)'},
    'default':             {'per_100k': 5.0,   'source': 'Estimated'},
}

def get_prevalence_estimate(condition):
    key = condition.lower()
    for k, v in PREVALENCE_FALLBACK.items():
        if k in key:
            return v
    return PREVALENCE_FALLBACK['default']

# -- Historic enrollment rate benchmarks (per site per month, by phase) --------
# Source: Getz et al. 2018 Tufts CSDD; rare disease adjustment -40%
ENROLLMENT_BENCHMARKS = {
    'Phase 1': {'rate_per_site_month': 1.5, 'screen_to_enroll': 0.40},
    'Phase 2': {'rate_per_site_month': 0.8, 'screen_to_enroll': 0.30},
    'Phase 3': {'rate_per_site_month': 0.5, 'screen_to_enroll': 0.25},
}

# -- Run queries ---------------------------------------------------------------
trials, ct_err     = query_ct_gov(condition, phase)
orphanet, orph_err = query_orphanet(orpha_code)
prev_fallback      = get_prevalence_estimate(condition)
benchmarks         = ENROLLMENT_BENCHMARKS.get(phase, ENROLLMENT_BENCHMARKS['Phase 2'])

# -- Feasibility calculation ---------------------------------------------------
# Estimated monthly enrollment from sites
monthly_enroll = n_sites * benchmarks['rate_per_site_month']
months_needed  = math.ceil(target_n / monthly_enroll) if monthly_enroll > 0 else 999
feasibility_ratio = duration_m / months_needed if months_needed > 0 else 0

# Competing trial burden
n_competing = len([t for t in trials if t['status'] in ('RECRUITING', 'NOT_YET_RECRUITING')])
competition_adjustment = max(0.4, 1.0 - (n_competing * 0.08))
adjusted_months = math.ceil(months_needed / competition_adjustment)

# Prevalence pool
us_pop_m = 335  # million
eu_pop_m = 450
pop_m = (us_pop_m if 'US' in countries else 0) + (eu_pop_m if 'EU' in countries else 0)
if not pop_m: pop_m = us_pop_m
eligible_pool = int(pop_m * 10 * prev_fallback['per_100k'] / 100_000)  # rough 10% reachable

# Recommendation
if adjusted_months <= duration_m and eligible_pool > target_n * 5:
    recommendation = 'GO'
    rationale = (f"Projected enrollment in {adjusted_months} months within the {duration_m}-month window. "
                 f"Eligible pool (~{eligible_pool:,}) is sufficient relative to target N={target_n}.")
elif adjusted_months <= duration_m * 1.5:
    recommendation = 'CAUTION'
    rationale = (f"Enrollment may take {adjusted_months} months — feasible but tight against {duration_m}-month window. "
                 f"{n_competing} competing trials in {phase} detected; consider site expansion or competitive enrichment strategy.")
else:
    recommendation = 'STOP — redesign'
    rationale = (f"Enrollment projected at {adjusted_months} months, exceeding the {duration_m}-month window by >{duration_m*0.5:.0f} months. "
                 f"{n_competing} active competing trials and limited eligible pool (~{eligible_pool:,}). "
                 f"Recommend: increase sites, broaden eligibility criteria, or extend enrollment window.")

report = {
    'condition': condition, 'trial_phase': phase, 'target_n': target_n,
    'n_sites': n_sites, 'enrollment_duration_months': duration_m,
    'recommendation': recommendation, 'rationale': rationale,
    'projected_enrollment_months': adjusted_months,
    'unadjusted_months': months_needed,
    'n_competing_trials': n_competing,
    'competition_adjustment_factor': round(competition_adjustment, 2),
    'eligible_pool_estimate': eligible_pool,
    'prevalence_per_100k': prev_fallback['per_100k'],
    'prevalence_source': prev_fallback['source'],
    'monthly_enrollment_rate': round(monthly_enroll, 1),
    'screen_to_enroll_rate': benchmarks['screen_to_enroll'],
    'ct_gov_error': ct_err, 'orphanet_error': orph_err,
}

# -- Write outputs -------------------------------------------------------------
with open('feasibility_report.json', 'w') as f:
    json.dump(report, f, indent=2)

with open('competing_trials.csv', 'w', newline='') as f:
    if trials:
        w = csv.DictWriter(f, fieldnames=['nct_id','title','status','phase','enrollment','enroll_type','start_date'])
        w.writeheader(); w.writerows(trials)
    else:
        f.write('nct_id,title,status,phase,enrollment,enroll_type,start_date\\n')
        f.write(f'N/A,No trials retrieved ({ct_err}),,,,\\n')

with open('prevalence_estimates.json', 'w') as f:
    json.dump({'orphanet': orphanet, 'fallback': prev_fallback,
               'eligible_pool_estimate': eligible_pool, 'regions': countries}, f, indent=2)

with open('enrollment_benchmarks.json', 'w') as f:
    json.dump({'phase': phase, 'benchmarks': benchmarks,
               'source': 'Getz 2018 Tufts CSDD, rare disease adjusted'}, f, indent=2)

qc = {
    'recommendation': recommendation,
    'feasibility_ratio': round(duration_m / max(adjusted_months, 1), 2),
    'n_competing_trials': n_competing,
    'eligible_pool_vs_target': round(eligible_pool / max(target_n, 1), 1),
}
with open('qc_metrics.json', 'w') as f:
    json.dump(qc, f, indent=2)

lines = [
    f"=== PATIENT RECRUITMENT FEASIBILITY REPORT ===",
    f"Condition: {condition} | Phase: {phase} | Target N: {target_n}",
    f"Sites: {n_sites} | Window: {duration_m} months | Regions: {countries}", "",
    f"RECOMMENDATION: {recommendation}",
    f"Rationale: {rationale}", "",
    f"Enrollment projection: {adjusted_months} months (unadjusted: {months_needed} months)",
    f"  Monthly rate: {monthly_enroll:.1f} patients/month ({n_sites} sites x {benchmarks['rate_per_site_month']} per site)",
    f"  Competition factor: {n_competing} competing trials → {competition_adjustment:.0%} efficiency",
    f"  Eligible pool: ~{eligible_pool:,} ({prev_fallback['per_100k']}/100k, {countries})",
    "", f"Competing active trials found: {n_competing}",
    *[f"  {t['nct_id']}: {t['title'][:60]} [{t['status']}]" for t in trials[:10]],
]
report_text = '\\n'.join(lines)
with open('recruitment_output.txt', 'w') as f:
    f.write(report_text)
print(report_text)
PYEOF

    cat << 'EOF' > versions.yml
patient_recruitment_feasibility:
  python: "3.10"
  data_sources: "ClinicalTrials.gov API v2; Orphanet API; Getz 2018 Tufts CSDD benchmarks"
EOF
    """
}

workflow PATIENT_RECRUITMENT_FEASIBILITY_WORKFLOW {
    take: meta_ch
    main: PATIENT_RECRUITMENT_FEASIBILITY(meta_ch)
    emit:
        report = PATIENT_RECRUITMENT_FEASIBILITY.out.report
        trials = PATIENT_RECRUITMENT_FEASIBILITY.out.trials
}

workflow {
    meta = [id: 'recruitment_feasibility_run', single_end: false]
    Channel.value(meta) | PATIENT_RECRUITMENT_FEASIBILITY_WORKFLOW
}
