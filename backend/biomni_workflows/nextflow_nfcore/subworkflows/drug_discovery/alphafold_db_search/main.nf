#!/usr/bin/env nextflow

/**
 * alphafold_db_search -- structural + sequence similarity search via web APIs
 *
 * Uses free public APIs instead of a local database copy:
 *   - Foldseek web server (search.foldseek.com): structural search against
 *     AlphaFold DB, PDB100, and SwissProt via the 3Di alphabet
 *   - EBI HMMER (hmmer.ebi.ac.uk): sequence-based homology search
 *
 * Runs on a single cheap instance (1 vCPU, 2 GB) — no S3 database sync,
 * no heavy binaries, no 64 GB memory requirement.
 *
 * Inputs:
 *   params.query_pdb   -- PDB ID (4 chars, e.g. '1IEP') OR path to .pdb file
 *   params.query_fasta -- FASTA sequence string or path (for HMMER; auto-extracted from PDB if absent)
 *   params.max_hits    -- max results per search (default: 50)
 *   params.evalue      -- e-value cutoff (default: 0.001)
 *   params.databases   -- comma-separated Foldseek databases (default: 'afdb50,afdb-swissprot,pdb100')
 */

nextflow.enable.dsl = 2

params.query_pdb   = ''
params.query_fasta = ''
params.max_hits    = 50
params.evalue      = 0.001
params.databases   = 'afdb50,afdb-swissprot,pdb100'
params.outdir      = 'results'
params.publish_dir_mode = 'copy'

// ---------------------------------------------------------------------------
// Process: Foldseek API structural search + EBI HMMER sequence search
// Single process — both are async HTTP polls, no heavy tools needed.
// Runs on the standard queue with minimal resources.
// ---------------------------------------------------------------------------

process ALPHAFOLD_API_SEARCH {
    tag "${meta.id}"
    label 'process_low'
    publishDir "${params.outdir}/${meta.id}", mode: params.publish_dir_mode

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate-nextflow-base:latest' \
        : 'python:3.11-slim'

    input:
    tuple val(meta), val(query_pdb)
    val  max_hits
    val  evalue
    val  databases

    output:
    tuple val(meta), path('foldseek_hits.tsv'),    emit: foldseek_hits
    tuple val(meta), path('hmmer_hits.tsv'),        emit: hmmer_hits
    tuple val(meta), path('search_summary.json'),   emit: summary
    tuple val(meta), path('combined_report.html'),  emit: report
    path 'versions.yml',                            emit: versions

    script:
    """
    python3 << 'PYEOF'
import json, csv, time, datetime, urllib.request, urllib.parse, urllib.error, sys, os, re

query_pdb = "${query_pdb}".strip()
max_hits  = int("${max_hits}")
evalue    = float("${evalue}")
databases = "${databases}".split(',')

# ---------------------------------------------------------------------------
# Step 1: Fetch PDB structure (if 4-char ID) or read from file
# ---------------------------------------------------------------------------
def fetch_pdb(query):
    pdb_id = query.upper()
    if re.match("^[A-Z0-9]{4}\$", pdb_id):
        url = f"https://files.rcsb.org/download/{pdb_id}.pdb"
        print(f"[API] Fetching PDB {pdb_id} from RCSB...")
        with urllib.request.urlopen(url, timeout=30) as r:
            return pdb_id, r.read().decode()
    elif os.path.exists(query):
        with open(query) as f:
            return os.path.basename(query), f.read()
    else:
        raise ValueError(f"query_pdb '{query}' is not a 4-char PDB ID or existing file path")

sample_id, pdb_content = fetch_pdb(query_pdb)
print(f"[API] Got structure for {sample_id} ({len(pdb_content)} bytes)")

# Extract SEQRES / ATOM sequence for HMMER
fasta_seq = ""
aa3 = {'ALA':'A','ARG':'R','ASN':'N','ASP':'D','CYS':'C','GLN':'Q','GLU':'E',
       'GLY':'G','HIS':'H','ILE':'I','LEU':'L','LYS':'K','MET':'M','PHE':'F',
       'PRO':'P','SER':'S','THR':'T','TRP':'W','TYR':'Y','VAL':'V'}
seqres = []
for line in pdb_content.splitlines():
    if line.startswith('SEQRES'):
        seqres += [aa3.get(r,'X') for r in line[19:].split()]
if seqres:
    fasta_seq = ''.join(seqres)
    print(f"[API] Extracted SEQRES sequence: {len(fasta_seq)} residues")

# ---------------------------------------------------------------------------
# Step 2: Foldseek web API structural search
# Docs: https://search.foldseek.com/api
# ---------------------------------------------------------------------------
foldseek_hits = []
try:
    print("[API] Submitting Foldseek structural search...")
    import tempfile, io
    # Build multipart form: q=pdb_content, mode=3diaa, database[]=afdb50, ...
    boundary = "BioMateBoundary42"
    body_parts = []
    def add_field(name, value):
        body_parts.append(
            f'--{boundary}\\r\\nContent-Disposition: form-data; name="{name}"\\r\\n\\r\\n{value}\\r\\n'.encode()
        )
    def add_file(name, filename, content):
        body_parts.append(
            f'--{boundary}\\r\\nContent-Disposition: form-data; name="{name}"; filename="{filename}"\\r\\nContent-Type: text/plain\\r\\n\\r\\n'.encode()
            + content.encode() + b'\\r\\n'
        )

    add_file('q', f'{sample_id}.pdb', pdb_content)
    add_field('mode', '3diaa')
    for db in databases:
        add_field('database[]', db.strip())
    body = b''.join(body_parts) + f'--{boundary}--\\r\\n'.encode()

    req = urllib.request.Request(
        'https://search.foldseek.com/api/ticket',
        data=body,
        headers={'Content-Type': f'multipart/form-data; boundary={boundary}'},
        method='POST'
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        ticket = json.loads(r.read())
    ticket_id = ticket['id']
    print(f"[API] Foldseek ticket: {ticket_id}")

    # Poll for completion (up to 10 minutes)
    for attempt in range(60):
        time.sleep(10)
        url = f'https://search.foldseek.com/api/ticket/{ticket_id}'
        with urllib.request.urlopen(url, timeout=30) as r:
            status = json.loads(r.read())
        print(f"[API] Foldseek status: {status.get('status','?')} (attempt {attempt+1})")
        if status.get('status') == 'COMPLETE':
            break
        if status.get('status') == 'ERROR':
            raise RuntimeError(f"Foldseek search failed: {status}")
    else:
        raise TimeoutError("Foldseek search timed out after 10 minutes")

    # Fetch results
    url = f'https://search.foldseek.com/api/result/{ticket_id}/0'
    with urllib.request.urlopen(url, timeout=30) as r:
        results = json.loads(r.read())

    for db_result in results.get('results', []):
        for aln in db_result.get('alignments', [[]])[0][:max_hits]:
            if float(aln.get('eval', 1)) <= evalue:
                foldseek_hits.append({
                    'database':    db_result.get('db', ''),
                    'target':      aln.get('target', ''),
                    'description': aln.get('taxName', '') or aln.get('target', ''),
                    'pident':      f"{aln.get('seqId', 0)*100:.1f}",
                    'alnlen':      aln.get('alnLength', ''),
                    'evalue':      aln.get('eval', ''),
                    'bitscore':    aln.get('score', ''),
                    'prob':        f"{aln.get('prob', 0)*100:.1f}",
                })
    print(f"[API] Foldseek: {len(foldseek_hits)} hits (e<={evalue})")
except Exception as ex:
    print(f"[WARN] Foldseek search failed: {ex}", file=sys.stderr)

# ---------------------------------------------------------------------------
# Step 3: EBI HMMER phmmer sequence search (runs against UniProtKB)
# API: https://www.ebi.ac.uk/Tools/hmmer/search/phmmer
# ---------------------------------------------------------------------------
hmmer_hits = []
if fasta_seq:
    try:
        print("[API] Submitting EBI HMMER phmmer sequence search...")
        fasta_str = f">query\\n{fasta_seq}"
        post_data = urllib.parse.urlencode({
            'seqdb': 'uniprotkb',
            'seq':   fasta_str,
            'E':     str(evalue),
            'domE':  str(evalue),
            'incE':  str(evalue),
            'incdomE': str(evalue),
        }).encode()
        req = urllib.request.Request(
            'https://www.ebi.ac.uk/Tools/hmmer/search/phmmer',
            data=post_data,
            headers={
                'Content-Type': 'application/x-www-form-urlencoded',
                'Accept': 'application/json',
            },
            method='POST'
        )
        # EBI HMMER returns redirect to results
        opener = urllib.request.build_opener(urllib.request.HTTPRedirectHandler())
        with opener.open(req, timeout=120) as r:
            hmmer_data = json.loads(r.read())

        hits_raw = hmmer_data.get('results', {}).get('hits', [])[:max_hits]
        for h in hits_raw:
            hmmer_hits.append({
                'accession':   h.get('acc', ''),
                'name':        h.get('name', ''),
                'description': h.get('desc', ''),
                'evalue':      h.get('evalue', ''),
                'score':       h.get('score', ''),
                'species':     h.get('species', ''),
            })
        print(f"[API] HMMER: {len(hmmer_hits)} hits")
    except Exception as ex:
        print(f"[WARN] HMMER search failed: {ex}", file=sys.stderr)
else:
    print("[WARN] No SEQRES found in PDB — skipping HMMER sequence search")

# ---------------------------------------------------------------------------
# Write outputs
# ---------------------------------------------------------------------------
fs_fields = ['database','target','description','pident','alnlen','evalue','bitscore','prob']
with open('foldseek_hits.tsv', 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=fs_fields, delimiter='\\t', extrasaction='ignore')
    w.writeheader(); w.writerows(foldseek_hits)

hmmer_fields = ['accession','name','description','evalue','score','species']
with open('hmmer_hits.tsv', 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=hmmer_fields, delimiter='\\t', extrasaction='ignore')
    w.writeheader(); w.writerows(hmmer_hits)

summary = {
    'generated_at':    datetime.datetime.utcnow().isoformat() + 'Z',
    'query':           query_pdb,
    'sample_id':       sample_id,
    'foldseek_hits':   len(foldseek_hits),
    'hmmer_hits':      len(hmmer_hits),
    'databases':       databases,
    'evalue_cutoff':   evalue,
    'top_structural':  foldseek_hits[:5],
    'top_sequence':    hmmer_hits[:5],
}
json.dump(summary, open('search_summary.json', 'w'), indent=2)

def fs_rows(hits):
    rows = []
    for h in hits:
        rows.append(
            "<tr><td>" + h["target"] + "</td><td>" + h["description"] + "</td>"
            "<td>" + h["pident"] + "%</td><td>" + str(h["evalue"]) + "</td>"
            "<td>" + h["prob"] + "%</td><td>" + h["database"] + "</td></tr>"
        )
    return "".join(rows)

def hm_rows(hits):
    rows = []
    for h in hits:
        rows.append(
            "<tr><td>" + h["accession"] + "</td><td>" + h["name"] + "</td>"
            "<td>" + h["description"][:80] + "</td><td>" + str(h["evalue"]) + "</td>"
            "<td>" + h["species"] + "</td></tr>"
        )
    return "".join(rows)

today = str(datetime.date.today())
n_fs  = str(len(foldseek_hits))
n_hm  = str(len(hmmer_hits))
html_parts = [
    "<!DOCTYPE html><html><head><title>AlphaFold DB Search - " + sample_id + "</title>",
    "<style>body{font-family:sans-serif;max-width:1100px;margin:2em auto}",
    "h2{margin-top:2em}table{border-collapse:collapse;width:100%;margin-bottom:2em}",
    "th,td{border:1px solid #ddd;padding:7px;font-size:.85em}",
    ".fsh th{background:#2563eb;color:#fff}.hh th{background:#16a34a;color:#fff}",
    "tr:nth-child(even){background:#f9fafb}</style></head><body>",
    "<h1>AlphaFold DB Search - " + sample_id + "</h1>",
    "<p>" + today + " | Foldseek structural: <b>" + n_fs + "</b> | HMMER sequence: <b>" + n_hm + "</b></p>",
    "<h2>Foldseek - Structural Analogs (3Di)</h2>",
    '<table class="fsh"><tr><th>Target</th><th>Description</th><th>% SeqID</th><th>E-value</th><th>Prob</th><th>Database</th></tr>',
    fs_rows(foldseek_hits),
    "</table>",
    "<h2>EBI HMMER phmmer - Sequence Homologs</h2>",
    '<table class="hh"><tr><th>Accession</th><th>Name</th><th>Description</th><th>E-value</th><th>Species</th></tr>',
    hm_rows(hmmer_hits),
    "</table></body></html>",
]
open("combined_report.html", "w").write("".join(html_parts))
print(f"[API] Done: {len(foldseek_hits)} structural + {len(hmmer_hits)} sequence hits")
PYEOF

    cat > versions.yml << EOF
ALPHAFOLD_API_SEARCH:
  python: \$(python3 --version | cut -d' ' -f2)
  foldseek_api: search.foldseek.com
  hmmer_api: hmmer.ebi.ac.uk
EOF
    """
}

// ---------------------------------------------------------------------------
// Named workflow (for inclusion by parent pipelines)
// ---------------------------------------------------------------------------

workflow ALPHAFOLD_DB_SEARCH {
    take:
    ch_query   // channel: tuple [meta, val(pdb_id_or_path)]

    main:
    ALPHAFOLD_API_SEARCH(
        ch_query,
        params.max_hits,
        params.evalue,
        params.databases
    )

    emit:
    foldseek_hits = ALPHAFOLD_API_SEARCH.out.foldseek_hits
    hmmer_hits    = ALPHAFOLD_API_SEARCH.out.hmmer_hits
    summary       = ALPHAFOLD_API_SEARCH.out.summary
    report        = ALPHAFOLD_API_SEARCH.out.report
    versions      = ALPHAFOLD_API_SEARCH.out.versions
}

// ---------------------------------------------------------------------------
// Entry point (standalone run)
// ---------------------------------------------------------------------------

workflow {
    if (!params.query_pdb) {
        error "Provide --query_pdb <PDB_ID_or_path>"
    }
    ch_query = Channel.of( [ [id: params.query_pdb.toString().replaceAll(/\.pdb$/, '').toUpperCase()],
                               params.query_pdb.toString() ] )
    ALPHAFOLD_DB_SEARCH(ch_query)
}
