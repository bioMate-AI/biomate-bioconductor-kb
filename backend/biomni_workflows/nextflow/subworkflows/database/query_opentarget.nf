#!/usr/bin/env nextflow
/*
 * biomni_database_query_opentarget
 *
 * Query the Open Targets Platform GraphQL API (https://api.platform.opentargets.org)
 * for a disease's associated targets and emit a per-target evidence table in the
 * schema consumed by `target_scorecard_ranker`.
 *
 * Previously this was a stub (touched an empty file). It now performs the real
 * query: disease name -> EFO/MONDO id (search) -> associatedTargets with
 * datatype scores + tractability + safety liabilities.
 *
 * Mapping to scorecard evidence axes:
 *   genetic_support      <- datatypeScores['genetic_association']  (0-1)
 *   biological_relevance <- overall association score              (0-1)
 *   tractability         <- highest achieved Open Targets tractability bucket
 *   safety_liability     <- normalised count of safetyLiabilities  (min(1, n/3))
 * (cell_specificity / expression_* are left empty — supplied by other tools.)
 *
 * Docker: biomate/biotools:latest  (stdlib-only python3 — also runs under
 *          `-profile standard` on the host for local verification.)
 */

nextflow.enable.dsl = 2

params.disease            = 'rheumatoid arthritis'   // name OR EFO_/MONDO_ id
params.efo_id             = 'NONE'                    // explicit id overrides name resolution
params.n_targets          = 25
params.min_association    = 0.0                       // drop rows below this overall score
params.outdir             = './results'

process QUERY_OPENTARGET {
    tag "${params.disease}"
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biotools:latest'

    output:
    path("target_evidence.csv"),            emit: evidence
    path("target_prioritisation.csv"),      emit: prioritisation
    path("query_opentarget_output.json"),   emit: json
    path("query_opentarget_output.txt"),    emit: output
    path("versions.yml"),                   emit: versions

    script:
    """
    export PARAM_DISEASE='${params.disease.toString().replace("'", "'\\''")}'
    export PARAM_EFO='${params.efo_id.toString().replace("'", "'\\''")}'
    export PARAM_N='${params.n_targets}'
    export PARAM_MINSCORE='${params.min_association}'

    python3 << 'PYEOF'
import os, sys, json, csv, urllib.request

API = "https://api.platform.opentargets.org/api/v4/graphql"

def gql(query, variables=None, timeout=45):
    payload = json.dumps({"query": query, "variables": variables or {}}).encode()
    req = urllib.request.Request(API, data=payload,
                                 headers={"Content-Type": "application/json",
                                          "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        body = json.load(resp)
    if body.get("errors"):
        raise RuntimeError("OpenTargets GraphQL errors: " + json.dumps(body["errors"])[:400])
    return body["data"]

disease_in = os.environ.get("PARAM_DISEASE", "").strip()
efo_in     = os.environ.get("PARAM_EFO", "NONE").strip()
n_targets  = int(os.environ.get("PARAM_N", "25") or 25)
min_score  = float(os.environ.get("PARAM_MINSCORE", "0.0") or 0.0)

EVIDENCE_COLS = ['gene','genetic_support','cell_specificity','expression_lfc',
                 'expression_padj','biological_relevance','tractability',
                 'safety_liability','disease_cell_type','notes']

def write_failed(msg, efo=None, disease=None):
    with open("query_opentarget_output.json","w") as f:
        json.dump({"status":"failed","error":msg,"disease":disease,"efo_id":efo,
                   "n_targets":0,"targets":[]}, f, indent=2)
    with open("target_evidence.csv","w",newline="") as f:
        csv.writer(f).writerow(EVIDENCE_COLS)          # header only, never fabricate rows
    with open("query_opentarget_output.txt","w") as f:
        f.write("QUERY_OPENTARGET FAILED: %s\\n" % msg)
    with open("versions.yml","w") as f:
        f.write('query_opentarget:\\n  api: "Open Targets Platform GraphQL v4"\\n  status: "failed"\\n')

# --- 1. resolve disease -> EFO/MONDO id -------------------------------------
try:
    if efo_in and efo_in not in ("NONE",""):
        efo = efo_in
        disease_name = disease_in or efo_in
    elif disease_in and (disease_in.startswith("EFO_") or disease_in.startswith("MONDO_")
                         or disease_in.startswith("HP_") or disease_in.startswith("Orphanet_")):
        efo = disease_in
        disease_name = disease_in
    else:
        q = ('query { search(queryString:%s, entityNames:["disease"], '
             'page:{index:0,size:1}){ hits{ id name entity } } }' % json.dumps(disease_in))
        hits = gql(q).get("search",{}).get("hits",[])
        if not hits:
            write_failed("No disease match for '%s' in Open Targets" % disease_in, disease=disease_in)
            sys.exit(1)
        efo = hits[0]["id"]; disease_name = hits[0]["name"]
except Exception as e:
    write_failed("disease resolution error: %s" % e, disease=disease_in); sys.exit(1)

# --- 2. associated targets + evidence ---------------------------------------
Q_ASSOC = ('query { disease(efoId:%s){ id name '
           'associatedTargets(page:{index:0,size:%d}){ count '
           'rows{ score datatypeScores{ id score } '
           'target{ id approvedSymbol '
           'prioritisation{ items{ key value } } } } } } }' % (json.dumps(efo), n_targets))
try:
    d = gql(Q_ASSOC)
except Exception as e:
    write_failed("associatedTargets query error: %s" % e, efo=efo, disease=disease_name); sys.exit(1)

disease_obj = d.get("disease")
if not disease_obj:
    write_failed("EFO id '%s' not found in Open Targets" % efo, efo=efo, disease=disease_name); sys.exit(1)

rows = disease_obj["associatedTargets"]["rows"]
total = disease_obj["associatedTargets"]["count"]

def norm(x):
    return None if x is None else round(max(0.0, min(1.0, float(x))), 4)

def _f(v, default=None):
    if v in (None, '', 'null', 'None'):
        return default
    try:
        return float(v)
    except Exception:
        return default

# Open Targets methodology (Ochoa 2021/2023, Buniello 2025):
#   biological_relevance = OT-normalised HARMONIC SUM of datatype scores.
#   DISCOVERY weight profile: the known-drug ('clinical') datatype is set to weight
#   0 (excluded) so novel mechanism targets lead rather than already-drugged
#   symptomatic ones (e.g. K-channels hit by 3,4-diaminopyridine in MG); this is a
#   valid OT datatype-weight adjustment. genetic_association is carried as its own
#   axis (genetic_support), not double-counted here. Normalisation is by the
#   UNWEIGHTED theoretical max (sum 1/i^2).
BIO_DATATYPES = ('literature', 'animal_model', 'rna_expression',
                 'affected_pathway', 'somatic_mutation')   # clinical excluded (w=0)

def ot_harmonic(scores):
    s = sorted((v for v in scores if v is not None), reverse=True)
    if not s:
        return None
    hs = sum(v / ((i + 1) ** 2) for i, v in enumerate(s))
    hs_max = sum(1.0 / ((i + 1) ** 2) for i in range(len(s)))
    return hs / hs_max

# OT Target-Prioritisation panel keys (traffic-light, -1..1)
TRACT_KEYS  = ('hasLigand', 'hasPocket', 'hasSmallMoleculeBinder')
SAFETY_KEYS = ('geneticConstraint', 'mouseKOScore', 'geneEssentiality',
               'hasSafetyEvent', 'isCancerDriverGene', 'paralogMaxIdentityPercentage')
PANEL_KEYS  = ('maxClinicalStage', 'hasLigand', 'hasPocket', 'hasSmallMoleculeBinder',
               'isInMembrane', 'isSecreted', 'mouseOrthologMaxIdentityPercentage',
               'geneticConstraint', 'mouseKOScore', 'geneEssentiality', 'hasSafetyEvent',
               'isCancerDriverGene', 'paralogMaxIdentityPercentage',
               'tissueSpecificity', 'tissueDistribution')

evidence = []
panel = []
for r in rows:
    if r["score"] < min_score:
        continue
    t = r["target"]
    dts = {x["id"]: x["score"] for x in (r.get("datatypeScores") or [])}
    prio = {it["key"]: _f(it["value"])
            for it in ((t.get("prioritisation") or {}).get("items") or [])}

    biol = ot_harmonic([dts.get(k) for k in BIO_DATATYPES])

    tvals = [max(0.0, prio[k]) for k in TRACT_KEYS if prio.get(k) is not None]
    tract = round(sum(tvals) / len(tvals), 3) if tvals else None

    svals = [max(0.0, -prio[k]) for k in SAFETY_KEYS if prio.get(k) is not None]
    safety = round(sum(svals) / len(svals), 3) if svals else None

    evidence.append({
        'gene': t["approvedSymbol"],
        'ensembl_id': t["id"],
        'genetic_support': norm(dts.get("genetic_association")),
        'cell_specificity': None,
        'expression_lfc': None,
        'expression_padj': None,
        'biological_relevance': norm(biol),
        'tractability': tract,
        'safety_liability': safety,
        'disease_cell_type': '',
        'notes': "OT assoc=%.3f; datatypes=%s; maxClinicalStage=%s" % (
            r["score"], ",".join("%s:%.2f" % (k, v) for k, v in sorted(dts.items())),
            prio.get('maxClinicalStage')),
    })
    panel.append({'gene': t["approvedSymbol"], **{k: prio.get(k) for k in PANEL_KEYS}})

# --- 3. write outputs (scorecard evidence schema) ---------------------------
with open("target_evidence.csv","w",newline="") as f:
    w = csv.writer(f); w.writerow(EVIDENCE_COLS)
    for e in evidence:
        w.writerow([e[c] if e.get(c) is not None else '' for c in EVIDENCE_COLS])

# OT Target-Prioritisation panel (traffic-light factors) — shown ALONGSIDE the
# ranking, never summed into it (Open Targets two-layer model).
with open("target_prioritisation.csv","w",newline="") as f:
    cols = ['gene'] + list(PANEL_KEYS)
    w = csv.writer(f); w.writerow(cols)
    for p in panel:
        w.writerow([p.get(c) if p.get(c) is not None else '' for c in cols])

with open("query_opentarget_output.json","w") as f:
    json.dump({"status":"completed","disease":disease_name,"efo_id":efo,
               "total_associated_targets":total,"n_returned":len(evidence),
               "source":"Open Targets Platform GraphQL v4","targets":evidence}, f, indent=2)

with open("query_opentarget_output.txt","w") as f:
    f.write("Open Targets — %s (%s): %d of %d associated targets\\n\\n" % (
        disease_name, efo, len(evidence), total))
    for e in evidence:
        f.write("  %-10s genetic=%s assoc=%s tract=%s safety=%s\\n" % (
            e['gene'], e['genetic_support'], e['biological_relevance'],
            e['tractability'], e['safety_liability']))

with open("versions.yml","w") as f:
    f.write('query_opentarget:\\n  api: "Open Targets Platform GraphQL v4"\\n  status: "completed"\\n')

print("Open Targets: %s (%s) -> %d/%d targets" % (disease_name, efo, len(evidence), total))
PYEOF
    """
}

workflow BIOMNI_DATABASE_QUERY_OPENTARGET {
    main:
        QUERY_OPENTARGET()
    emit:
        evidence = QUERY_OPENTARGET.out.evidence
        output   = QUERY_OPENTARGET.out.output
}

workflow {
    BIOMNI_DATABASE_QUERY_OPENTARGET()
}
