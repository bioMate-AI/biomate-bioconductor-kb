#!/usr/bin/env nextflow

/**
 * alphafold_db_search -- structural + sequence similarity search against AlphaFold DB
 *
 * Searches a query protein (PDB/CIF/FASTA) against the BioMate mirror of the
 * AlphaFold Human Proteome (~48k structures) using:
 *   - Foldseek  : 3Di alphabet structural search (finds structural analogs)
 *   - MMseqs2   : Sequence search (finds sequence homologs)
 *
 * S3 pre-built indexes (built once by scripts/build_alphafold_db.sh):
 *   s3://biomate-structure-db/alphafold/human/foldseek_db/
 *   s3://biomate-structure-db/alphafold/human/mmseqs2_db/
 *
 * Inputs:
 *   params.query_pdb     -- path/S3 URI to query structure (PDB or mmCIF)
 *   params.query_fasta   -- path/S3 URI to query FASTA (for MMseqs2; optional)
 *   params.search_mode   -- 'structural' | 'sequence' | 'both' (default: 'both')
 *   params.max_hits      -- max results to return (default: 50)
 *   params.evalue        -- e-value cutoff (default: 0.001)
 *   (always live — no mock mode)
 *   params.s3_db_base    -- S3 base URI for pre-built indexes
 */

nextflow.enable.dsl = 2

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------

params.query_pdb     = ''
params.query_fasta   = ''
params.search_mode   = 'both'
params.max_hits      = 50
params.evalue        = 0.001
params.min_seq_id    = 0.0
params.coverage      = 0.8
params.s3_db_base    = 's3://biomate-structure-db/alphafold/human'
params.outdir        = 'results'
params.publish_dir_mode = 'copy'

// ---------------------------------------------------------------------------
// Foldseek structural search
// ---------------------------------------------------------------------------

process FOLDSEEK_STRUCTURAL_SEARCH {
    tag "${meta.id}"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}/foldseek", mode: params.publish_dir_mode

    container 'steineggerlab/foldseek:latest'

    input:
    tuple val(meta), path(query)
    val  db_base
    val  max_hits
    val  evalue
    val  coverage

    output:
    tuple val(meta), path('foldseek_hits.tsv'),    emit: hits
    tuple val(meta), path('foldseek_report.html'), emit: report
    path 'versions.yml',                           emit: versions

    script:
    """
        mkdir -p tmp_query foldseek_db_local
        aws s3 sync ${db_base}/foldseek_db/ foldseek_db_local/ --quiet
        foldseek createdb ${query} query_db
        foldseek search query_db foldseek_db_local/af_db result_db tmp_query \\
            --max-seqs ${max_hits} \\
            -e ${evalue} \\
            --cov-mode 0 \\
            -c ${coverage} \\
            --threads ${task.cpus}
        foldseek convertalis query_db foldseek_db_local/af_db result_db foldseek_hits.tsv \\
            --format-output "query,target,pident,alnlen,mismatch,gapopen,qstart,qend,tstart,tend,evalue,bits,theader"
        # Add header
        sed -i '1s/^/query\\ttarget\\tpident\\talnlen\\tmismatch\\tgapopen\\tqstart\\tqend\\ttstart\\ttend\\tevalue\\tbitscore\\ttdescription\\n/' foldseek_hits.tsv

    python3 << 'PYEOF'
import csv, datetime, os
hits = []
try:
    with open('foldseek_hits.tsv') as f:
        reader = csv.DictReader(f, delimiter='\\t')
        hits = list(reader)
except Exception:
    pass
rows = ''.join(
    '<tr><td>{target}</td><td>{tdescription}</td><td>{pident}</td><td>{evalue}</td><td>{bitscore}</td></tr>'.format(**h)
    for h in hits
)
html = '''<!DOCTYPE html>
<html><head><title>Foldseek Structural Search</title>
<style>body{{font-family:sans-serif;max-width:900px;margin:2em auto}}
table{{border-collapse:collapse;width:100%}}th,td{{border:1px solid #ddd;padding:8px}}
th{{background:#2563eb;color:#fff}}tr:nth-child(even){{background:#f9fafb}}</style></head>
<body><h1>Foldseek Structural Search</h1>
<p>Date: {date} &nbsp;|&nbsp; Hits: {n}</p>
<table><tr><th>Target</th><th>Description</th><th>% ID</th><th>E-value</th><th>Score</th></tr>
{rows}</table></body></html>'''.format(date=str(datetime.date.today()), n=len(hits), rows=rows)
open('foldseek_report.html', 'w').write(html)
PYEOF

    cat > versions.yml << EOF
FOLDSEEK_STRUCTURAL_SEARCH:
  foldseek: \$(foldseek version 2>/dev/null || echo "unknown")
EOF
    """
}

// ---------------------------------------------------------------------------
// MMseqs2 sequence search
// ---------------------------------------------------------------------------

process MMSEQS2_SEQUENCE_SEARCH {
    tag "${meta.id}"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}/mmseqs2", mode: params.publish_dir_mode

    container 'soedinglab/mmseqs2:latest'

    input:
    tuple val(meta), path(query)
    val  db_base
    val  max_hits
    val  evalue
    val  min_seq_id
    val  coverage

    output:
    tuple val(meta), path('mmseqs2_hits.tsv'),    emit: hits
    tuple val(meta), path('mmseqs2_report.html'), emit: report
    path 'versions.yml',                          emit: versions

    script:
    """
        mkdir -p tmp_mmseqs mmseqs2_db_local
        aws s3 sync ${db_base}/mmseqs2_db/ mmseqs2_db_local/ --quiet
        mmseqs createdb ${query} query_db
        mmseqs search query_db mmseqs2_db_local/af_db result_db tmp_mmseqs \\
            --max-seqs ${max_hits} \\
            -e ${evalue} \\
            --min-seq-id ${min_seq_id} \\
            -c ${coverage} \\
            --threads ${task.cpus}
        mmseqs convertalis query_db mmseqs2_db_local/af_db result_db mmseqs2_hits.tsv \\
            --format-output "query,target,pident,alnlen,mismatch,gapopen,qstart,qend,tstart,tend,evalue,bits,theader"
        sed -i '1s/^/query\\ttarget\\tpident\\talnlen\\tmismatch\\tgapopen\\tqstart\\tqend\\ttstart\\ttend\\tevalue\\tbitscore\\ttdescription\\n/' mmseqs2_hits.tsv

    python3 << 'PYEOF'
import csv, datetime
hits = []
try:
    with open('mmseqs2_hits.tsv') as f:
        reader = csv.DictReader(f, delimiter='\\t')
        hits = list(reader)
except Exception:
    pass
rows = ''.join(
    '<tr><td>{target}</td><td>{tdescription}</td><td>{pident}</td><td>{evalue}</td><td>{bitscore}</td></tr>'.format(**h)
    for h in hits
)
html = '''<!DOCTYPE html>
<html><head><title>MMseqs2 Sequence Search</title>
<style>body{{font-family:sans-serif;max-width:900px;margin:2em auto}}
table{{border-collapse:collapse;width:100%}}th,td{{border:1px solid #ddd;padding:8px}}
th{{background:#16a34a;color:#fff}}tr:nth-child(even){{background:#f9fafb}}</style></head>
<body><h1>MMseqs2 Sequence Search</h1>
<p>Date: {date} &nbsp;|&nbsp; Hits: {n}</p>
<table><tr><th>Target</th><th>Description</th><th>% ID</th><th>E-value</th><th>Score</th></tr>
{rows}</table></body></html>'''.format(date=str(datetime.date.today()), n=len(hits), rows=rows)
open('mmseqs2_report.html', 'w').write(html)
PYEOF

    cat > versions.yml << EOF
MMSEQS2_SEQUENCE_SEARCH:
  mmseqs2: \$(mmseqs version 2>/dev/null || echo "unknown")
EOF
    """
}

// ---------------------------------------------------------------------------
// Merge and summarise results
// ---------------------------------------------------------------------------

process MERGE_SEARCH_RESULTS {
    tag "${meta.id}"
    label 'process_low'
    publishDir "${params.outdir}/${meta.id}", mode: params.publish_dir_mode

    container 'python:3.11-slim'

    input:
    tuple val(meta), path(foldseek_hits)
    tuple val(meta2), path(mmseqs2_hits)

    output:
    tuple val(meta), path('combined_hits.tsv'),   emit: hits
    tuple val(meta), path('search_summary.json'), emit: summary
    tuple val(meta), path('combined_report.html'),emit: report
    path 'versions.yml',                          emit: versions

    script:
    """
    python3 << 'PYEOF'
import csv, json, datetime, os

def load_tsv(path):
    if not os.path.exists(path): return []
    with open(path) as f:
        return list(csv.DictReader(f, delimiter='\\t'))

fs  = load_tsv('${foldseek_hits}')
mms = load_tsv('${mmseqs2_hits}')
for h in fs:  h['search_type'] = 'structural'
for h in mms: h['search_type'] = 'sequence'
all_hits = fs + mms

fields = ['search_type','query','target','pident','alnlen','evalue','bitscore','tdescription']
with open('combined_hits.tsv','w',newline='') as f:
    w = csv.DictWriter(f, fieldnames=fields, delimiter='\\t', extrasaction='ignore')
    w.writeheader(); w.writerows(all_hits)

summary = {
    'generated_at': datetime.datetime.utcnow().isoformat()+'Z',
    'sample_id': '${meta.id}',
    'foldseek_hits': len(fs), 'mmseqs2_hits': len(mms), 'total_hits': len(all_hits),
    'top_structural': [{'target':h['target'],'evalue':h.get('evalue',''),'description':h.get('tdescription','')} for h in fs[:5]],
    'top_sequence':   [{'target':h['target'],'evalue':h.get('evalue',''),'description':h.get('tdescription','')} for h in mms[:5]],
}
json.dump(summary, open('search_summary.json','w'), indent=2)

def make_rows(hits):
    return ''.join(
        '<tr><td>{target}</td><td>{tdescription}</td><td>{pident}</td><td>{evalue}</td><td>{bitscore}</td></tr>'.format(**h)
        for h in hits)

html = '''<!DOCTYPE html>
<html><head><title>AlphaFold DB Search Report</title>
<style>body{{font-family:sans-serif;max-width:1000px;margin:2em auto}}h2{{margin-top:2em}}
table{{border-collapse:collapse;width:100%;margin-bottom:2em}}
th,td{{border:1px solid #ddd;padding:8px;font-size:.9em}}
.fsh th{{background:#2563eb;color:#fff}}.msh th{{background:#16a34a;color:#fff}}
tr:nth-child(even){{background:#f9fafb}}</style></head>
<body><h1>AlphaFold DB Search -- {sample}</h1>
<p>{date} | Structural: <b>{nfs}</b> | Sequence: <b>{nmms}</b></p>
<h2>Foldseek -- Structural Analogs</h2>
<table><tr class="fsh"><th>Target</th><th>Description</th><th>% ID</th><th>E-value</th><th>Score</th></tr>{fs_rows}</table>
<h2>MMseqs2 -- Sequence Homologs</h2>
<table><tr class="msh"><th>Target</th><th>Description</th><th>% ID</th><th>E-value</th><th>Score</th></tr>{mms_rows}</table>
</body></html>'''.format(
    sample='${meta.id}', date=str(datetime.date.today()),
    nfs=len(fs), nmms=len(mms),
    fs_rows=make_rows(fs), mms_rows=make_rows(mms))
open('combined_report.html','w').write(html)
print(f"Combined: {len(all_hits)} hits ({len(fs)} structural + {len(mms)} sequence)")
PYEOF

    cat > versions.yml << EOF
MERGE_SEARCH_RESULTS:
  python: \$(python3 --version | cut -d' ' -f2)
EOF
    """
}

// ---------------------------------------------------------------------------
// Workflow
// ---------------------------------------------------------------------------

workflow ALPHAFOLD_DB_SEARCH {

    take:
    ch_query   // channel: tuple [meta, path] -- query structure (PDB/CIF)

    main:
    FOLDSEEK_STRUCTURAL_SEARCH(
        ch_query,
        params.s3_db_base,
        params.max_hits,
        params.evalue,
        params.coverage
    )

    MMSEQS2_SEQUENCE_SEARCH(
        ch_query,
        params.s3_db_base,
        params.max_hits,
        params.evalue,
        params.min_seq_id,
        params.coverage
    )

    MERGE_SEARCH_RESULTS(
        FOLDSEEK_STRUCTURAL_SEARCH.out.hits,
        MMSEQS2_SEQUENCE_SEARCH.out.hits
    )

    emit:
    combined_hits   = MERGE_SEARCH_RESULTS.out.hits
    summary         = MERGE_SEARCH_RESULTS.out.summary
    report          = MERGE_SEARCH_RESULTS.out.report
    foldseek_hits   = FOLDSEEK_STRUCTURAL_SEARCH.out.hits
    foldseek_report = FOLDSEEK_STRUCTURAL_SEARCH.out.report
    mmseqs2_hits    = MMSEQS2_SEQUENCE_SEARCH.out.hits
    mmseqs2_report  = MMSEQS2_SEQUENCE_SEARCH.out.report
    versions        = MERGE_SEARCH_RESULTS.out.versions
}

// ---------------------------------------------------------------------------
// Entry point (standalone run)
// ---------------------------------------------------------------------------

workflow {
    if (!params.query_pdb) {
        error "Provide --query_pdb <path_or_s3_uri>"
    }

    ch_query = Channel.fromPath(params.query_pdb)
        .map { f -> [ [id: f.baseName], f ] }

    ALPHAFOLD_DB_SEARCH(ch_query)
}
