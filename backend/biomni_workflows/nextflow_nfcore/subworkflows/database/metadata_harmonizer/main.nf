#!/usr/bin/env nextflow
/*
 * database/metadata_harmonizer
 *
 * DETERMINISTIC, ONTOLOGY-GROUNDED metadata / clinical-annotation harmonizer.
 *
 * Maps free-text clinical / sample metadata values onto a controlled
 * vocabulary (an ontology term list) so heterogeneous cohorts can be pooled
 * and queried. Metadata harmonization is the field's unsolved bottleneck:
 * LLM-only mappers generalize poorly to unseen terms (~96% accuracy for
 * in-dictionary terms collapsing to ~17% out-of-dictionary) and, worse,
 * HALLUCINATE ontology IDs that look plausible but do not exist. This
 * workflow therefore NEVER invents a term or an ID. Every mapping is produced
 * by a deterministic string-matching cascade against the supplied ontology,
 * carries an explicit confidence, and is flagged for HUMAN REVIEW whenever the
 * match is weak, ambiguous, or absent.
 *
 * Design principles:
 *   - DETERMINISTIC: pure stdlib string matching (no ML, no network, no LLM).
 *     Same inputs -> byte-identical outputs. Fully auditable.
 *   - ONTOLOGY-GROUNDED: a value can only ever map to an ID that is literally
 *     present in the ontology_file. Out-of-dictionary terms are left UNMAPPED,
 *     never guessed. No hallucinated IDs, ever.
 *   - HUMAN-IN-THE-LOOP: low-confidence, ambiguous (near-tie), and unmapped
 *     values are flagged needs_review=true for human curation. The machine
 *     proposes; a curator disposes.
 *
 * Match cascade (first tier that fires wins; confidence from tier + score):
 *   1. exact          normalized-equality of value vs term_label
 *   2. synonym_exact  normalized-equality of value vs any listed synonym
 *   3. token_set      Jaccard overlap of normalized token sets (word reorder /
 *                     partial phrase); accepted above a token threshold
 *   4. fuzzy          character n-gram / edit-distance (difflib) similarity;
 *                     accepted above a fuzzy threshold, always flagged review
 * Ambiguity: if the top and runner-up candidates are within a small margin the
 * mapping is retained but flagged needs_review (a human must disambiguate).
 *
 * Input:  metadata_file (REQUIRED CSV) — either long form (columns field,value)
 *         or a wide table whose cell values are the free-text terms to map.
 *         ontology_file (REQUIRED CSV) — controlled vocabulary with columns
 *         term_id, term_label and optional synonyms (|- or ;-delimited).
 *         Neither file is optional; NO synthetic fallback is generated.
 * Output: harmonized_metadata.csv, harmonization_results.json,
 *         harmonization_report.md, versions.yml
 */

nextflow.enable.dsl = 2

params.outdir        = './results'
params.metadata_file = 'NONE'          // REQUIRED path to real free-text metadata CSV
params.ontology_file = 'NONE'          // REQUIRED path to controlled-vocabulary CSV

// -- Acceptance / review thresholds (all deterministic) -----------------------
params.review_threshold = '0.85'       // confidence below this => needs_review
params.token_threshold  = '0.50'       // min Jaccard to accept a token_set match
params.fuzzy_threshold   = '0.80'      // min difflib ratio to accept a fuzzy match
params.ambiguity_margin  = '0.05'      // top vs runner-up gap below this => ambiguous

process METADATA_HARMONIZER {
    tag "$meta.id"
    label 'process_low'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("harmonization_results.json"), emit: results
    tuple val(meta), path("harmonized_metadata.csv"),    emit: harmonized
    tuple val(meta), path("harmonization_report.md"),    emit: report
    path "versions.yml",                                 emit: versions

    script:
    """
    export PARAM_METADATA='${params.metadata_file}'
    export PARAM_ONTOLOGY='${params.ontology_file}'
    export PARAM_REVIEW_THRESH='${params.review_threshold}'
    export PARAM_TOKEN_THRESH='${params.token_threshold}'
    export PARAM_FUZZY_THRESH='${params.fuzzy_threshold}'
    export PARAM_AMBIG_MARGIN='${params.ambiguity_margin}'

    python3 << 'PYEOF'
import json, os, csv, sys, re, difflib

# ------------------------------------------------------------------ helpers ---
def _f(v, default):
    # parse a float param, falling back to default on any bad input
    try:
        return float(v)
    except Exception:
        return default

def normalize(s):
    # lowercase, strip punctuation to spaces, collapse whitespace
    if s is None:
        return ''
    s = str(s).lower().strip()
    s = re.sub(r"[^a-z0-9]+", " ", s)
    return re.sub(r"\\s+", " ", s).strip()

def tokens(s):
    # normalized token set (order-independent)
    return set(t for t in normalize(s).split(" ") if t)

def jaccard(a, b):
    # hand-rolled Jaccard over two token sets
    if not a or not b:
        return 0.0
    inter = len(a & b)
    union = len(a | b)
    return inter / union if union else 0.0

def fuzzy_ratio(a, b):
    # character-level edit-distance similarity via stdlib difflib
    return difflib.SequenceMatcher(None, normalize(a), normalize(b)).ratio()

def split_synonyms(raw):
    # synonyms may be | ; or , delimited; return list of raw synonym strings
    if not raw:
        return []
    parts = re.split(r"[|;]", str(raw))
    if len(parts) == 1:
        parts = str(raw).split(",")
    return [p.strip() for p in parts if p.strip()]

# ------------------------------------------------------------------- params ---
review_thresh = _f(os.environ.get('PARAM_REVIEW_THRESH'), 0.85)
token_thresh  = _f(os.environ.get('PARAM_TOKEN_THRESH'), 0.50)
fuzzy_thresh  = _f(os.environ.get('PARAM_FUZZY_THRESH'), 0.80)
ambig_margin  = _f(os.environ.get('PARAM_AMBIG_MARGIN'), 0.05)

metadata_path = os.environ.get('PARAM_METADATA', 'NONE')
ontology_path = os.environ.get('PARAM_ONTOLOGY', 'NONE')

# --------------------------------------------------- fail-fast: real files only
def _missing(path):
    return (not path) or path in ('NONE', '') or not os.path.exists(path)

def _fail(msg):
    # write headered-empty CSV + failed-status JSON, then exit(1). No fallback.
    sys.stderr.write("ERROR: " + msg + "\\n")
    with open('harmonized_metadata.csv', 'w', newline='') as fh:
        csv.writer(fh).writerow(
            ['original_value', 'mapped_term_id', 'mapped_term_label',
             'confidence', 'match_method', 'needs_review'])
    with open('harmonization_results.json', 'w') as fh:
        json.dump({'status': 'failed', 'error': msg,
                   'mappings': [], 'coverage': {}}, fh, indent=2)
    with open('harmonization_report.md', 'w') as fh:
        fh.write("# Metadata Harmonization — FAILED\\n\\n" + msg + "\\n")
    with open('versions.yml', 'w') as fh:
        fh.write('metadata_harmonizer:\\n  python: "3.10"\\n  status: "failed"\\n')
    sys.exit(1)

if _missing(metadata_path):
    _fail("--metadata_file is required and must point to a real free-text "
          "metadata CSV. No synthetic data is generated. got=%r" % metadata_path)
if _missing(ontology_path):
    _fail("--ontology_file is required and must point to a real controlled-"
          "vocabulary CSV (term_id, term_label[, synonyms]). No synthetic data "
          "is generated. got=%r" % ontology_path)

# -------------------------------------------------------------- load ontology
# Each ontology entry: {id, label, synonyms:[...], and precomputed norm forms}
ontology = []
with open(ontology_path, newline='') as fh:
    rdr = csv.DictReader(fh)
    if not rdr.fieldnames:
        _fail("ontology_file has no header row")
    # tolerant column resolution
    cols = {c.lower().strip(): c for c in rdr.fieldnames}
    id_col  = cols.get('term_id') or cols.get('id') or cols.get('ontology_id')
    lab_col = cols.get('term_label') or cols.get('label') or cols.get('name')
    syn_col = cols.get('synonyms') or cols.get('synonym') or cols.get('aliases')
    if not id_col or not lab_col:
        _fail("ontology_file must contain term_id and term_label columns "
              "(found: %r)" % rdr.fieldnames)
    for r in rdr:
        tid = (r.get(id_col) or '').strip()
        lab = (r.get(lab_col) or '').strip()
        if not tid or not lab:
            continue
        syns = split_synonyms(r.get(syn_col)) if syn_col else []
        ontology.append({
            'id': tid,
            'label': lab,
            'synonyms': syns,
            'norm_label': normalize(lab),
            'norm_syns': [normalize(s) for s in syns],
            'label_tokens': tokens(lab),
            'syn_tokens': [tokens(s) for s in syns],
        })

if not ontology:
    _fail("ontology_file contained no usable term_id/term_label rows")

# exact-lookup index: normalized string -> ontology entry (labels + synonyms)
exact_index = {}
synonym_index = {}
for ent in ontology:
    exact_index.setdefault(ent['norm_label'], ent)
    for ns in ent['norm_syns']:
        synonym_index.setdefault(ns, ent)

# -------------------------------------------------------------- load metadata
# Detect long form (columns include value / term, optionally field) vs wide.
# For wide tables, every non-empty cell (excluding the header) is a value to
# harmonize; we record its column as the 'field' for provenance.
values = []   # list of (field, original_value)
with open(metadata_path, newline='') as fh:
    rdr = csv.reader(fh)
    all_rows = [row for row in rdr if any((c or '').strip() for c in row)]
if not all_rows:
    _fail("metadata_file is empty")

header = [h.strip() for h in all_rows[0]]
header_lower = [h.lower() for h in header]
is_long = ('value' in header_lower or 'term' in header_lower)

if is_long:
    val_idx = header_lower.index('value') if 'value' in header_lower else header_lower.index('term')
    fld_idx = header_lower.index('field') if 'field' in header_lower else None
    for row in all_rows[1:]:
        if val_idx >= len(row):
            continue
        v = (row[val_idx] or '').strip()
        if not v:
            continue
        f = (row[fld_idx].strip() if (fld_idx is not None and fld_idx < len(row)) else '')
        values.append((f, v))
else:
    # wide: harmonize every cell value under its column header
    for row in all_rows[1:]:
        for ci, cell in enumerate(row):
            v = (cell or '').strip()
            if not v:
                continue
            f = header[ci] if ci < len(header) else ''
            values.append((f, v))

if not values:
    _fail("metadata_file contained no free-text values to harmonize")

# --------------------------------------------------- deterministic match cascade
def best_fuzzy_candidates(value):
    # score value against every label + synonym; return sorted (score, ent, via)
    nv = normalize(value)
    vt = tokens(value)
    cands = []
    for ent in ontology:
        # token-set (Jaccard) best over label + synonyms
        j = jaccard(vt, ent['label_tokens'])
        for st in ent['syn_tokens']:
            j = max(j, jaccard(vt, st))
        # character fuzzy best over label + synonyms
        fz = difflib.SequenceMatcher(None, nv, ent['norm_label']).ratio()
        for ns in ent['norm_syns']:
            fz = max(fz, difflib.SequenceMatcher(None, nv, ns).ratio())
        cands.append({'ent': ent, 'jaccard': round(j, 4), 'fuzzy': round(fz, 4)})
    return cands

def harmonize_value(value):
    # returns a mapping dict; NEVER fabricates an id — unmapped => id is ''
    nv = normalize(value)

    # tier 1: exact label
    if nv in exact_index:
        ent = exact_index[nv]
        return _mk(value, ent, 1.0, 'exact', needs_review=False,
                   detail='normalized exact label match')

    # tier 2: synonym exact
    if nv in synonym_index:
        ent = synonym_index[nv]
        return _mk(value, ent, 0.97, 'synonym_exact', needs_review=(0.97 < review_thresh),
                   detail='normalized exact synonym match')

    # tiers 3 & 4: fuzzy — compute all candidates once, rank
    cands = best_fuzzy_candidates(value)

    # token_set tier: rank by Jaccard
    by_tok = sorted(cands, key=lambda c: c['jaccard'], reverse=True)
    top_tok = by_tok[0]
    tok_runner = by_tok[1]['jaccard'] if len(by_tok) > 1 else 0.0
    if top_tok['jaccard'] >= token_thresh:
        conf = round(0.60 + 0.30 * top_tok['jaccard'], 4)   # 0.60..0.90 band
        ambiguous = (top_tok['jaccard'] - tok_runner) < ambig_margin and tok_runner > 0
        nr = (conf < review_thresh) or ambiguous
        return _mk(value, top_tok['ent'], conf, 'token_set', needs_review=nr,
                   detail='Jaccard=%.2f%s' % (top_tok['jaccard'],
                          ' (AMBIGUOUS near-tie)' if ambiguous else ''),
                   ambiguous=ambiguous)

    # fuzzy tier: rank by character similarity
    by_fz = sorted(cands, key=lambda c: c['fuzzy'], reverse=True)
    top_fz = by_fz[0]
    fz_runner = by_fz[1]['fuzzy'] if len(by_fz) > 1 else 0.0
    if top_fz['fuzzy'] >= fuzzy_thresh:
        conf = round(0.40 + 0.40 * top_fz['fuzzy'], 4)      # 0.40..0.80 band
        ambiguous = (top_fz['fuzzy'] - fz_runner) < ambig_margin and fz_runner > 0
        # fuzzy matches ALWAYS need review (below review_thresh by construction)
        return _mk(value, top_fz['ent'], conf, 'fuzzy', needs_review=True,
                   detail='difflib=%.2f%s' % (top_fz['fuzzy'],
                          ' (AMBIGUOUS near-tie)' if ambiguous else ''),
                   ambiguous=ambiguous)

    # out-of-dictionary: NEVER guess an id. Flag for human curation.
    return {
        'original_value': value, 'mapped_term_id': '', 'mapped_term_label': '',
        'confidence': 0.0, 'match_method': 'unmapped', 'needs_review': True,
        'ambiguous': False,
        'detail': 'no ontology term above thresholds — OUT OF DICTIONARY, '
                  'requires human curation (no ID invented)',
        'best_candidate_id': by_fz[0]['ent']['id'] if by_fz else '',
        'best_candidate_label': by_fz[0]['ent']['label'] if by_fz else '',
        'best_candidate_score': by_fz[0]['fuzzy'] if by_fz else 0.0,
    }

def _mk(value, ent, conf, method, needs_review, detail, ambiguous=False):
    return {
        'original_value': value,
        'mapped_term_id': ent['id'],
        'mapped_term_label': ent['label'],
        'confidence': round(conf, 4),
        'match_method': method,
        'needs_review': bool(needs_review),
        'ambiguous': bool(ambiguous),
        'detail': detail,
    }

# ---------------------------------------------------------------- run all values
# de-duplicate identical (field,value) but keep count for reporting
seen = {}
mappings = []
for field, value in values:
    key = (field, value)
    if key in seen:
        seen[key]['occurrences'] += 1
        continue
    m = harmonize_value(value)
    m['field'] = field
    m['occurrences'] = 1
    seen[key] = m
    mappings.append(m)

# ------------------------------------------------------------------- coverage
n = len(mappings)
n_high   = sum(1 for m in mappings if m['confidence'] >= review_thresh and m['mapped_term_id'])
n_review = sum(1 for m in mappings if m['needs_review'] and m['mapped_term_id'])
n_unmapped = sum(1 for m in mappings if not m['mapped_term_id'])
def pct(x):
    return round(100.0 * x / n, 1) if n else 0.0
coverage = {
    'n_values': n,
    'n_auto_high_confidence': n_high,
    'n_needs_review_mapped': n_review,
    'n_unmapped': n_unmapped,
    'pct_auto_high_confidence': pct(n_high),
    'pct_needs_review': pct(sum(1 for m in mappings if m['needs_review'])),
    'pct_unmapped': pct(n_unmapped),
    'review_threshold': review_thresh,
}

# ------------------------------------------------------------------- outputs
with open('harmonized_metadata.csv', 'w', newline='') as fh:
    w = csv.writer(fh)
    w.writerow(['original_value', 'mapped_term_id', 'mapped_term_label',
                'confidence', 'match_method', 'needs_review'])
    for m in mappings:
        w.writerow([m['original_value'], m['mapped_term_id'], m['mapped_term_label'],
                    m['confidence'], m['match_method'],
                    'true' if m['needs_review'] else 'false'])

run_meta = {
    'metadata_source': os.path.basename(metadata_path),
    'ontology_source': os.path.basename(ontology_path),
    'ontology_terms': len(ontology),
    'input_format': 'long' if is_long else 'wide',
    'thresholds': {
        'review_threshold': review_thresh,
        'token_threshold': token_thresh,
        'fuzzy_threshold': fuzzy_thresh,
        'ambiguity_margin': ambig_margin,
    },
    'method': 'deterministic string-match cascade (exact -> synonym_exact -> '
              'token_set Jaccard -> fuzzy difflib); ontology-grounded; '
              'no LLM, no network, no ID invention',
}

with open('harmonization_results.json', 'w') as fh:
    json.dump({'status': 'completed', 'run': run_meta,
               'coverage': coverage, 'mappings': mappings}, fh, indent=2)

# ------------------------------------------------------------------- report
def fmt(v):
    return '%.2f' % v if isinstance(v, float) else str(v)

lines = []
lines.append('# Metadata Harmonization Report')
lines.append('')
lines.append('**Metadata source:** `%s`  |  **Ontology:** `%s` (%d terms)'
             % (run_meta['metadata_source'], run_meta['ontology_source'], len(ontology)))
lines.append('')
lines.append('Free-text metadata values mapped to a controlled vocabulary using a '
             '**deterministic** string-match cascade (exact -> synonym -> token-set '
             'Jaccard -> character fuzzy). No machine learning, no LLM, no network '
             'lookup, and **no ontology IDs were invented**: a value can only map to '
             'an ID literally present in the ontology file.')
lines.append('')
lines.append('> **Human curation required.** Rows flagged `needs_review` (fuzzy, '
             'ambiguous near-ties, or below the confidence threshold) and all '
             '`unmapped` (out-of-dictionary) rows are proposals only and MUST be '
             'reviewed by a curator before use. Unmapped values were left blank — '
             'never guessed.')
lines.append('')
lines.append('## Coverage')
lines.append('')
lines.append('| Metric | Count | %% |')
lines.append('|--------|------:|---:|')
lines.append('| Values harmonized (unique) | %d | 100.0 |' % coverage['n_values'])
lines.append('| Auto-mapped, high confidence | %d | %.1f |'
             % (coverage['n_auto_high_confidence'], coverage['pct_auto_high_confidence']))
lines.append('| Needs human review | %d | %.1f |'
             % (sum(1 for m in mappings if m['needs_review']), coverage['pct_needs_review']))
lines.append('| Unmapped (out-of-dictionary) | %d | %.1f |'
             % (coverage['n_unmapped'], coverage['pct_unmapped']))
lines.append('')
lines.append('## All mappings')
lines.append('')
lines.append('| Value | Term ID | Term label | Conf | Method | Review |')
lines.append('|-------|---------|------------|-----:|--------|:------:|')
for m in mappings:
    lines.append('| %s | %s | %s | %.2f | %s | %s |'
                 % (m['original_value'], m['mapped_term_id'] or '—',
                    m['mapped_term_label'] or '—', m['confidence'],
                    m['match_method'], '⚠️' if m['needs_review'] else '✓'))
lines.append('')

review_rows = [m for m in mappings if m['needs_review'] and m['mapped_term_id']]
if review_rows:
    lines.append('## ⚠ Flagged for human review (proposed mapping — verify)')
    lines.append('')
    for m in review_rows:
        lines.append('- **%s** -> `%s` (%s) [%s, conf %.2f] — %s'
                     % (m['original_value'], m['mapped_term_id'],
                        m['mapped_term_label'], m['match_method'],
                        m['confidence'], m['detail']))
    lines.append('')

unmapped_rows = [m for m in mappings if not m['mapped_term_id']]
if unmapped_rows:
    lines.append('## ⚠ Unmapped — out of dictionary (NO ID invented)')
    lines.append('')
    lines.append('These values had no acceptable ontology match. They were left '
                 'blank rather than guessed, and require a curator to either add a '
                 'new ontology term or supply the correct mapping.')
    lines.append('')
    for m in unmapped_rows:
        hint = ''
        if m.get('best_candidate_id'):
            hint = (' (nearest non-accepted candidate: `%s` %s, score %.2f — '
                    'below threshold, NOT applied)'
                    % (m['best_candidate_id'], m['best_candidate_label'],
                       m.get('best_candidate_score', 0.0)))
        lines.append('- **%s**%s' % (m['original_value'], hint))
    lines.append('')

lines.append('## Methodology')
lines.append('')
lines.append('For each free-text value the value and every ontology label/synonym '
             'are normalized (lowercase, punctuation stripped, whitespace collapsed). '
             'The cascade returns the first tier that fires: (1) exact label equality '
             '(conf 1.00); (2) exact synonym equality (conf 0.97); (3) token-set '
             'Jaccard overlap >= %.2f (conf 0.60–0.90); (4) character edit-distance '
             'similarity (difflib) >= %.2f (conf 0.40–0.80, always flagged for review). '
             'Near-ties within a %.2f margin are flagged ambiguous. Values with no '
             'tier above threshold are reported unmapped with an empty ID. This is '
             'fully deterministic and auditable; it is designed to complement, not '
             'replace, expert curation.'
             % (token_thresh, fuzzy_thresh, ambig_margin))

with open('harmonization_report.md', 'w') as fh:
    fh.write('\\n'.join(lines) + '\\n')

# ------------------------------------------------------------------- console
print('=== METADATA HARMONIZATION (%d unique values) ===' % n)
print('  auto high-confidence: %d (%.1f%%)' % (n_high, coverage['pct_auto_high_confidence']))
print('  needs review:         %d (%.1f%%)' % (sum(1 for m in mappings if m['needs_review']),
                                               coverage['pct_needs_review']))
print('  unmapped:             %d (%.1f%%)' % (n_unmapped, coverage['pct_unmapped']))

with open('versions.yml', 'w') as fh:
    fh.write('metadata_harmonizer:\\n')
    fh.write('  python: "3.10"\\n')
    fh.write('  method: "deterministic ontology-grounded string-match cascade (stdlib only)"\\n')
PYEOF
    """
}

workflow METADATA_HARMONIZER_WORKFLOW {
    take: meta_ch
    main: METADATA_HARMONIZER(meta_ch)
    emit:
        results    = METADATA_HARMONIZER.out.results
        harmonized = METADATA_HARMONIZER.out.harmonized
        report     = METADATA_HARMONIZER.out.report
}

workflow {
    meta = [id: 'harmonizer_run', single_end: false]
    Channel.value(meta) | METADATA_HARMONIZER_WORKFLOW
}
