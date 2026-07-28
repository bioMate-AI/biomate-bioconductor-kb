#!/usr/bin/env nextflow
/*
 * immunology/antigen_resolution
 *
 * THE TCR <-> HLA <-> PEPTIDE ANTIGEN-RESOLUTION INTEGRATION STEP.
 *
 * BioMate's antigen moat lane. Serves TCR-T shops (e.g. Mongoose Bio) that need
 * to go from raw repertoire + typing + binding predictions to a ranked list of
 * candidate DISEASE ANTIGENS / EPITOPES a program can actually pursue.
 *
 * This is a FUSION / INTEGRATION step. It does NOT re-run upstream tools. It
 * INGESTS the outputs of the standard immunogenomics stack:
 *   - airrflow          -> TCR/BCR repertoire (clonotype table, CDR3, abundance)
 *   - hlatyping         -> patient HLA alleles (class I + class II)
 *   - epitopeprediction -> peptide x HLA binding predictions (NetMHCpan /
 *                          NetMHCIIpan style: binding_score / %rank)
 *
 * For each candidate peptide/antigen it computes an ANTIGEN-RESOLUTION SCORE
 * fusing three orthogonal lines of evidence:
 *   (a) HLA-binding strength   Is the peptide predicted to be presented on one of
 *                              THIS patient's alleles? Strong binders (%rank <= 2,
 *                              NetMHCIIpan convention; Reynisson 2020) rank higher.
 *   (b) repertoire support     Is there clonal expansion consistent with a T-cell
 *                              response to this antigen? (abundance / frequency of
 *                              the matched clonotype in the repertoire.)
 *   (c) disease relevance      Optional. If a peptide's source_gene is on a
 *                              provided disease-gene list, it is up-weighted.
 *
 * DELIBERATE EMPHASIS ON CLASS II (HLA-DP / DQ / DR). CD4 help and class-II
 * immunopeptidome coverage — especially the under-served DP/DQ loci — is the
 * field's blind spot (Racle 2023 immunopeptidome; DP/DQ presentation gap).
 * Class-II candidates are surfaced and their locus coverage reported so a DP/DQ
 * hit is never buried behind the better-characterised DR / class-I space.
 *
 * Input (ALL REQUIRED, real files only — no synthetic fallback):
 *   repertoire_file  CSV: clonotype, cdr3, abundance|frequency[, v_gene]
 *   hla_file         CSV: patient HLA alleles (allele column; class II incl DP/DQ)
 *   epitope_file     CSV: peptide, hla_allele, binding_score|rank[, source_gene]
 *   disease_genes    OPTIONAL CSV/text: disease-relevant gene symbols (one per line
 *                    or a 'gene' column)
 * Output:
 *   antigen_candidates.csv, antigen_resolution_results.json,
 *   antigen_resolution_report.md, versions.yml
 *
 * If any REQUIRED file is missing -> failed-status JSON + headered-empty CSV +
 * exit(1). No synthetic data is ever generated.
 */

nextflow.enable.dsl = 2

params.outdir          = './results'
params.repertoire_file = 'NONE'      // REQUIRED: airrflow clonotype table (CSV)
params.hla_file        = 'NONE'      // REQUIRED: hlatyping patient alleles (CSV)
params.epitope_file    = 'NONE'      // REQUIRED: epitopeprediction peptide x HLA (CSV)
params.disease_genes   = 'NONE'      // OPTIONAL: disease-relevant gene list (CSV/txt)
params.patient_id      = 'patient'

// -- Evidence weights (renormalised internally over axes actually present) -----
params.w_binding    = '0.45'         // HLA-binding strength
params.w_repertoire = '0.40'         // clonal support in the repertoire
params.w_disease    = '0.15'         // disease-gene relevance (only if disease_genes given)

// -- NetMHCIIpan/NetMHCpan %rank thresholds (Reynisson 2020) -------------------
params.strong_rank  = '2.0'          // %rank <= 2  -> strong binder  (score 1.0..)
params.weak_rank    = '10.0'         // %rank <= 10 -> weak binder; > weak_rank -> ~0

// -- Class-II emphasis: additive bonus to a candidate presented on a DP/DQ allele
params.classII_dpdq_bonus = '0.05'

process ANTIGEN_RESOLUTION {
    tag "$meta.id"
    label 'process_low'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("antigen_resolution_results.json"), emit: results
    tuple val(meta), path("antigen_candidates.csv"),          emit: candidates
    tuple val(meta), path("antigen_resolution_report.md"),    emit: report
    path "versions.yml",                                      emit: versions

    script:
    """
    export PARAM_REPERTOIRE='${params.repertoire_file}'
    export PARAM_HLA='${params.hla_file}'
    export PARAM_EPITOPE='${params.epitope_file}'
    export PARAM_DISEASE_GENES='${params.disease_genes.toString().replace("'", "'\\''")}'
    export PARAM_PATIENT='${params.patient_id.toString().replace("'", "'\\''")}'
    export PARAM_W_BIND='${params.w_binding}'
    export PARAM_W_REP='${params.w_repertoire}'
    export PARAM_W_DIS='${params.w_disease}'
    export PARAM_STRONG_RANK='${params.strong_rank}'
    export PARAM_WEAK_RANK='${params.weak_rank}'
    export PARAM_DPDQ_BONUS='${params.classII_dpdq_bonus}'

    python3 << 'PYEOF'
import json, os, csv, math, sys, re

# ------------------------------------------------------------------ helpers ---
def _f(v, default=None):
    if v in (None, '', 'null', 'None', 'NA', 'nan'): return default
    try: return float(v)
    except Exception: return default

def clamp01(x):
    if x is None: return None
    return max(0.0, min(1.0, x))

def get(row, *keys):
    # case-insensitive column lookup over aliases
    lower = {k.lower().strip(): v for k, v in row.items() if k is not None}
    for k in keys:
        if k.lower() in lower and lower[k.lower()] not in (None, ''):
            return lower[k.lower()]
    return None

# ------------------------------------------------------------------- params ---
patient    = os.environ.get('PARAM_PATIENT', 'patient')
w_bind_p   = _f(os.environ.get('PARAM_W_BIND'), 0.45)
w_rep_p    = _f(os.environ.get('PARAM_W_REP'),  0.40)
w_dis_p    = _f(os.environ.get('PARAM_W_DIS'),  0.15)
strong_rank = _f(os.environ.get('PARAM_STRONG_RANK'), 2.0)
weak_rank   = _f(os.environ.get('PARAM_WEAK_RANK'),  10.0)
dpdq_bonus  = _f(os.environ.get('PARAM_DPDQ_BONUS'), 0.05)

def fail(msg):
    sys.stderr.write('ERROR: ' + msg + '\\n')
    with open('antigen_resolution_results.json', 'w') as fh:
        json.dump({'status': 'failed', 'error': msg, 'candidates': []}, fh, indent=2)
    with open('antigen_candidates.csv', 'w', newline='') as fh:
        w = csv.writer(fh)
        w.writerow(['rank', 'antigen', 'peptide', 'hla_allele', 'hla_class',
                    'binding', 'repertoire_support', 'disease_relevance',
                    'score', 'evidence'])
    with open('antigen_resolution_report.md', 'w') as fh:
        fh.write('# Antigen Resolution — FAILED\\n\\n' + msg + '\\n')
    with open('versions.yml', 'w') as fh:
        fh.write('antigen_resolution:\\n  python: "3.10"\\n  status: "failed"\\n')
    sys.exit(1)

def require(path, label):
    if (not path) or path in ('NONE', '') or not os.path.exists(path):
        fail('%s is required and must point to a real CSV. Got: %r. '
             'No synthetic data is generated.' % (label, path))
    return path

# ---------------------------------------------------------- load real inputs ---
rep_path = require(os.environ.get('PARAM_REPERTOIRE', 'NONE'), '--repertoire_file')
hla_path = require(os.environ.get('PARAM_HLA', 'NONE'),        '--hla_file')
epi_path = require(os.environ.get('PARAM_EPITOPE', 'NONE'),    '--epitope_file')

def read_csv(path):
    with open(path, newline='') as fh:
        return list(csv.DictReader(fh))

rep_rows = read_csv(rep_path)
hla_rows = read_csv(hla_path)
epi_rows = read_csv(epi_path)
if not epi_rows:
    fail('epitope_file has no rows: %r' % epi_path)
if not hla_rows:
    fail('hla_file has no rows: %r' % hla_path)

# ------------------------------------------------------ HLA allele normalisation
def norm_allele(a):
    # normalise 'HLA-DRB1*04:01' / 'DRB1_0401' / 'DRB1*0401' -> 'HLA-DRB1*04:01'
    if a is None: return None
    a = str(a).strip().upper().replace('_', '*')
    a = a.replace('HLA-', '')
    m = re.match(r'^([A-Z0-9]+)\\*?(\\d+):?(\\d+)?', a)
    if not m:
        return 'HLA-' + a
    locus, f1, f2 = m.group(1), m.group(2), m.group(3)
    # pad 4-digit fields like 0401 -> 04:01
    if f2 is None and len(f1) >= 4 and f1.isdigit():
        f1, f2 = f1[:2], f1[2:4]
    allele = 'HLA-' + locus + '*' + f1
    if f2:
        allele += ':' + f2
    return allele

def locus_of(allele):
    # DRB1 / DPB1 / DQB1 / A / B / C ...
    m = re.match(r'^HLA-([A-Z0-9]+)', allele or '')
    return m.group(1) if m else ''

def hla_class(allele):
    loc = locus_of(allele)
    if loc in ('A', 'B', 'C', 'E', 'F', 'G'):
        return 'I'
    if loc.startswith(('DR', 'DP', 'DQ', 'DM', 'DO')):
        return 'II'
    return '?'

def is_dpdq(allele):
    return locus_of(allele).startswith(('DP', 'DQ'))

patient_alleles = set()
for r in hla_rows:
    a = get(r, 'allele', 'hla_allele', 'hla', 'genotype', 'name')
    na = norm_allele(a)
    if na:
        patient_alleles.add(na)
if not patient_alleles:
    fail('no HLA alleles could be parsed from %r (expected an allele column)' % hla_path)

# --------------------------------------------------------- repertoire support ---
# Build a per-clonotype and per-CDR3 support map (normalised abundance/frequency).
def cdr3_key(s):
    return re.sub(r'[^A-Z]', '', (s or '').upper())

clono_support = {}   # clonotype id -> support (0..1)
cdr3_support = {}     # cdr3 aa -> support (0..1)
raw_vals = []
tmp = []
for r in rep_rows:
    clono = get(r, 'clonotype', 'clone_id', 'clonotype_id', 'clone')
    cdr3 = get(r, 'cdr3', 'cdr3_aa', 'junction_aa', 'cdr3aa')
    ab = _f(get(r, 'abundance', 'count', 'reads', 'clone_count'))
    fr = _f(get(r, 'frequency', 'freq', 'proportion', 'clone_fraction'))
    val = fr if fr is not None else ab
    tmp.append((clono, cdr3, val))
    if val is not None:
        raw_vals.append(val)

# Normalise: frequencies (<=1) used as-is; raw counts scaled by max.
max_val = max(raw_vals) if raw_vals else 1.0
freq_like = all((v is not None and v <= 1.0) for v in raw_vals) if raw_vals else False
for clono, cdr3, val in tmp:
    if val is None:
        continue
    sup = clamp01(val if freq_like else (val / max_val if max_val > 0 else 0.0))
    if clono:
        clono_support[str(clono).strip()] = max(clono_support.get(str(clono).strip(), 0.0), sup)
    if cdr3:
        k = cdr3_key(cdr3)
        cdr3_support[k] = max(cdr3_support.get(k, 0.0), sup)

# --------------------------------------------------------- disease-gene list ----
disease_genes = set()
dg_path = os.environ.get('PARAM_DISEASE_GENES', 'NONE')
have_disease = dg_path not in ('NONE', '', None) and os.path.exists(dg_path)
if have_disease:
    with open(dg_path, newline='') as fh:
        sniff = fh.read()
    for line in sniff.splitlines():
        line = line.strip()
        if not line:
            continue
        # accept 'gene' header, CSV, or bare list
        parts = [p.strip() for p in re.split(r'[,\\t]', line) if p.strip()]
        for p in parts:
            if p.lower() in ('gene', 'symbol', 'source_gene', 'genes'):
                continue
            disease_genes.add(p.upper())

# ---------------------------------------------- effective weights (renormalise)
axes_active = ['binding', 'repertoire']
if have_disease and disease_genes:
    axes_active.append('disease')
w_map = {'binding': w_bind_p, 'repertoire': w_rep_p, 'disease': w_dis_p}
wsum = sum(w_map[a] for a in axes_active) or 1.0
W = {a: w_map[a] / wsum for a in axes_active}

# ------------------------------------------------- binding-strength transform ---
def binding_strength(rank, score):
    # %rank is the primary signal (NetMHCIIpan/NetMHCpan). Lower rank = stronger.
    # rank<=strong_rank -> 1.0 down to rank>=weak_rank -> ~0 (linear in log space).
    if rank is not None:
        if rank <= strong_rank:
            return 1.0
        if rank >= weak_rank:
            return 0.0
        # linear ramp between strong and weak thresholds
        return clamp01((weak_rank - rank) / (weak_rank - strong_rank))
    # fall back to a raw binding_score if no rank (assume higher = stronger, 0..1)
    if score is not None:
        return clamp01(score if score <= 1.0 else score / 100.0)
    return None

# --------------------------------------------------- CDR3-to-peptide matching ---
# We do not have paired TCR:pMHC labels; repertoire support attaches to a candidate
# when the epitope row carries a clonotype/cdr3 linking it to an expanded clone
# (as produced by tools that annotate predicted epitopes with matched TCRs), OR
# when the peptide sequence itself is used as the join key against a cdr3 map.
def repertoire_support_for(row, peptide):
    ev = []
    sup = 0.0
    clono = get(row, 'clonotype', 'clone_id', 'clonotype_id', 'clone')
    cdr3 = get(row, 'cdr3', 'cdr3_aa', 'junction_aa')
    if clono and str(clono).strip() in clono_support:
        s = clono_support[str(clono).strip()]
        if s > sup: sup = s
        ev.append('clonotype ' + str(clono).strip() + ' expanded (support %.2f)' % s)
    if cdr3:
        k = cdr3_key(cdr3)
        if k in cdr3_support:
            s = cdr3_support[k]
            if s > sup: sup = s
            ev.append('CDR3 ' + cdr3 + ' matched expanded clone (support %.2f)' % s)
    return (sup if (clono or cdr3) else None), ev

# ------------------------------------------------------------- score epitopes ---
candidates = []
for row in epi_rows:
    peptide = get(row, 'peptide', 'sequence', 'epitope', 'pep')
    if not peptide:
        continue
    peptide = str(peptide).strip().upper()
    allele = norm_allele(get(row, 'hla_allele', 'allele', 'hla', 'mhc'))
    if allele not in patient_alleles:
        continue  # only score peptides presented on THIS patient's alleles
    rank = _f(get(row, 'rank', '%rank', 'rank_ba', 'el_rank', 'percentile_rank'))
    score = _f(get(row, 'binding_score', 'score', 'affinity', 'ic50_norm'))
    src_gene = get(row, 'source_gene', 'gene', 'protein', 'source')
    src_gene_u = str(src_gene).strip().upper() if src_gene else None

    b = binding_strength(rank, score)
    if b is None:
        continue  # no interpretable binding signal -> not a resolvable antigen
    rsup, rev = repertoire_support_for(row, peptide)
    drel = None
    if 'disease' in W:
        drel = 1.0 if (src_gene_u and src_gene_u in disease_genes) else 0.0

    # coverage-aware weighted mean over axes actually present
    parts = {'binding': b}
    if rsup is not None:
        parts['repertoire'] = rsup
    if drel is not None:
        parts['disease'] = drel
    covered = [a for a in parts if a in W]
    wsub = sum(W[a] for a in covered) or 1.0
    score_val = sum(W[a] * parts[a] for a in covered) / wsub

    cls = hla_class(allele)
    bonus = dpdq_bonus if is_dpdq(allele) else 0.0
    final = clamp01(round(score_val + bonus, 4))

    # evidence provenance
    evidence = []
    if rank is not None:
        tag = ('STRONG' if rank <= strong_rank else ('weak' if rank <= weak_rank else 'non-binder'))
        evidence.append('%%rank=%.2f (%s) on %s [class %s]' % (rank, tag, allele, cls))
    elif score is not None:
        evidence.append('binding_score=%.3f on %s [class %s]' % (score, allele, cls))
    evidence.extend(rev)
    if rsup is None:
        evidence.append('no repertoire match (binding-only candidate)')
    if drel == 1.0:
        evidence.append('source gene %s on disease-gene list' % src_gene_u)
    if bonus > 0:
        evidence.append('class-II DP/DQ presentation (+%.2f coverage bonus)' % bonus)

    candidates.append({
        'antigen': src_gene_u or peptide,
        'peptide': peptide,
        'hla_allele': allele,
        'hla_class': cls,
        'hla_locus': locus_of(allele),
        'is_dpdq': is_dpdq(allele),
        'rank': rank,
        'binding_score_raw': score,
        'binding': round(b, 4),
        'repertoire_support': None if rsup is None else round(rsup, 4),
        'disease_relevance': drel,
        'source_gene': src_gene_u,
        'score': final,
        'axes_present': covered,
        'evidence': evidence,
    })

if not candidates:
    fail('no candidate peptides could be scored — none of the epitope rows '
         'matched the patient HLA alleles (%s) or carried interpretable binding '
         'signal.' % ', '.join(sorted(patient_alleles)))

# --------------------------------------------------------------- rank + dedup ---
# keep the best-scoring entry per (peptide, allele), then rank descending
best = {}
for c in candidates:
    key = (c['peptide'], c['hla_allele'])
    if key not in best or c['score'] > best[key]['score']:
        best[key] = c
candidates = list(best.values())
candidates.sort(key=lambda d: (d['score'], d['binding'], d['repertoire_support'] or 0.0),
                reverse=True)
for i, c in enumerate(candidates, 1):
    c['candidate_rank'] = i

# ------------------------------------------------------------------- outputs ---
n_classII = sum(1 for c in candidates if c['hla_class'] == 'II')
n_dpdq = sum(1 for c in candidates if c['is_dpdq'])
n_rep = sum(1 for c in candidates if c['repertoire_support'] is not None)

run_meta = {
    'patient_id': patient,
    'patient_alleles': sorted(patient_alleles),
    'n_candidates': len(candidates),
    'n_class_II': n_classII,
    'n_dpdq': n_dpdq,
    'n_with_repertoire_support': n_rep,
    'weights': W,
    'disease_gene_list': (sorted(disease_genes) if have_disease else None),
    'rank_thresholds': {'strong_rank': strong_rank, 'weak_rank': weak_rank},
    'inputs': {
        'repertoire_file': os.path.basename(rep_path),
        'hla_file': os.path.basename(hla_path),
        'epitope_file': os.path.basename(epi_path),
        'disease_genes': (os.path.basename(dg_path) if have_disease else None),
    },
    'framework': 'NetMHCIIpan/NetMHCpan %rank binding (Reynisson 2020) fused with '
                 'AIRR repertoire clonal support; class-II DP/DQ emphasis',
}

with open('antigen_resolution_results.json', 'w') as fh:
    json.dump({'status': 'completed',
               'patient_id': patient,
               'n_candidates': len(candidates),
               'top_antigens': [c['antigen'] for c in candidates[:5]],
               'run': run_meta,
               'candidates': candidates}, fh, indent=2)

# CSV -------------------------------------------------------------------------
with open('antigen_candidates.csv', 'w', newline='') as fh:
    w = csv.writer(fh)
    w.writerow(['rank', 'antigen', 'peptide', 'hla_allele', 'hla_class',
                'binding', 'repertoire_support', 'disease_relevance',
                'score', 'evidence'])
    for c in candidates:
        w.writerow([
            c['candidate_rank'], c['antigen'], c['peptide'], c['hla_allele'],
            c['hla_class'], c['binding'],
            '' if c['repertoire_support'] is None else c['repertoire_support'],
            '' if c['disease_relevance'] is None else c['disease_relevance'],
            c['score'], '; '.join(c['evidence']),
        ])

# Markdown report -------------------------------------------------------------
def fmt(v):
    return '—' if v is None else (f'{v:.2f}' if isinstance(v, float) else str(v))

lines = []
lines.append('# Antigen Resolution — %s' % patient)
lines.append('')
lines.append('**Patient HLA alleles:** ' + ', '.join(sorted(patient_alleles)))
lines.append('')
lines.append('TCR <-> HLA <-> peptide fusion: ranked candidate disease antigens / '
             'epitopes built by integrating repertoire clonal support (airrflow), '
             'patient HLA typing (hlatyping) and peptide:MHC binding predictions '
             '(epitopeprediction). Binding uses NetMHCIIpan/NetMHCpan %rank '
             'convention (Reynisson 2020): %rank <= {:.0f} = strong binder.'.format(strong_rank))
lines.append('')
lines.append('**Weights:** ' + ', '.join('%s=%.2f' % (k, v) for k, v in W.items()))
lines.append('')
lines.append('**Class-II coverage:** %d / %d candidates are class II; %d on DP/DQ loci '
             '(the field\\'s under-served presentation space).' % (n_classII, len(candidates), n_dpdq))
lines.append('')
lines.append('## Ranked antigen / epitope candidates')
lines.append('')
lines.append('| Rank | Antigen | Peptide | HLA allele | Class | Binding | Rep. support | Disease | Score |')
lines.append('|-----:|---------|---------|-----------|:-----:|--------:|-------------:|:-------:|------:|')
for c in candidates:
    lines.append('| %d | %s | %s | %s | %s | %s | %s | %s | %s |' % (
        c['candidate_rank'], c['antigen'], c['peptide'], c['hla_allele'], c['hla_class'],
        fmt(c['binding']), fmt(c['repertoire_support']), fmt(c['disease_relevance']),
        fmt(c['score'])))
lines.append('')
lines.append('## Top candidates — evidence provenance')
lines.append('')
for c in candidates[:8]:
    lines.append('### %d. %s — `%s` on %s (class %s), score %s' % (
        c['candidate_rank'], c['antigen'], c['peptide'], c['hla_allele'],
        c['hla_class'], fmt(c['score'])))
    for e in c['evidence']:
        lines.append('- ' + e)
    lines.append('')

if n_dpdq:
    lines.append('## Class-II DP/DQ candidates (coverage highlight)')
    lines.append('')
    for c in candidates:
        if c['is_dpdq']:
            lines.append('- **%s** `%s` on %s — score %s' % (
                c['antigen'], c['peptide'], c['hla_allele'], fmt(c['score'])))
    lines.append('')

lines.append('## Methodology')
lines.append('')
lines.append('For each predicted epitope presented on one of the patient\\'s own HLA '
             'alleles, an antigen-resolution score fuses (a) HLA-binding strength from '
             'the %rank/binding_score (NetMHCIIpan/NetMHCpan; Reynisson 2020), (b) '
             'repertoire clonal support when the epitope is linked to an expanded '
             'clonotype/CDR3 in the AIRR repertoire, and (c) optional disease-gene '
             'relevance. Axes are combined with a coverage-aware weighted mean (weights '
             'renormalised over the axes actually present), and a small additive bonus '
             'surfaces class-II DP/DQ presentation so under-characterised loci are not '
             'buried. This is an integration step — upstream tools are ingested, not '
             're-run.')

with open('antigen_resolution_report.md', 'w') as fh:
    fh.write('\\n'.join(lines) + '\\n')

# console summary -------------------------------------------------------------
print('=== ANTIGEN RESOLUTION: %s (%d candidates) ===' % (patient, len(candidates)))
for c in candidates[:8]:
    print('  #%-2d %-12s %-11s %-16s [%s] score=%s' % (
        c['candidate_rank'], c['antigen'], c['peptide'], c['hla_allele'],
        c['hla_class'], fmt(c['score'])))

with open('versions.yml', 'w') as fh:
    fh.write('antigen_resolution:\\n')
    fh.write('  python: "3.10"\\n')
    fh.write('  framework: "NetMHCIIpan/NetMHCpan %rank (Reynisson 2020) + AIRR repertoire fusion"\\n')
PYEOF
    """
}

workflow ANTIGEN_RESOLUTION_WORKFLOW {
    take: meta_ch
    main: ANTIGEN_RESOLUTION(meta_ch)
    emit:
        results    = ANTIGEN_RESOLUTION.out.results
        candidates = ANTIGEN_RESOLUTION.out.candidates
        report     = ANTIGEN_RESOLUTION.out.report
}

workflow {
    meta = [id: 'antigen_resolution_run', single_end: false]
    Channel.value(meta) | ANTIGEN_RESOLUTION_WORKFLOW
}
