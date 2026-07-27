#!/usr/bin/env nextflow
/*
 * single_cell/integration_benchmark
 *
 * THE HARMONIZATION SELECT-AND-EVALUATE SCORER (the productizable wedge).
 *
 * There is no universal-best batch-integration method — every method trades batch
 * removal against biological-signal preservation, and OVER-CORRECTION (erasing
 * biology while mixing batches) is a real failure mode. This workflow scores an
 * integrated embedding on BOTH objectives (scIB two-objective harness) so the right
 * method can be selected and over-correction detected — turning "we ran Harmony"
 * into "we chose the method that removed batch WITHOUT erasing biology, and here's
 * the score."
 *
 * Metrics (unweighted kNN / silhouette approximations of the scIB definitions):
 *   BATCH REMOVAL (want high):   iLISI (batch mixing), ASW-batch score
 *   BIOLOGY CONSERVATION (high): cLISI-derived purity, ASW-celltype score
 *   -> verdict: WELL-INTEGRATED / OVER-CORRECTED / UNDER-CORRECTED / POOR
 *
 * References: Luecken et al. 2022 scIB (Nat Methods); Korsunsky et al. 2019 (LISI,
 * Harmony); Tran et al. 2020 (batch-integration benchmark).
 *
 * INPUT (REQUIRED): embedding CSV: cell_id, dim1..dimN, batch, celltype
 * OUTPUT: integration_metrics.json, integration_report.md, per_cell_lisi.csv, versions.yml
 */

nextflow.enable.dsl = 2

params.outdir         = './results'
params.embedding_file = 'NONE'   // REQUIRED: cell_id, dim1..dimN, batch, celltype
params.method_name    = 'integration'
params.k              = '30'     // neighbours for LISI
params.batch_weight   = '0.5'    // scIB overall = batch_weight*batch_removal + (1-batch_weight)*bio
params.good_threshold = '0.6'    // per-objective score at/above which the objective is "met"

process INTEGRATION_BENCHMARK {
    tag "$meta.id"
    label 'process_low'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("integration_metrics.json"), emit: results
    tuple val(meta), path("integration_report.md"),    emit: report
    tuple val(meta), path("per_cell_lisi.csv"),        emit: lisi
    path "versions.yml",                               emit: versions

    script:
    """
    export PARAM_EMB='${params.embedding_file}'
    export PARAM_METHOD='${params.method_name}'
    export PARAM_K='${params.k}'
    export PARAM_BW='${params.batch_weight}'
    export PARAM_GT='${params.good_threshold}'

    python3 << 'PYEOF'
import os, sys, json, csv, math

def _f(v, d=None):
    if v in (None,'','null','None','NA','nan'): return d
    try: return float(v)
    except Exception: return d

emb_path = os.environ.get('PARAM_EMB','NONE')
method   = os.environ.get('PARAM_METHOD','integration')
K        = int(_f(os.environ.get('PARAM_K'),30) or 30)
bw       = _f(os.environ.get('PARAM_BW'),0.5)
good_t   = _f(os.environ.get('PARAM_GT'),0.6)

def fail(msg):
    with open('integration_metrics.json','w') as f:
        json.dump({'status':'failed','error':msg}, f, indent=2)
    with open('per_cell_lisi.csv','w') as f: f.write('cell_id,iLISI,cLISI\\n')
    with open('integration_report.md','w') as f: f.write('# integration_benchmark FAILED\\n\\n%s\\n'%msg)
    with open('versions.yml','w') as f: f.write('integration_benchmark:\\n  status: "failed"\\n')
    sys.exit(1)

if (not emb_path) or emb_path in ('NONE','') or not os.path.exists(emb_path):
    fail('--embedding_file is required (cell_id, dim1..dimN, batch, celltype). No synthetic data.')

cells=[]; coords=[]; batch=[]; ctype=[]
with open(emb_path, newline='') as fh:
    rdr = csv.DictReader(fh)
    cols = rdr.fieldnames or []
    lc = {c.lower(): c for c in cols}
    bcol = lc.get('batch'); ccol = lc.get('celltype') or lc.get('cell_type') or lc.get('label')
    idcol = lc.get('cell_id') or lc.get('cell') or lc.get('id')
    dim_cols = [c for c in cols if c not in (bcol, ccol, idcol) and _looks_num_hdr(c)] if False else None
    # dimension columns = everything numeric that isn't batch/celltype/id
    dim_cols = [c for c in cols if c not in (bcol, ccol, idcol)]
    for i,r in enumerate(rdr):
        vec=[]
        ok=True
        for c in dim_cols:
            v=_f(r.get(c))
            if v is None: ok=False; break
            vec.append(v)
        if not ok or bcol is None or ccol is None: continue
        cells.append(r.get(idcol) or ('cell%d'%i))
        coords.append(vec); batch.append(str(r.get(bcol))); ctype.append(str(r.get(ccol)))

n=len(coords)
if n < 10: fail('too few cells (%d) with complete embedding + labels'%n)
k=min(K, n-1)

def dist2(a,b): return sum((a[i]-b[i])**2 for i in range(len(a)))

# kNN indices (brute force; fine for cohort-scale eval)
knn=[]
for i in range(n):
    ds=sorted(((dist2(coords[i],coords[j]), j) for j in range(n) if j!=i))
    knn.append([j for _,j in ds[:k]])

def inv_simpson(labels):
    from collections import Counter
    c=Counter(labels); tot=len(labels)
    return 1.0/sum((v/tot)**2 for v in c.values())

batches=sorted(set(batch)); ctypes=sorted(set(ctype))
nb=len(batches); nc=len(ctypes)
if nb<2: fail('need >=2 batches to assess batch mixing (found %d)'%nb)

iLISI=[]; cLISI=[]
for i in range(n):
    iLISI.append(inv_simpson([batch[j] for j in knn[i]]))
    cLISI.append(inv_simpson([ctype[j] for j in knn[i]]))
ilisi=sum(iLISI)/n; clisi=sum(cLISI)/n
# normalise: iLISI in [1,nb] -> [0,1] (high=mixed=good); cLISI in [1,nc] -> purity (high=pure=good)
ilisi_score = (ilisi-1)/(nb-1) if nb>1 else 0.0
clisi_purity = 1.0 - (clisi-1)/(nc-1) if nc>1 else 1.0

# silhouette by a grouping
def asw(labels):
    groups={}
    for idx,l in enumerate(labels): groups.setdefault(l,[]).append(idx)
    if len(groups)<2: return 0.0
    ss=[]
    for i in range(n):
        li=labels[i]
        same=[math.sqrt(dist2(coords[i],coords[j])) for j in groups[li] if j!=i]
        a=sum(same)/len(same) if same else 0.0
        b=math.inf
        for l,idxs in groups.items():
            if l==li: continue
            d=[math.sqrt(dist2(coords[i],coords[j])) for j in idxs]
            if d: b=min(b, sum(d)/len(d))
        if b==math.inf: continue
        ss.append((b-a)/max(a,b) if max(a,b)>0 else 0.0)
    return sum(ss)/len(ss) if ss else 0.0

asw_batch=asw(batch)      # want ~0/neg (batches NOT separable) => mixed
asw_ct=asw(ctype)         # want >0 (celltypes separable) => biology kept
asw_batch_score = 1.0 - (asw_batch+1)/2.0        # high = batches well mixed
asw_ct_score    = (asw_ct+1)/2.0                 # high = celltypes separable

batch_removal   = round(0.5*ilisi_score + 0.5*asw_batch_score, 4)
bio_conservation= round(0.5*clisi_purity + 0.5*asw_ct_score, 4)
overall = round(bw*batch_removal + (1-bw)*bio_conservation, 4)

if batch_removal>=good_t and bio_conservation>=good_t:
    verdict='WELL-INTEGRATED'
    note='Batches mixed AND biology preserved. Suitable for integrated analysis.'
elif batch_removal>=good_t and bio_conservation<good_t:
    verdict='OVER-CORRECTED'
    note=('Batches mixed but biological structure erased (cell types blended). '
          'Reduce integration strength / choose a more conservation-favouring method.')
elif batch_removal<good_t and bio_conservation>=good_t:
    verdict='UNDER-CORRECTED'
    note=('Biology preserved but batch effect remains (batches still separable). '
          'Stronger integration needed.')
else:
    verdict='POORLY INTEGRATED'
    note='Neither objective met — re-examine inputs and method choice.'

res={'status':'completed','method':method,'n_cells':n,'n_batches':nb,'n_celltypes':nc,
     'k':k,
     'batch_removal':{'score':batch_removal,'iLISI':round(ilisi,3),'iLISI_score':round(ilisi_score,4),
                      'ASW_batch':round(asw_batch,4),'ASW_batch_score':round(asw_batch_score,4)},
     'biology_conservation':{'score':bio_conservation,'cLISI':round(clisi,3),
                             'cLISI_purity':round(clisi_purity,4),'ASW_celltype':round(asw_ct,4),
                             'ASW_celltype_score':round(asw_ct_score,4)},
     'overall_scib_score':overall,'batch_weight':bw,'good_threshold':good_t,
     'verdict':verdict,'verdict_note':note}
with open('integration_metrics.json','w') as f: json.dump(res,f,indent=2)

with open('per_cell_lisi.csv','w',newline='') as f:
    w=csv.writer(f); w.writerow(['cell_id','iLISI','cLISI'])
    for i in range(n): w.writerow([cells[i], round(iLISI[i],3), round(cLISI[i],3)])

L=[]
L.append(f'# Integration Benchmark — {method}')
L.append('')
L.append(f'**Cells:** {n}  |  **Batches:** {nb}  |  **Cell types:** {nc}  |  **Verdict:** **{verdict}**')
L.append('')
L.append('Two-objective scIB scoring. There is no universal-best integration method; '
         'the point is to remove batch WITHOUT erasing biology, and to detect over-correction.')
L.append('')
L.append('| Objective | Score (0–1, higher better) | Components |')
L.append('|---|---:|---|')
L.append(f'| **Batch removal** | {batch_removal} | iLISI {ilisi:.2f} (→{ilisi_score:.2f}), ASW-batch {asw_batch:+.2f} (→{asw_batch_score:.2f}) |')
L.append(f'| **Biology conservation** | {bio_conservation} | cLISI purity {clisi_purity:.2f}, ASW-celltype {asw_ct:+.2f} (→{asw_ct_score:.2f}) |')
L.append(f'| **Overall (scIB)** | {overall} | {bw:.0%} batch / {1-bw:.0%} biology |')
L.append('')
L.append(f'## Verdict — {verdict}')
L.append('')
L.append(note)
L.append('')
L.append('_LISI = inverse-Simpson diversity of labels among k nearest neighbours '
         '(iLISI over batches → high = mixed; cLISI over cell types → low = pure). '
         'ASW = average silhouette width. Method: Luecken 2022 scIB; Korsunsky 2019 LISI._')
with open('integration_report.md','w') as f: f.write('\\n'.join(L)+'\\n')

print('=== INTEGRATION_BENCHMARK %s | n=%d b=%d ct=%d | batch_removal=%.2f bio=%.2f | %s ==='%(
    method,n,nb,nc,batch_removal,bio_conservation,verdict))

with open('versions.yml','w') as f:
    f.write('integration_benchmark:\\n  python: "3.10"\\n  metrics: "iLISI/cLISI/ASW (scIB; Luecken 2022, Korsunsky 2019)"\\n')
PYEOF
    """
}

workflow INTEGRATION_BENCHMARK_WORKFLOW {
    take: meta_ch
    main: INTEGRATION_BENCHMARK(meta_ch)
    emit:
        results = INTEGRATION_BENCHMARK.out.results
        report  = INTEGRATION_BENCHMARK.out.report
}

workflow {
    meta = [id: 'integration_benchmark_run', single_end: false]
    Channel.value(meta) | INTEGRATION_BENCHMARK_WORKFLOW
}
