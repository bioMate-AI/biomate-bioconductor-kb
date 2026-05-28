#!/usr/bin/env nextflow

/**
 * drugclip_virtual_screening
 *
 * Ultra-fast structure-based virtual screening using DrugCLIP.
 * CLIP-based contrastive learning; 10 million times faster than traditional
 * docking. Published in Science 2026. Screened 10K proteins × 500M compounds.
 *
 * Inputs:
 *   params.receptor_pdb  -- target protein PDB file or PDB ID (e.g., '6LUD')
 *   params.compounds_smi -- SMILES file (one compound per line, optional name col)
 *   params.top_k         -- number of top hits to return (default: 100)
 *   params.batch_size    -- inference batch size (default: 512)
 *   params.pocket_residues -- comma-separated residue numbers defining binding pocket (optional)
 *   params.outdir        -- output directory
 */

nextflow.enable.dsl = 2

params.receptor_pdb    = ''
params.compounds_smi   = ''
params.top_k           = 100
params.batch_size      = 512
params.pocket_residues = ''
params.outdir          = 'results'
params.publish_dir_mode = 'copy'

ECR = '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/drugclip:latest'

// ── Fetch receptor if PDB ID given ───────────────────────────────────────────

// [Analysis]
process FETCH_RECEPTOR {
    tag "receptor"
    label 'process_low'
    container ECR

    input:
    val(receptor_input)

    output:
    path("receptor.pdb"), emit: pdb

    script:
    if (receptor_input =~ /^[0-9][A-Za-z0-9]{3}$/) {
        """
        python3 -c "
import urllib.request
url = 'https://files.rcsb.org/download/${receptor_input}.pdb'
urllib.request.urlretrieve(url, 'receptor.pdb')
print('Downloaded PDB: ${receptor_input}')
"
        """
    } else {
        """
        cp ${receptor_input} receptor.pdb
        """
    }
}

// ── Run DrugCLIP screening ────────────────────────────────────────────────────

// [Virtual Screening]
process DRUGCLIP_SCREEN {
    tag "drugclip"
    label 'process_gpu'
    publishDir "${params.outdir}/screening", mode: params.publish_dir_mode

    container ECR

    input:
    path(receptor_pdb)
    path(compounds_smi)

    output:
    path("drugclip_hits.csv"), emit: hits
    path("drugclip_embeddings.npy"), emit: embeddings, optional: true

    script:
    def pocket_flag = params.pocket_residues ? "--pocket-residues ${params.pocket_residues}" : ""
    """
    python /opt/drugclip/screen.py \\
        --receptor ${receptor_pdb} \\
        --compounds ${compounds_smi} \\
        --top-k ${params.top_k} \\
        --batch-size ${params.batch_size} \\
        --output drugclip_hits.csv \\
        --save-embeddings drugclip_embeddings.npy \\
        ${pocket_flag}
    """
}

// ── Generate report ───────────────────────────────────────────────────────────

// [Analysis]
process SCREENING_REPORT {
    tag "report"
    label 'process_low'
    publishDir "${params.outdir}", mode: params.publish_dir_mode

    container ECR

    input:
    path(hits_csv)
    path(receptor_pdb)

    output:
    path("drugclip_report.json"), emit: report
    path("top_hits.sdf"), emit: sdf, optional: true

    script:
    """
    python3 - <<'EOF'
import json, csv, os

hits = []
with open("${hits_csv}") as f:
    reader = csv.DictReader(f)
    for row in reader:
        hits.append(row)

report = {
    "tool": "DrugCLIP",
    "publication": "Science 2026",
    "receptor": os.path.basename("${receptor_pdb}"),
    "compounds_screened": len(hits),
    "top_k": ${params.top_k},
    "top_hits": hits[:10],
}
with open("drugclip_report.json", "w") as f:
    json.dump(report, f, indent=2)
print(f"Screened {len(hits)} compounds; top hit score: {hits[0].get('score','N/A') if hits else 'N/A'}")
EOF
    """
}

workflow {
    receptor_ch = Channel.value(params.receptor_pdb)
    compounds_ch = Channel.fromPath(params.compounds_smi, checkIfExists: true)

    FETCH_RECEPTOR(receptor_ch)
    DRUGCLIP_SCREEN(FETCH_RECEPTOR.out.pdb, compounds_ch)
    SCREENING_REPORT(DRUGCLIP_SCREEN.out.hits, FETCH_RECEPTOR.out.pdb)
}
