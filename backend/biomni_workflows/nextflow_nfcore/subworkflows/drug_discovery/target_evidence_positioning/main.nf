#!/usr/bin/env nextflow
/*
 * drug_discovery/target_evidence_positioning
 *
 * Evidence-based target positioning for drug discovery.
 * Queries OpenTargets, ChEMBL, ClinicalTrials.gov, and PubMed in parallel
 * to score a target across three axes:
 *   1. Evidence strength  — genetic, expression, literature, animal model
 *   2. Competitive crowding — active drugs/trials on same target or pathway
 *   3. Clinical stage    — furthest advanced asset on this target
 *
 * Outputs a ranked positioning report with a 3-axis scorecard and
 * competitive landscape table.
 *
 * Outputs:
 *   positioning_report.json     — full scored report
 *   evidence_scorecard.csv      — per-dimension scores with sources
 *   competitive_landscape.csv   — existing drugs/trials on target/pathway
 *   positioning_output.txt      — human-readable summary
 */

nextflow.enable.dsl = 2

params.outdir         = './results'
params.target_name    = 'FCGRT'           // gene symbol (FcRn = FCGRT)
params.disease_name   = 'Myasthenia Gravis'
params.efo_id         = 'EFO_0000751'     // EFO/MONDO ID for OpenTargets disease lookup
params.pathway        = 'FcRn inhibition' // mechanistic pathway label for competitive grouping
params.modality       = 'biologic'        // biologic | small_molecule | both

process TARGET_EVIDENCE_POSITIONING {
    tag "$meta.id"
    label 'process_low'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("positioning_report.json"),    emit: report
    tuple val(meta), path("evidence_scorecard.csv"),     emit: scorecard
    tuple val(meta), path("competitive_landscape.csv"),  emit: landscape
    tuple val(meta), path("positioning_output.txt"),     emit: output
    tuple val(meta), path("qc_metrics.json"),            emit: qc_metrics
    path "versions.yml",                                 emit: versions

    script:
    """
    export PARAM_TARGET='${params.target_name}'
    export PARAM_DISEASE='${params.disease_name}'
    export PARAM_EFO='${params.efo_id}'
    export PARAM_PATHWAY='${params.pathway}'
    export PARAM_MODALITY='${params.modality}'

    python3 << 'PYEOF'
import json, os, csv, time
try:
    import urllib.request as urlreq
    import urllib.parse as urlparse
except ImportError:
    pass

target   = os.environ.get('PARAM_TARGET', 'FCGRT')
disease  = os.environ.get('PARAM_DISEASE', 'Myasthenia Gravis')
efo_id   = os.environ.get('PARAM_EFO', 'EFO_0000751')
pathway  = os.environ.get('PARAM_PATHWAY', 'FcRn inhibition')
modality = os.environ.get('PARAM_MODALITY', 'biologic')

def safe_get(url, headers=None, timeout=15):
    try:
        req = urlreq.Request(url, headers=headers or {'User-Agent': 'BioMate/1.0', 'Accept': 'application/json'})
        with urlreq.urlopen(req, timeout=timeout) as r:
            return json.load(r), None
    except Exception as e:
        return None, str(e)

def safe_post(url, payload, headers=None, timeout=15):
    try:
        data = json.dumps(payload).encode()
        req  = urlreq.Request(url, data=data,
                              headers={**(headers or {}),
                                       'Content-Type': 'application/json',
                                       'Accept': 'application/json',
                                       'User-Agent': 'BioMate/1.0'})
        with urlreq.urlopen(req, timeout=timeout) as r:
            return json.load(r), None
    except Exception as e:
        return None, str(e)

# -- 1. OpenTargets: target-disease association --------------------------------
OT_URL = "https://api.platform.opentargets.org/api/v4/graphql"
ot_query = {
    "query": """
    query TargetDisease($target: String!, $disease: String!) {
      target(ensemblId: $target) {
        id approvedSymbol approvedName
        associatedDiseases(
          filter: { ids: [$disease] }
          orderByScore: "score"
        ) {
          rows {
            disease { name id }
            score
            datatypeScores { id score }
          }
        }
        tractability {
          label modality value
        }
        safetyLiabilities { event biosample effects }
      }
    }""",
    "variables": {"target": "", "disease": efo_id}
}

# Try to find Ensembl ID from gene symbol via UniProt / OT search
search_url = f"https://api.platform.opentargets.org/api/v4/graphql"
search_q = {"query": f"""query {{ search(queryString: "{target}", entityNames: ["target"]) {{
    hits {{ id score object {{ ... on Target {{ approvedSymbol tractability {{ label modality value }}}} }} }}
}} }}"""}
ot_search, se = safe_post(OT_URL, search_q)
ensembl_id, ot_symbol, ot_tractability = None, target, []
if ot_search:
    hits = ot_search.get('data', {}).get('search', {}).get('hits', [])
    for h in hits:
        obj = h.get('object', {})
        if obj.get('approvedSymbol', '').upper() == target.upper():
            ensembl_id = h['id']
            ot_tractability = obj.get('tractability', [])
            break

ot_score, ot_datatypes, ot_safety, ot_error = 0.0, [], [], se
if ensembl_id:
    ot_query['variables']['target'] = ensembl_id
    ot_data, ot_error = safe_post(OT_URL, ot_query)
    if ot_data:
        tgt = ot_data.get('data', {}).get('target', {})
        rows = tgt.get('associatedDiseases', {}).get('rows', [])
        if rows:
            ot_score = rows[0].get('score', 0.0)
            ot_datatypes = rows[0].get('datatypeScores', [])
        ot_safety = tgt.get('safetyLiabilities', [])
        ot_tractability = tgt.get('tractability', ot_tractability)

# -- 2. ChEMBL: drugs on this target ------------------------------------------
chembl_target_url = f"https://www.ebi.ac.uk/chembl/api/data/target/search.json?q={urlparse.quote(target)}&limit=5"
chembl_tgt, ce = safe_get(chembl_target_url)
chembl_target_id = None
if chembl_tgt:
    results = chembl_tgt.get('targets', [])
    for r in results:
        if r.get('pref_name', '').upper() == target.upper() or target.upper() in r.get('pref_name','').upper():
            chembl_target_id = r.get('target_chembl_id')
            break
    if not chembl_target_id and results:
        chembl_target_id = results[0].get('target_chembl_id')

drugs_on_target = []
if chembl_target_id:
    mech_url = f"https://www.ebi.ac.uk/chembl/api/data/mechanism.json?target_chembl_id={chembl_target_id}&limit=50"
    mech_data, _ = safe_get(mech_url)
    if mech_data:
        for m in mech_data.get('mechanisms', []):
            drugs_on_target.append({
                'molecule': m.get('molecule_chembl_id', ''),
                'mechanism': m.get('mechanism_of_action', ''),
                'action_type': m.get('action_type', ''),
                'max_phase': m.get('max_phase', 0),
            })

n_approved = len([d for d in drugs_on_target if d.get('max_phase') == 4])
n_clinical = len([d for d in drugs_on_target if d.get('max_phase', 0) >= 2])
max_phase  = max([d.get('max_phase', 0) for d in drugs_on_target], default=0)

# -- 3. ClinicalTrials.gov: active trials on condition + target/pathway --------
q_disease = urlparse.quote(disease)
q_target  = urlparse.quote(target)
ct_url = (f"https://clinicaltrials.gov/api/v2/studies"
          f"?query.cond={q_disease}&query.intr={q_target}"
          f"&filter.overallStatus=RECRUITING,ACTIVE_NOT_RECRUITING,NOT_YET_RECRUITING"
          f"&pageSize=30&format=json")
ct_data, ct_err = safe_get(ct_url)
active_trials = []
if ct_data:
    for s in ct_data.get('studies', []):
        proto = s.get('protocolSection', {})
        id_m  = proto.get('identificationModule', {})
        st_m  = proto.get('statusModule', {})
        de_m  = proto.get('designModule', {})
        active_trials.append({
            'nct_id':   id_m.get('nctId',''),
            'title':    id_m.get('briefTitle','')[:70],
            'status':   st_m.get('overallStatus',''),
            'phase':    ', '.join(de_m.get('phases', [])),
        })
n_active_trials = len(active_trials)

# Broader pathway trial count
ct_pathway_url = (f"https://clinicaltrials.gov/api/v2/studies"
                  f"?query.cond={q_disease}&query.intr={urlparse.quote(pathway)}"
                  f"&filter.overallStatus=RECRUITING,ACTIVE_NOT_RECRUITING&pageSize=50&format=json")
ct_pathway, _ = safe_get(ct_pathway_url)
n_pathway_trials = len((ct_pathway or {}).get('studies', []))

# -- 4. PubMed: literature evidence volume ------------------------------------
pubmed_url = (f"https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi"
              f"?db=pubmed&term={urlparse.quote(target+'[tiab] AND '+disease+'[tiab]')}"
              f"&retmode=json&retmax=0")
pm_data, pm_err = safe_get(pubmed_url)
n_publications = int((pm_data or {}).get('esearchresult', {}).get('count', 0))

# Trend: last 3 years
from datetime import datetime
year = datetime.now().year
pubmed_trend_url = (f"https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi"
                    f"?db=pubmed&term={urlparse.quote(target+'[tiab] AND '+disease+'[tiab]')}"
                    f"&mindate={year-3}&maxdate={year}&retmode=json&retmax=0")
pm_trend, _ = safe_get(pubmed_trend_url)
n_recent_pubs = int((pm_trend or {}).get('esearchresult', {}).get('count', 0))

# -- 5. Score across 3 axes (0-1) ---------------------------------------------
# Axis 1: Evidence strength
genetic_score  = next((d['score'] for d in ot_datatypes if 'genetic' in d.get('id','').lower()), 0)
expr_score     = next((d['score'] for d in ot_datatypes if 'expression' in d.get('id','').lower()), 0)
lit_score      = min(1.0, n_publications / 100)
lit_trend      = min(1.0, n_recent_pubs / 30)
evidence_score = round((ot_score * 0.40 + genetic_score * 0.25 + lit_score * 0.20 + lit_trend * 0.15), 3)

# Axis 2: Competitive crowding (high = saturated)
crowding_raw   = min(1.0, (n_approved * 0.3 + n_clinical * 0.1 + n_active_trials * 0.05 + n_pathway_trials * 0.03))
crowding_score = round(crowding_raw, 3)

# Axis 3: Clinical stage of furthest asset (normalised 0-1)
stage_map = {0: 0.0, 1: 0.25, 2: 0.50, 3: 0.75, 4: 1.0}
clinical_stage_score = round(stage_map.get(int(max_phase), 0.0), 3)

# Opportunity score: high evidence + low crowding + room to differentiate
opportunity_score = round(evidence_score * (1 - crowding_score * 0.5) * (1 - clinical_stage_score * 0.3), 3)

# Tractability
tractable_sm  = any(t.get('modality','') == 'SmallMolecule' and t.get('value') for t in ot_tractability)
tractable_ab  = any(t.get('modality','') == 'Antibody'     and t.get('value') for t in ot_tractability)

# Safety flags
safety_flags = [s.get('event','') for s in ot_safety[:3]]

# -- Positioning verdict -------------------------------------------------------
if opportunity_score >= 0.50:
    verdict = 'HIGH OPPORTUNITY — strong evidence, differentiation space exists'
elif opportunity_score >= 0.30:
    verdict = 'MODERATE — solid evidence but competitive pressure; differentiation strategy required'
elif crowding_score >= 0.70:
    verdict = 'SATURATED — crowded landscape; late entrant positioning needed or indication pivot'
else:
    verdict = 'LOW EVIDENCE — exploratory; high risk, high reward if target is validated'

report = {
    'target': target, 'disease': disease, 'pathway': pathway,
    'opentargets_score': ot_score, 'ensembl_id': ensembl_id,
    'evidence_score': evidence_score, 'crowding_score': crowding_score,
    'clinical_stage_score': clinical_stage_score, 'opportunity_score': opportunity_score,
    'verdict': verdict,
    'n_approved_drugs': n_approved, 'n_clinical_drugs': n_clinical,
    'max_clinical_phase': max_phase, 'n_active_trials': n_active_trials,
    'n_pathway_trials': n_pathway_trials,
    'n_publications': n_publications, 'n_recent_publications_3yr': n_recent_pubs,
    'tractable_small_molecule': tractable_sm, 'tractable_antibody': tractable_ab,
    'safety_flags': safety_flags,
    'errors': {k: v for k, v in {'opentargets': ot_error, 'chembl': ce,
                                   'clinicaltrials': ct_err, 'pubmed': pm_err}.items() if v},
}

scorecard_rows = [
    {'dimension': 'OpenTargets association score', 'score': ot_score,         'source': 'OpenTargets Platform', 'weight': 0.40},
    {'dimension': 'Genetic evidence',              'score': genetic_score,    'source': 'OpenTargets genetics datasource', 'weight': 0.25},
    {'dimension': 'Literature volume',             'score': lit_score,        'source': f'PubMed n={n_publications}', 'weight': 0.20},
    {'dimension': 'Literature trend (3yr)',        'score': lit_trend,        'source': f'PubMed n={n_recent_pubs} recent', 'weight': 0.15},
    {'dimension': 'Competitive crowding',          'score': crowding_score,   'source': 'ChEMBL + ClinicalTrials.gov', 'weight': None},
    {'dimension': 'Clinical stage (furthest)',     'score': clinical_stage_score, 'source': f'ChEMBL max_phase={max_phase}', 'weight': None},
    {'dimension': 'OPPORTUNITY SCORE',             'score': opportunity_score,'source': 'Composite', 'weight': None},
]

# -- Write outputs -------------------------------------------------------------
with open('positioning_report.json', 'w') as f: json.dump(report, f, indent=2)

with open('evidence_scorecard.csv', 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=['dimension','score','source','weight'])
    w.writeheader(); w.writerows(scorecard_rows)

with open('competitive_landscape.csv', 'w', newline='') as f:
    all_landscape = drugs_on_target[:20] + [{'molecule': t['nct_id'], 'mechanism': t['title'],
                                              'action_type': t['phase'], 'max_phase': t['status']}
                                             for t in active_trials[:10]]
    w = csv.DictWriter(f, fieldnames=['molecule','mechanism','action_type','max_phase'])
    w.writeheader(); w.writerows(all_landscape or [{'molecule':'N/A','mechanism':'No data','action_type':'','max_phase':''}])

qc = {'opportunity_score': opportunity_score, 'verdict': verdict,
      'evidence_score': evidence_score, 'crowding_score': crowding_score}
with open('qc_metrics.json', 'w') as f: json.dump(qc, f, indent=2)

lines = [
    f"=== TARGET EVIDENCE POSITIONING REPORT ===",
    f"Target: {target} | Disease: {disease} | Pathway: {pathway}", "",
    f"VERDICT: {verdict}", f"Opportunity score: {opportunity_score:.3f}", "",
    f"Evidence (score {evidence_score:.2f}):",
    f"  OpenTargets association: {ot_score:.3f}",
    f"  Genetic evidence: {genetic_score:.3f}",
    f"  Publications: {n_publications} total, {n_recent_pubs} last 3yr",
    f"  Tractability: SM={tractable_sm}, Antibody={tractable_ab}", "",
    f"Competitive landscape (score {crowding_score:.2f}):",
    f"  Approved drugs on target: {n_approved}",
    f"  Clinical-stage drugs (Ph2+): {n_clinical}, max phase: {max_phase}",
    f"  Active trials on target/disease: {n_active_trials}",
    f"  Active trials on pathway ({pathway}): {n_pathway_trials}", "",
]
if safety_flags:
    lines.append(f"Safety flags: {', '.join(safety_flags)}")
if active_trials[:5]:
    lines.append("Top active trials:")
    for t in active_trials[:5]:
        lines.append(f"  {t['nct_id']}: {t['title'][:60]} [{t['phase']}]")

with open('positioning_output.txt', 'w') as f: f.write('\\n'.join(lines))
print('\\n'.join(lines))
PYEOF

    cat << 'EOF' > versions.yml
target_evidence_positioning:
  python: "3.10"
  data_sources: "OpenTargets Platform GraphQL v4; ChEMBL REST v1; ClinicalTrials.gov API v2; PubMed E-utilities"
  scoring: "3-axis: evidence strength x competitive crowding x clinical stage"
EOF
    """
}

workflow TARGET_EVIDENCE_POSITIONING_WORKFLOW {
    take: meta_ch
    main: TARGET_EVIDENCE_POSITIONING(meta_ch)
    emit:
        report    = TARGET_EVIDENCE_POSITIONING.out.report
        scorecard = TARGET_EVIDENCE_POSITIONING.out.scorecard
}

workflow {
    meta = [id: 'target_positioning_run', single_end: false]
    Channel.value(meta) | TARGET_EVIDENCE_POSITIONING_WORKFLOW
}
