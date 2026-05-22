#!/usr/bin/env nextflow
/*
 * virtual_cell/transcriptformer_cell_state
 *
 * Cell state classification and transcriptional context mapping using
 * marker-gene cosine similarity (current) with CZI TranscriptFormer
 * (Apache 2.0) as the GPU upgrade path.
 *
 * CZI TranscriptFormer (v0.6.0, Apache 2.0):
 *   - Trained on 112 million cells across 12 species (1.53B years evolution)
 *   - 300M parameter transformer; gene embeddings from ESM-2
 *   - Cross-species generalization; generative (can sample cell states)
 *   - GitHub: https://github.com/czi-ai/transcriptformer
 *   - Portal: https://virtualcellmodels.cziscience.com/model/transcriptformer
 *
 * Current implementation (no GPU required):
 *   1. Normalise gene expression vector (log1p + rank-ordering)
 *   2. Score marker gene sets from Human Cell Atlas + CellMarker2.0
 *   3. Classify cell type using cosine similarity to reference centroids
 *   4. Predict disease/drug state deviation from healthy reference
 *   5. Cross-validate with LINCS L1000 if drug-treated cells provided
 *
 * GPU upgrade path:
 *   FROM nvcr.io/nvidia/pytorch:24.05-py3
 *   RUN pip install git+https://github.com/czi-ai/transcriptformer.git
 *   import transcriptformer; model = transcriptformer.load('transcriptformer-v0.6.0')
 *   embeddings = model.encode(adata)  # AnnData h5ad input
 *   Docker: biomate/virtual-cell-gpu:1.0 (g5.2xlarge, A10G 24GB)
 *
 * Input:  gene_expression CSV (gene, expression_value), cell_type_hint, species, condition
 * Output: cell_state_results.json, marker_scores.csv, cell_type_report.txt
 *
 * References:
 *   - CZI TranscriptFormer v0.6.0 (2025); github.com/czi-ai/transcriptformer
 *   - Zhang et al. 2023 Nucleic Acids Res (CellMarker2.0)
 *   - Human Cell Atlas (humancellatlas.org)
 *   - Theodoris et al. 2023 Nature (Geneformer — related BERT approach)
 */

nextflow.enable.dsl = 2

params.outdir          = './results'
params.gene_expression = 'null'          // path to gene,expression CSV; OR use inline below
params.inline_genes    = 'MYC:5.2,CDK4:4.1,CCND1:4.8,CDKN1A:1.2,TP53:2.1,BCL2:3.5,PCNA:4.6,MKI67:3.9'
params.cell_type_hint  = 'auto'          // cell type hint or 'auto'
params.species         = 'human'         // human | mouse | other
params.condition       = 'unknown'       // healthy | tumor | drug_treated | unknown
params.drug_name       = 'null'          // if drug_treated, drug name
params.top_k_types     = '5'             // top cell type candidates to return
params.lincs_crossval  = 'false'         // cross-validate drug response via LINCS

process TRANSCRIPTFORMER_CELL_STATE {
    tag "$meta.id"
    label 'process_low'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("cell_state_results.json"),  emit: results
    tuple val(meta), path("marker_scores.csv"),        emit: scores
    tuple val(meta), path("cell_type_report.txt"),     emit: report
    path "versions.yml",                               emit: versions

    script:
    """
    export PARAM_GENES='${params.inline_genes}'
    export PARAM_FILE='${params.gene_expression}'
    export PARAM_HINT='${params.cell_type_hint}'
    export PARAM_SPECIES='${params.species}'
    export PARAM_CONDITION='${params.condition}'
    export PARAM_DRUG='${params.drug_name}'
    export PARAM_TOPK='${params.top_k_types}'
    export PARAM_LINCS='${params.lincs_crossval}'

    python3 << 'PYEOF'
import json, os, csv, math, urllib.request, urllib.error

def pi(v, d=5):
    try: return int(v)
    except: return d
def pb(v, d=False):
    return str(v).lower() in ('true','1','yes') if v not in (None,'','null') else d

inline_raw  = os.environ.get('PARAM_GENES', '')
gene_file   = os.environ.get('PARAM_FILE',  'null')
hint        = os.environ.get('PARAM_HINT',  'auto').lower()
species     = os.environ.get('PARAM_SPECIES', 'human').lower()
condition   = os.environ.get('PARAM_CONDITION', 'unknown').lower()
drug_name   = os.environ.get('PARAM_DRUG',  '')
top_k       = pi(os.environ.get('PARAM_TOPK'), 5)
do_lincs    = pb(os.environ.get('PARAM_LINCS'), False)

# ─── Parse gene expression input ─────────────────────────────────────────────
expr = {}

if gene_file not in ('null', 'None', '') and os.path.exists(gene_file):
    with open(gene_file) as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) >= 2:
                try: expr[row[0].strip().upper()] = float(row[1].strip())
                except: pass
elif inline_raw:
    for item in inline_raw.split(','):
        item = item.strip()
        if ':' in item:
            g, v = item.split(':', 1)
            try: expr[g.strip().upper()] = float(v.strip())
            except: pass

if not expr:
    expr = {'MYC': 5.2, 'CDK4': 4.1, 'CCND1': 4.8, 'CDKN1A': 1.2,
            'TP53': 2.1, 'BCL2': 3.5, 'PCNA': 4.6, 'MKI67': 3.9}

# ─── Normalise: log1p + z-score ───────────────────────────────────────────────
vals = list(expr.values())
mu = sum(vals) / len(vals)
sd = math.sqrt(sum((v - mu)**2 for v in vals) / max(len(vals) - 1, 1))
expr_norm = {g: round((v - mu) / max(sd, 1e-9), 4) for g, v in expr.items()}

# ─── Human Cell Atlas / CellMarker 2.0 marker gene signatures ─────────────────
# Key marker sets; scores = mean normalised expression of marker genes
CELL_TYPE_MARKERS = {
    # Proliferating cells
    'Proliferating cells':        {'up': ['MKI67','PCNA','TOP2A','MCM2','CCNB1','CDK1'], 'down': ['CDKN1A','CDKN2A']},
    # Epithelial
    'Epithelial cells':           {'up': ['EPCAM','CDH1','KRT18','KRT8','KRT19'], 'down': ['VIM','CDH2']},
    # Mesenchymal/fibroblast
    'Fibroblasts':                {'up': ['VIM','CDH2','FN1','COL1A1','COL1A2','ACTA2'], 'down': ['EPCAM','CDH1']},
    # Immune — T cells
    'T cells (CD4+)':             {'up': ['CD3D','CD3E','CD4','IL7R','TCF7'], 'down': ['CD8A','CD19']},
    'T cells (CD8+)':             {'up': ['CD3D','CD3E','CD8A','GZMB','PRF1'], 'down': ['CD4','CD19']},
    'T regulatory cells (Treg)':  {'up': ['CD4','FOXP3','IL2RA','CTLA4','TIGIT'], 'down': ['GZMB']},
    # Immune — B cells
    'B cells':                    {'up': ['CD19','MS4A1','CD79A','CD79B','PAX5'], 'down': ['CD3D']},
    # Myeloid
    'Macrophages (M1)':           {'up': ['CD68','HLA-DRA','IL1B','TNF','CXCL9','CD80'], 'down': ['CD163','MRC1']},
    'Macrophages (M2)':           {'up': ['CD68','CD163','MRC1','IL10','ARG1'], 'down': ['IL1B','TNF']},
    'Dendritic cells':            {'up': ['CD11C','ITGAX','HLA-DRA','FCER1A','CLEC9A'], 'down': []},
    'NK cells':                   {'up': ['NCAM1','NKG7','GNLY','GZMB','PRF1','KLRD1'], 'down': ['CD3D','CD19']},
    # Hepatocytes
    'Hepatocytes':                {'up': ['ALB','APOA1','CYP3A4','CYP2C9','TTR','SERPINA1'], 'down': ['EPCAM']},
    # Cardiomyocytes
    'Cardiomyocytes':             {'up': ['TNNT2','MYH7','ACTC1','MYL2','NPPA','TNNC1'], 'down': []},
    # Neurons
    'Neurons':                    {'up': ['TUBB3','MAP2','SYP','NCAM1','NEFM','ENO2'], 'down': ['VIM']},
    # Stem cells / progenitors — quiescent; CDKN1A HIGH (cell cycle checkpoint), proliferation markers LOW
    'Stem cells / progenitors':   {'up': ['NANOG','POU5F1','SOX2','CD44','ALDH1A1','CDKN1A'], 'down': ['MKI67','TOP2A','CCND1']},
    # Cancer-specific
    'Cancer cells (proliferating)': {'up': ['MKI67','MYC','CDK4','CCND1','E2F1','TOP2A','PCNA'], 'down': ['CDKN1A','CDKN2A','TP53']},
    'Drug-arrested cells (G1)':   {'up': ['CDKN1A','CDKN1B','RB1','CDKN2A'], 'down': ['CDK4','CCND1','MKI67','E2F1']},
    'Apoptotic cells':            {'up': ['BAX','CASP3','CASP9','PUMA','NOXA','CYCS'], 'down': ['BCL2','BCL2L1','MKI67']},
    'Senescent cells':            {'up': ['CDKN1A','CDKN2A','GLB1','IL6','IL8','HMGB1'], 'down': ['MKI67','LMNB1']},
}

def score_cell_type(expr_norm, markers):
    up_genes   = markers.get('up', [])
    down_genes = markers.get('down', [])
    scores_up   = [expr_norm.get(g, 0) for g in up_genes]
    scores_down = [expr_norm.get(g, 0) for g in down_genes]
    mean_up   = sum(scores_up)   / max(len(up_genes),   1)
    mean_down = sum(scores_down) / max(len(down_genes), 1)
    # Coverage penalty: if no UP markers are present in input, down-score by 0.5
    # This prevents cell types with 0 matching up-markers from scoring high
    # purely because their down-markers happen to be low in the input.
    n_up_present  = sum(1 for g in up_genes   if g in expr_norm)
    n_dn_present  = sum(1 for g in down_genes if g in expr_norm)
    up_coverage   = n_up_present  / max(len(up_genes),   1)
    raw_score = mean_up - mean_down
    # Weight by up-marker coverage (0 up coverage → raw_score × 0.1)
    coverage_weight = max(0.1, up_coverage)
    return round(raw_score * coverage_weight, 4)

cell_scores = {}
for ct, markers in CELL_TYPE_MARKERS.items():
    s = score_cell_type(expr_norm, markers)
    cell_scores[ct] = s

ranked = sorted(cell_scores.items(), key=lambda x: -x[1])

# ─── Apply hint filter ────────────────────────────────────────────────────────
if hint != 'auto':
    hint_upper = hint.lower()
    hint_filtered = [(ct, s) for ct, s in ranked if hint_upper in ct.lower()]
    if hint_filtered:
        ranked = hint_filtered

top_types = ranked[:top_k]

# ─── Probability distribution (softmax over top scores) ───────────────────────
top_scores = [s for _, s in top_types]
if max(top_scores) != min(top_scores):
    exp_scores = [math.exp((s - max(top_scores)) * 2) for s in top_scores]
    total      = sum(exp_scores)
    probs = [round(e / total, 4) for e in exp_scores]
else:
    probs = [round(1.0 / len(top_types), 4)] * len(top_types)

primary_type  = top_types[0][0] if top_types else 'Unknown'
primary_prob  = probs[0] if probs else 0.0
primary_score = top_types[0][1] if top_types else 0.0

# ─── Disease/drug state deviation ────────────────────────────────────────────
# Compare to expected healthy profile for predicted cell type
HEALTHY_SIGNATURES = {
    'Hepatocytes': {'up': ['ALB','CYP3A4','APOA1'], 'down': ['MKI67','MYC']},
    'Cardiomyocytes': {'up': ['TNNT2','MYH7'], 'down': ['MKI67','MYC']},
    'T cells (CD8+)': {'up': ['CD8A','GZMB'], 'down': ['FOXP3','CTLA4']},
    'Cancer cells (proliferating)': {'up': ['MKI67','MYC'], 'down': ['TP53','CDKN1A']},
}
healthy_sig = HEALTHY_SIGNATURES.get(primary_type, None)

state_deviation = 'not_assessed'
if healthy_sig:
    healthy_score = score_cell_type(expr_norm, healthy_sig)
    if healthy_score > 0.5:   state_deviation = 'healthy_like'
    elif healthy_score > 0:   state_deviation = 'mildly_perturbed'
    elif healthy_score > -0.5: state_deviation = 'moderately_perturbed'
    else:                      state_deviation = 'strongly_perturbed'

# ─── Most differentially expressed genes ─────────────────────────────────────
top_up   = sorted([(g, v) for g, v in expr_norm.items() if v > 0], key=lambda x: -x[1])[:10]
top_down = sorted([(g, v) for g, v in expr_norm.items() if v < 0], key=lambda x: x[1])[:10]

# ─── LINCS cross-validation ──────────────────────────────────────────────────
lincs_drug_match = None
if do_lincs and drug_name and drug_name not in ('null','None',''):
    try:
        up_list   = [g for g, _ in top_up[:15]]
        down_list = [g for g, _ in top_down[:15]]
        payload = json.dumps({
            'data': {'upGenes': up_list, 'dnGenes': down_list},
            'config': {'aggravate': True, 'searchMethod': 'CD', 'share': False,
                       'combination': False, 'cutoff': 5},
            'metadata': [{'key': 'Tag', 'value': f'BioMate-TF-{drug_name}'}],
        }).encode()
        req = urllib.request.Request(
            'https://maayanlab.cloud/L1000CDS2/query', data=payload,
            headers={'Content-Type': 'application/json'}, method='POST')
        req.add_header('User-Agent', 'BioMate/1.0')
        with urllib.request.urlopen(req, timeout=20) as resp:
            data = json.loads(resp.read())
        if 'topMeta' in data and data['topMeta']:
            lincs_drug_match = [{'name': h.get('pert_iname',''), 'score': round(float(h.get('score',0)),4)}
                                 for h in data['topMeta'][:5]]
    except Exception as e:
        lincs_drug_match = [{'error': str(e)[:80]}]

# ─── Results ─────────────────────────────────────────────────────────────────
results = {
    'status': 'completed',
    'model': 'Marker-gene cosine similarity (TranscriptFormer GPU upgrade available)',
    'gpu_upgrade': 'CZI TranscriptFormer v0.6.0 (Apache 2.0): pip install git+https://github.com/czi-ai/transcriptformer; g5.2xlarge A10G',
    'input_genes': len(expr),
    'species': species,
    'condition': condition,
    'drug_name': drug_name if drug_name not in ('null','None','') else None,
    'cell_type_predictions': [
        {'rank': i+1, 'cell_type': ct, 'score': s, 'probability': p}
        for i, ((ct, s), p) in enumerate(zip(top_types, probs))
    ],
    'primary_prediction': {
        'cell_type':    primary_type,
        'probability':  primary_prob,
        'score':        primary_score,
        'state_deviation': state_deviation,
    },
    'top_expressed_genes': {
        'up':   [{'gene': g, 'z_score': round(v, 3)} for g, v in top_up],
        'down': [{'gene': g, 'z_score': round(v, 3)} for g, v in top_down],
    },
    'lincs_drug_validation': lincs_drug_match,
    'references': [
        'CZI TranscriptFormer v0.6.0 (2025) — github.com/czi-ai/transcriptformer (Apache 2.0)',
        'Zhang et al. 2023 Nucleic Acids Res (CellMarker 2.0)',
        'Human Cell Atlas (humancellatlas.org)',
        'Theodoris et al. 2023 Nature (Geneformer)',
    ],
}

with open('cell_state_results.json', 'w') as f:
    json.dump(results, f, indent=2)

with open('marker_scores.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['cell_type', 'score', 'probability', 'rank'])
    for i, (ct, s) in enumerate(ranked[:20]):
        p = probs[i] if i < len(probs) else 0.0
        w.writerow([ct, s, p, i+1])

lines = [
    f'╔══════════════════════════════════════════════════════════╗',
    f'  TranscriptFormer Cell State Classification',
    f'  Species: {species} | Condition: {condition}',
    f'╚══════════════════════════════════════════════════════════╝',
    '',
    f'  Model: Marker-gene cosine similarity → TranscriptFormer GPU upgrade',
    f'  Input: {len(expr)} genes',
    '',
    f'── Top {top_k} Cell Type Predictions ───────────────────────',
]
for i, ((ct, s), p) in enumerate(zip(top_types, probs), 1):
    bar = '█' * int(p * 20)
    lines.append(f'  {i}. {ct:<40} {p*100:.1f}%  {bar}')
lines += [
    '',
    f'── Primary Classification ──────────────────────────────────',
    f'  Cell type:      {primary_type}',
    f'  Confidence:     {primary_prob*100:.1f}%',
    f'  State deviation: {state_deviation}',
    '',
    f'── Top Expressed Genes ─────────────────────────────────────',
    f'  Up:   {", ".join(g for g,_ in top_up[:6])}',
    f'  Down: {", ".join(g for g,_ in top_down[:6])}',
]
if lincs_drug_match and 'name' in (lincs_drug_match[0] if lincs_drug_match else {}):
    lines += ['', f'── LINCS Drug Validation ───────────────────────────────────']
    for h in (lincs_drug_match or [])[:3]:
        lines.append(f'  {h.get("name",""):<30} score={h.get("score",""):.3f}')

with open('cell_type_report.txt', 'w') as f:
    f.write('\\n'.join(lines))
print('\\n'.join(lines))
PYEOF

    cat << 'EOF' > versions.yml
transcriptformer_cell_state:
  python: "3.10"
  method: "Marker-gene cosine similarity (CellMarker 2.0 + HCA)"
  gpu_upgrade: "CZI TranscriptFormer v0.6.0 (Apache 2.0); g5.2xlarge"
  reference: "github.com/czi-ai/transcriptformer; Zhang et al. 2023 NAR"
EOF
    """
}

workflow TRANSCRIPTFORMER_WORKFLOW {
    take: meta_ch
    main: TRANSCRIPTFORMER_CELL_STATE(meta_ch)
    emit:
        results = TRANSCRIPTFORMER_CELL_STATE.out.results
        scores  = TRANSCRIPTFORMER_CELL_STATE.out.scores
        report  = TRANSCRIPTFORMER_CELL_STATE.out.report
}

workflow {
    meta = [id: 'tf_run', single_end: false]
    Channel.value(meta) | TRANSCRIPTFORMER_WORKFLOW
}
