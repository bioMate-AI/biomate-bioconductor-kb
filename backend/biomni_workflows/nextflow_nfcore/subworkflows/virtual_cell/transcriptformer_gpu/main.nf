#!/usr/bin/env nextflow
/*
 * virtual_cell/transcriptformer_gpu
 *
 * FULL GPU implementation: Cell state embedding and perturbation prediction
 * using CZI TranscriptFormer (Apache 2.0 license).
 *
 * Reference: CZI TranscriptFormer v0.6.0 (2025)
 *   GitHub: https://github.com/czi-ai/transcriptformer
 *   Portal: https://virtualcellmodels.cziscience.com/model/transcriptformer
 *   License: Apache 2.0
 *
 * Model:
 *   - 300M parameter transformer encoder
 *   - Trained on 112M cells across 12 species (1.53B years evolution)
 *   - Gene embeddings from ESM-2 protein language model
 *   - Expression counts as log-count bias in attention matrix
 *   - Generative: can sample new cell states
 *   - Cross-species generalization built-in
 *
 * Requirements:
 *   - Docker: 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/virtual-cell-gpu:1.0
 *   - AWS Batch: g5.2xlarge (A10G 24GB VRAM) recommended
 *   - Model weights: auto-downloaded from CZI portal or /models/transcriptformer/
 *
 * Input:  adata_h5ad (AnnData), or inline_genes (gene:value CSV), perturbation (optional)
 * Output: cell_embeddings.csv, cell_state_results.json, tf_report.txt
 */

nextflow.enable.dsl = 2

params.outdir           = './results'
params.adata_h5ad       = 'null'
params.inline_genes     = 'MYC:5.2,CDK4:4.1,CCND1:4.8,CDKN1A:1.2,TP53:2.1,MKI67:3.9'
params.species          = 'homo_sapiens'   // homo_sapiens | mus_musculus | etc.
params.task             = 'embed'           // embed | classify | perturb
params.perturbation_gene = 'null'          // gene to knockout (for task=perturb)
params.model_version    = 'transcriptformer-v0.6.0'
params.model_dir        = '/models/transcriptformer'
params.batch_size       = '32'
params.device           = 'auto'

process TRANSCRIPTFORMER_GPU {
    tag "$meta.id"
    label 'process_gpu'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/virtual-cell-gpu:1.0' \
        : 'biomate/virtual-cell-gpu:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("cell_state_results.json"),  emit: results
    tuple val(meta), path("cell_embeddings.csv"),      emit: embeddings
    tuple val(meta), path("tf_report.txt"),            emit: report
    path "versions.yml",                               emit: versions

    script:
    """
    export PARAM_ADATA='${params.adata_h5ad}'
    export PARAM_GENES='${params.inline_genes}'
    export PARAM_SPECIES='${params.species}'
    export PARAM_TASK='${params.task}'
    export PARAM_PERT_GENE='${params.perturbation_gene}'
    export PARAM_MODEL_VERSION='${params.model_version}'
    export PARAM_MODEL_DIR='${params.model_dir}'
    export PARAM_BATCH='${params.batch_size}'
    export PARAM_DEVICE='${params.device}'

    python3 << 'PYEOF'
import json, os, csv

adata_path = os.environ.get('PARAM_ADATA', 'null')
inline_raw = os.environ.get('PARAM_GENES', '')
species    = os.environ.get('PARAM_SPECIES', 'homo_sapiens')
task       = os.environ.get('PARAM_TASK', 'embed')
pert_gene  = os.environ.get('PARAM_PERT_GENE', 'null')
model_ver  = os.environ.get('PARAM_MODEL_VERSION', 'transcriptformer-v0.6.0')
model_dir  = os.environ.get('PARAM_MODEL_DIR', '/models/transcriptformer')
batch_size = int(os.environ.get('PARAM_BATCH', '32'))
device_str = os.environ.get('PARAM_DEVICE', 'auto')

import torch
device = 'cuda' if (device_str == 'auto' and torch.cuda.is_available()) else device_str
print(f"Device: {device}", flush=True)

tf_available = False
embeddings = []
cell_types = []
results_extra = {}

# ─── Try TranscriptFormer ─────────────────────────────────────────────────
try:
    import transcriptformer as tf_module
    import anndata

    # Load AnnData
    if adata_path not in ('null','None','') and os.path.exists(adata_path):
        adata = anndata.read_h5ad(adata_path)
        print(f"Loaded AnnData: {adata.shape}", flush=True)
    else:
        # Build minimal AnnData from inline gene expression
        import numpy as np, pandas as pd
        expr = {}
        for item in inline_raw.split(','):
            if ':' in item:
                g, v = item.strip().split(':', 1)
                try: expr[g.strip().upper()] = float(v)
                except: pass
        if not expr:
            expr = {'MYC': 5.2, 'CDK4': 4.1, 'CCND1': 4.8, 'CDKN1A': 1.2, 'MKI67': 3.9}
        gene_names = list(expr.keys())
        X = np.array([[expr[g] for g in gene_names]])
        adata = anndata.AnnData(X=X,
                                obs=pd.DataFrame({'cell_id': ['cell_0']}).set_index('cell_id'),
                                var=pd.DataFrame({'gene_name': gene_names}).set_index('gene_name'))

    # Load TranscriptFormer model
    if os.path.exists(model_dir) and os.listdir(model_dir):
        print(f"Loading TranscriptFormer from {model_dir}", flush=True)
        model = tf_module.load(model_dir, device=device)
    else:
        print(f"Downloading TranscriptFormer {model_ver}...", flush=True)
        os.makedirs(model_dir, exist_ok=True)
        model = tf_module.load(model_ver, device=device, cache_dir=model_dir)

    # Run task
    if task == 'embed':
        emb = model.encode(adata, batch_size=batch_size)
        embeddings = emb.tolist() if hasattr(emb, 'tolist') else list(emb)
        results_extra['embedding_dim'] = len(embeddings[0]) if embeddings else 0
        results_extra['n_cells'] = len(embeddings)

    elif task == 'classify':
        cell_type_probs = model.classify(adata, batch_size=batch_size)
        cell_types = cell_type_probs.tolist() if hasattr(cell_type_probs, 'tolist') else []
        results_extra['cell_type_predictions'] = cell_types[:5]

    elif task == 'perturb' and pert_gene not in ('null','None',''):
        perturbed = model.perturb(adata, gene=pert_gene, perturbation='knockout',
                                  batch_size=batch_size)
        # Compare perturbed vs original embedding
        orig_emb = model.encode(adata, batch_size=batch_size)
        pert_emb = model.encode(perturbed, batch_size=batch_size)
        import numpy as np
        delta = np.array(pert_emb) - np.array(orig_emb)
        results_extra['perturbation_gene'] = pert_gene
        results_extra['mean_embedding_shift'] = float(np.linalg.norm(delta.mean(axis=0)))
        embeddings = pert_emb.tolist()

    tf_available = True
    model_used = f'TranscriptFormer {model_ver} (Apache 2.0)'

except ImportError as e:
    print(f"TranscriptFormer not importable: {e}", flush=True)
    model_used = f'Marker-gene fallback (TranscriptFormer unavailable: {str(e)[:60]})'

except Exception as e:
    print(f"TranscriptFormer error: {e}", flush=True)
    model_used = f'Marker-gene fallback (error: {str(e)[:80]})'

# ─── Fallback: marker-based classification (same as CPU workflow) ─────────
if not tf_available:
    import math
    expr = {}
    for item in inline_raw.split(','):
        if ':' in item:
            g, v = item.strip().split(':', 1)
            try: expr[g.strip().upper()] = float(v)
            except: pass
    if not expr:
        expr = {'MYC': 5.2, 'CDK4': 4.1, 'CDKN1A': 1.2, 'MKI67': 3.9}
    vals = list(expr.values())
    mu = sum(vals)/len(vals); sd = math.sqrt(sum((v-mu)**2 for v in vals)/max(len(vals)-1,1))
    expr_norm = {g: (v-mu)/max(sd,1e-9) for g, v in expr.items()}
    MARKERS = {
        'Cancer cells (proliferating)': {'up': ['MKI67','MYC','CDK4','CCND1','PCNA'], 'down': ['CDKN1A','TP53']},
        'Drug-arrested cells (G1)':     {'up': ['CDKN1A','CDKN1B'], 'down': ['CDK4','CCND1','MKI67']},
        'Hepatocytes':                   {'up': ['ALB','CYP3A4','APOA1'], 'down': ['MKI67']},
    }
    scores = {ct: sum(expr_norm.get(g,0) for g in m['up'])/max(len(m['up']),1)
                 - sum(expr_norm.get(g,0) for g in m['down'])/max(len(m['down']),1)
              for ct, m in MARKERS.items()}
    best = max(scores, key=scores.get)
    results_extra['fallback_cell_type'] = best
    results_extra['fallback_score'] = round(scores[best], 4)
    embeddings = []

# ─── Write outputs ────────────────────────────────────────────────────────
results = {
    'status': 'completed',
    'model': model_used,
    'device': device,
    'transcriptformer_available': tf_available,
    'species': species,
    'task': task,
    'license': 'Apache 2.0 (CZI TranscriptFormer)',
    **results_extra,
    'references': [
        'CZI TranscriptFormer v0.6.0 (2025) — github.com/czi-ai/transcriptformer',
        'CZI + NVIDIA Virtual Cell Initiative (Oct 2025)',
        'Human Cell Atlas (humancellatlas.org)',
    ],
}

with open('cell_state_results.json', 'w') as f:
    json.dump(results, f, indent=2)

with open('cell_embeddings.csv', 'w', newline='') as f:
    w = csv.writer(f)
    if embeddings:
        w.writerow([f'dim_{i}' for i in range(len(embeddings[0]))])
        for row in embeddings:
            w.writerow([round(v, 6) for v in row])
    else:
        w.writerow(['note'])
        w.writerow([f'Embeddings not available — {model_used}'])

lines = [
    f'╔══════════════════════════════════════════════════════════╗',
    f'  TranscriptFormer GPU — Cell State Analysis',
    f'  Task: {task} | Species: {species}',
    f'  Model: {model_used}',
    f'╚══════════════════════════════════════════════════════════╝',
    '',
    f'  License: Apache 2.0 (CZI; github.com/czi-ai/transcriptformer)',
    f'  TranscriptFormer available: {tf_available}',
    '',
]
for k, v in results_extra.items():
    lines.append(f'  {k}: {v}')

with open('tf_report.txt', 'w') as f:
    f.write('\\n'.join(lines))
print('\\n'.join(lines))
PYEOF

    cat << 'EOF' > versions.yml
transcriptformer_gpu:
  model: "CZI TranscriptFormer v0.6.0 (Apache 2.0)"
  reference: "github.com/czi-ai/transcriptformer"
  training_data: "112M cells, 12 species"
  docker: "biomate/virtual-cell-gpu:1.0"
  instance: "g5.2xlarge (A10G 24GB)"
  license: "Apache 2.0"
EOF
    """
}

workflow TRANSCRIPTFORMER_GPU_WORKFLOW {
    take: meta_ch
    main: TRANSCRIPTFORMER_GPU(meta_ch)
    emit:
        results    = TRANSCRIPTFORMER_GPU.out.results
        embeddings = TRANSCRIPTFORMER_GPU.out.embeddings
        report     = TRANSCRIPTFORMER_GPU.out.report
}

workflow {
    meta = [id: 'tf_gpu_run']
    Channel.value(meta) | TRANSCRIPTFORMER_GPU_WORKFLOW
}
