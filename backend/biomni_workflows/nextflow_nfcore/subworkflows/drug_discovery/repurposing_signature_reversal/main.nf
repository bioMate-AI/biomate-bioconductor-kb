#!/usr/bin/env nextflow
/*
 * drug_discovery/repurposing_signature_reversal
 *
 * REPURPOSING HYPOTHESES — the last AI-wheel spoke from the UCB target-discovery
 * workflow. Given a DISEASE signature (up/down genes) and a reference database of
 * PERTURBATION signatures (compounds / gene knockouts, LINCS/CMap-style), find the
 * perturbagens whose transcriptional effect REVERSES the disease signature — i.e.
 * they down-regulate what disease up-regulates and vice versa. Negative connectivity
 * = a repurposing candidate.
 *
 * Method: Connectivity Map enrichment (Lamb et al. Science 2006; Subramanian et al.
 * Cell 2017 for next-gen L1000/CMap). For each perturbagen, its genes are ranked by
 * effect; a Kolmogorov-Smirnov enrichment score is computed for the disease UP set
 * and the disease DOWN set. connectivity = (ES_up - ES_down)/2 (0 if same sign);
 * reversal_score = -connectivity, so high = strong reversal = candidate.
 *
 * INPUT (both REQUIRED — no synthetic fallback):
 *   --query_file      disease signature CSV: gene, logfc   (or gene, direction up/down)
 *   --reference_file  perturbation signatures CSV (long): perturbagen, gene, score
 * OUTPUT: repurposing_candidates.csv, repurposing_report.md, repurposing_results.json, versions.yml
 */

nextflow.enable.dsl = 2

params.outdir        = './results'
params.query_file    = 'NONE'     // REQUIRED disease signature (gene, logfc)
params.reference_file = 'NONE'    // REQUIRED perturbation signatures (perturbagen, gene, score)
params.disease       = 'unspecified disease'
params.up_threshold  = '1.0'      // logfc >= this => disease-up gene
params.down_threshold = '1.0'     // logfc <= -this => disease-down gene
params.top_n         = '25'       // how many candidates to highlight
params.min_matched   = '5'        // min matched signature genes to score a perturbagen

process REPURPOSING_SIGNATURE_REVERSAL {
    tag "$meta.id"
    label 'process_low'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/workflow-tools:x86' : 'biomate/workflow-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("repurposing_results.json"),   emit: results
    tuple val(meta), path("repurposing_candidates.csv"), emit: candidates
    tuple val(meta), path("repurposing_report.md"),      emit: report
    path "versions.yml",                                 emit: versions

    script:
    """
    export PARAM_QUERY='${params.query_file}'
    export PARAM_REF='${params.reference_file}'
    export PARAM_DISEASE='${params.disease}'
    export PARAM_UP_T='${params.up_threshold}'
    export PARAM_DOWN_T='${params.down_threshold}'
    export PARAM_TOPN='${params.top_n}'
    export PARAM_MINMATCH='${params.min_matched}'

    python3 << 'PYEOF'
import os, sys, json, csv

def _f(v, d=None):
    if v in (None, '', 'null', 'None', 'NA', 'nan'): return d
    try: return float(v)
    except Exception: return d

disease = os.environ.get('PARAM_DISEASE', 'unspecified disease')
up_t   = _f(os.environ.get('PARAM_UP_T'), 1.0)
down_t = _f(os.environ.get('PARAM_DOWN_T'), 1.0)
top_n  = int(_f(os.environ.get('PARAM_TOPN'), 25) or 25)
min_m  = int(_f(os.environ.get('PARAM_MINMATCH'), 5) or 5)
qpath  = os.environ.get('PARAM_QUERY', 'NONE')
rpath  = os.environ.get('PARAM_REF', 'NONE')

def fail(msg):
    with open('repurposing_results.json','w') as f:
        json.dump({'status':'failed','error':msg,'candidates':[]}, f, indent=2)
    with open('repurposing_candidates.csv','w') as f:
        f.write('perturbagen,reversal_score,connectivity,es_up,es_down,n_up_matched,n_down_matched\\n')
    with open('repurposing_report.md','w') as f:
        f.write('# Repurposing signature reversal — FAILED\\n\\n%s\\n' % msg)
    with open('versions.yml','w') as f:
        f.write('repurposing_signature_reversal:\\n  status: "failed"\\n')
    sys.exit(1)

for p, lbl in ((qpath,'query_file'), (rpath,'reference_file')):
    if (not p) or p in ('NONE','') or not os.path.exists(p):
        fail('--%s is required and must exist. No synthetic data is generated.' % lbl)

def col(row, *names):
    for n in names:
        for k in row:
            if k.strip().lower() == n:
                return row[k]
    return None

# ---- query disease signature -> up/down gene sets ----
up_set, down_set = set(), set()
with open(qpath, newline='') as fh:
    for r in csv.DictReader(fh):
        g = (col(r, 'gene', 'symbol', 'name') or '').strip().upper()
        if not g: continue
        lfc = _f(col(r, 'logfc', 'log2fc', 'lfc', 'score'))
        direction = (col(r, 'direction', 'sign') or '').strip().lower()
        if lfc is not None:
            if lfc >= up_t: up_set.add(g)
            elif lfc <= -down_t: down_set.add(g)
        elif direction in ('up','+','1'): up_set.add(g)
        elif direction in ('down','-','-1'): down_set.add(g)
if len(up_set) + len(down_set) < 2:
    fail('query signature has too few up/down genes at the given thresholds (up=%d down=%d)' % (len(up_set), len(down_set)))

# ---- reference perturbation signatures (long -> per-perturbagen) ----
ref = {}   # perturbagen -> list of (gene, score)
with open(rpath, newline='') as fh:
    for r in csv.DictReader(fh):
        pert = (col(r, 'perturbagen', 'perturbation', 'compound', 'drug', 'signature', 'pert_id') or '').strip()
        g = (col(r, 'gene', 'symbol', 'name') or '').strip().upper()
        sc = _f(col(r, 'score', 'logfc', 'log2fc', 'zscore', 'value'))
        if not pert or not g or sc is None: continue
        ref.setdefault(pert, []).append((g, sc))
if not ref:
    fail('reference_file produced no perturbagen signatures (need perturbagen, gene, score)')

# ---- CMap KS enrichment ----
def ks_es(positions, n):
    # positions: sorted 1-based ranks of gene-set members within the ranked list
    t = len(positions)
    if t == 0 or n == 0:
        return 0.0
    a = max(j / t - positions[j-1] / n for j in range(1, t+1))
    b = max(positions[j-1] / n - (j-1) / t for j in range(1, t+1))
    return a if a >= b else -b

results = []
for pert, genescores in ref.items():
    # rank this perturbagen's genes high->low by score
    ranked = [g for g, s in sorted(genescores, key=lambda x: x[1], reverse=True)]
    n = len(ranked)
    rank_of = {g: i+1 for i, g in enumerate(ranked)}
    up_pos = sorted(rank_of[g] for g in up_set if g in rank_of)
    dn_pos = sorted(rank_of[g] for g in down_set if g in rank_of)
    n_up, n_dn = len(up_pos), len(dn_pos)
    if (n_up + n_dn) < min_m:
        continue
    es_up = ks_es(up_pos, n)
    es_dn = ks_es(dn_pos, n)
    # Lamb 2006: 0 if same sign, else (es_up - es_down)/2
    conn = 0.0 if (es_up * es_dn) > 0 else (es_up - es_dn) / 2.0
    reversal = round(-conn, 4)   # high => perturbagen reverses the disease signature
    results.append({
        'perturbagen': pert, 'reversal_score': reversal, 'connectivity': round(conn, 4),
        'es_up': round(es_up, 4), 'es_down': round(es_dn, 4),
        'n_up_matched': n_up, 'n_down_matched': n_dn, 'n_ref_genes': n,
    })

if not results:
    fail('no perturbagen shared >= %d signature genes with the query' % min_m)

results.sort(key=lambda d: d['reversal_score'], reverse=True)
for i, d in enumerate(results, 1):
    d['rank'] = i

top = results[:top_n]

run = {'disease': disease, 'n_query_up': len(up_set), 'n_query_down': len(down_set),
       'n_perturbagens_scored': len(results),
       'method': 'Connectivity Map KS enrichment (Lamb 2006; Subramanian 2017)',
       'thresholds': {'up': up_t, 'down': down_t, 'min_matched': min_m}}

with open('repurposing_results.json','w') as f:
    json.dump({'status':'completed', 'run': run,
               'top_candidates': [d['perturbagen'] for d in top[:10]],
               'candidates': results}, f, indent=2)

cols = ['rank','perturbagen','reversal_score','connectivity','es_up','es_down',
        'n_up_matched','n_down_matched','n_ref_genes']
with open('repurposing_candidates.csv','w', newline='') as f:
    w = csv.writer(f); w.writerow(cols)
    for d in results:
        w.writerow([d[c] for c in cols])

L = []
L.append(f'# Repurposing Signature Reversal — {disease}')
L.append('')
L.append(f'**Query signature:** {len(up_set)} up / {len(down_set)} down genes  |  '
         f'**Perturbagens scored:** {len(results)}')
L.append('')
L.append('Perturbagens ranked by how strongly they REVERSE the disease signature '
         '(down-regulate disease-up genes and up-regulate disease-down genes). '
         'Negative Connectivity-Map connectivity = reversal = repurposing candidate. '
         'Rankings are hypotheses — confirm biologically and against known pharmacology.')
L.append('')
L.append('## Top reversal candidates')
L.append('')
L.append('| Rank | Perturbagen | Reversal score | Connectivity | ES up | ES down | matched (up/down) |')
L.append('|-----:|-------------|---------------:|-------------:|------:|--------:|:-----------------:|')
for d in top:
    L.append(f"| {d['rank']} | {d['perturbagen']} | {d['reversal_score']:.3f} | "
             f"{d['connectivity']:.3f} | {d['es_up']:.2f} | {d['es_down']:.2f} | "
             f"{d['n_up_matched']}/{d['n_down_matched']} |")
L.append('')
L.append('## Method')
L.append('')
L.append('Connectivity Map enrichment (Lamb et al. Science 2006; Subramanian et al. Cell '
         '2017). For each perturbagen, genes are ranked by effect and a Kolmogorov–Smirnov '
         'enrichment score is computed for the disease up- and down-gene sets; connectivity = '
         '(ES_up − ES_down)/2 (0 when the two enrichments share sign). A negative connectivity '
         'means the perturbagen opposes the disease signature; reversal_score = −connectivity.')
with open('repurposing_report.md','w') as f:
    f.write('\\n'.join(L) + '\\n')

print('=== REPURPOSING: %s | %d up / %d down | %d perturbagens | top: %s ===' % (
    disease, len(up_set), len(down_set), len(results),
    ', '.join(d['perturbagen'] for d in top[:5])))

with open('versions.yml','w') as f:
    f.write('repurposing_signature_reversal:\\n  python: "3.10"\\n  method: "Connectivity Map KS (Lamb 2006 / Subramanian 2017)"\\n')
PYEOF
    """
}

workflow REPURPOSING_WORKFLOW {
    take: meta_ch
    main: REPURPOSING_SIGNATURE_REVERSAL(meta_ch)
    emit:
        results    = REPURPOSING_SIGNATURE_REVERSAL.out.results
        candidates = REPURPOSING_SIGNATURE_REVERSAL.out.candidates
        report     = REPURPOSING_SIGNATURE_REVERSAL.out.report
}

workflow {
    meta = [id: 'repurposing_run', single_end: false]
    Channel.value(meta) | REPURPOSING_WORKFLOW
}
