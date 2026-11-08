#!/usr/bin/env nextflow
/*
 * biostatistics/cohort_qc_triage
 *
 * THE HARMONIZATION QC-TRIAGE GATE.
 *
 * Given a cohort's sample metadata (and optional per-sample omics QC metrics),
 * decide whether the dataset is good enough to INTEGRATE into a harmonized,
 * multi-cohort analysis — or whether it must be TRIAGED (fixable) or REJECTED
 * (un-integratable). This is the survey-identified gate that must run BEFORE
 * any cross-cohort harmonization / batch-correction step: integrating a
 * dataset whose batch is confounded with the biological outcome bakes an
 * uncorrectable artifact into every downstream result.
 *
 * Checks performed:
 *   1. METADATA COMPLETENESS — fraction of required fields present and populated
 *      (default: batch, group, sex, age, timepoint, platform). Missing fields
 *      are itemized.
 *   2. BATCH<->BIOLOGY CONFOUNDING (the single most important check) — is the
 *      technical `batch` variable statistically confounded with the biological
 *      `group`/outcome? Measured with a chi-square test of independence on the
 *      batch x group contingency table and Cramer's V effect size. Near-perfect
 *      confounding (each batch maps to one group) => the batch effect and the
 *      biological effect are mathematically inseparable => REJECT.
 *   3. PROVENANCE COMPLETENESS — BRISQ (Moore 2011) / MIxS (Yilmaz 2011) style
 *      fields present (collection, storage, platform, protocol)?
 *   4. QC-METRIC FLAGS (optional metrics table) — per-sample outliers on
 *      pct_mito, n_genes, and library_size using a robust MAD rule.
 *
 * Verdict per dataset:
 *   INTEGRATE  — complete enough and batch is NOT confounded with biology.
 *   TRIAGE     — fixable problems (missing fields / provenance / QC outliers);
 *                lists exactly what to fix.
 *   REJECT     — batch confounded with biology, or metadata too incomplete to
 *                harmonize.
 *
 * Statistics are hand-rolled with the Python stdlib only (math, csv, json) so
 * the module has NO third-party dependency and is fully auditable.
 *
 * References: BRISQ minimum biospecimen reporting (Moore et al. 2011); MIxS
 * minimum information about any (x) sequence (Yilmaz et al. 2011);
 * batch-effect confounding & correction (Leek et al. Nat Rev Genet 2010).
 *
 * Input:  metadata_file (REQUIRED CSV: sample_id, batch, group, ...), optional
 *         qc_metrics_file. If metadata_file is absent/unreadable the workflow
 *         writes a failed-status JSON + headered empty CSV and exits(1). No
 *         synthetic data is ever generated.
 * Output: qc_triage_results.json, qc_triage_report.md, sample_qc_flags.csv,
 *         versions.yml
 */

nextflow.enable.dsl = 2

params.outdir          = './results'
params.metadata_file   = 'NONE'    // REQUIRED CSV: sample_id, batch, group, sex, age, timepoint, platform, ...
params.qc_metrics_file  = 'NONE'   // optional CSV: sample_id, pct_mito, n_genes, library_size
params.dataset_id       = 'cohort'

// Required metadata fields (comma-separated). Completeness is scored over these.
params.required_fields  = 'batch,group,sex,age,timepoint,platform'
// Provenance (BRISQ / MIxS) fields checked for harmonization traceability.
params.provenance_fields = 'collection_date,storage,platform,protocol'
// Column names for the two confounding variables.
params.batch_field       = 'batch'
params.group_field       = 'group'

// -- Thresholds ---------------------------------------------------------------
// Metadata completeness below this => contributes to REJECT.
params.min_completeness  = '0.60'
// Cramer's V at/above this (with significant chi-square) => confounded => REJECT.
params.confound_v_reject = '0.80'
// Cramer's V at/above this => partial confounding => TRIAGE warning.
params.confound_v_warn   = '0.50'
// chi-square p-value below this is "significant" association.
params.confound_alpha    = '0.05'
// MAD multiplier for per-sample QC-metric outlier flags.
params.mad_k             = '3.5'

process COHORT_QC_TRIAGE {
    tag "$meta.id"
    label 'process_low'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/workflow-tools:x86' : 'biomate/workflow-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("qc_triage_results.json"), emit: results
    tuple val(meta), path("qc_triage_report.md"),    emit: report
    tuple val(meta), path("sample_qc_flags.csv"),    emit: flags
    path "versions.yml",                             emit: versions

    script:
    """
    export PARAM_METADATA='${params.metadata_file}'
    export PARAM_QC_METRICS='${params.qc_metrics_file}'
    export PARAM_DATASET_ID='${params.dataset_id.toString().replace("'", "'\\''")}'
    export PARAM_REQUIRED='${params.required_fields.toString().replace("'", "'\\''")}'
    export PARAM_PROVENANCE='${params.provenance_fields.toString().replace("'", "'\\''")}'
    export PARAM_BATCH_FIELD='${params.batch_field.toString().replace("'", "'\\''")}'
    export PARAM_GROUP_FIELD='${params.group_field.toString().replace("'", "'\\''")}'
    export PARAM_MIN_COMPLETENESS='${params.min_completeness}'
    export PARAM_V_REJECT='${params.confound_v_reject}'
    export PARAM_V_WARN='${params.confound_v_warn}'
    export PARAM_ALPHA='${params.confound_alpha}'
    export PARAM_MAD_K='${params.mad_k}'

    python3 << 'PYEOF'
import os, csv, json, math, sys

# ------------------------------------------------------------------ helpers ---
def _f(v, default=None):
    if v in (None, '', 'null', 'None', 'NA', 'nan', 'NaN'):
        return default
    try:
        return float(v)
    except Exception:
        return default

def _present(v):
    # A cell "counts" as present only if it is non-empty and not a null token.
    if v is None:
        return False
    s = str(v).strip()
    return s != '' and s.lower() not in ('na', 'n/a', 'null', 'none', 'nan', 'unknown', '.')

def _split(env, default_list):
    raw = os.environ.get(env, '') or ''
    parts = [p.strip() for p in raw.split(',') if p.strip()]
    return parts if parts else list(default_list)

# ------------------------------------------------------------------- params ---
dataset_id  = os.environ.get('PARAM_DATASET_ID', 'cohort') or 'cohort'
required    = _split('PARAM_REQUIRED', ['batch', 'group', 'sex', 'age', 'timepoint', 'platform'])
provenance  = _split('PARAM_PROVENANCE', ['collection_date', 'storage', 'platform', 'protocol'])
batch_field = os.environ.get('PARAM_BATCH_FIELD', 'batch') or 'batch'
group_field = os.environ.get('PARAM_GROUP_FIELD', 'group') or 'group'
min_complete = _f(os.environ.get('PARAM_MIN_COMPLETENESS'), 0.60)
v_reject    = _f(os.environ.get('PARAM_V_REJECT'), 0.80)
v_warn      = _f(os.environ.get('PARAM_V_WARN'), 0.50)
alpha       = _f(os.environ.get('PARAM_ALPHA'), 0.05)
mad_k       = _f(os.environ.get('PARAM_MAD_K'), 3.5)

# -------------------------------------------------- load metadata (real only) -
meta_path = os.environ.get('PARAM_METADATA', 'NONE')
if (not meta_path) or meta_path in ('NONE', '') or not os.path.exists(meta_path):
    sys.stderr.write(
        "ERROR: --metadata_file is required and must point to a real cohort "
        "sample-metadata CSV (columns: sample_id, batch, group, ...). "
        "No synthetic data is generated.\\n")
    with open('qc_triage_results.json', 'w') as fh:
        json.dump({'status': 'failed',
                   'error': 'metadata_file missing or not found: %r' % meta_path,
                   'dataset_id': dataset_id, 'verdict': None, 'checks': {}}, fh, indent=2)
    with open('sample_qc_flags.csv', 'w', newline='') as fh:
        csv.writer(fh).writerow(['sample_id', 'batch', 'group', 'flags'])
    with open('qc_triage_report.md', 'w') as fh:
        fh.write('# Cohort QC Triage — FAILED\\n\\nmetadata_file missing or unreadable.\\n')
    with open('versions.yml', 'w') as fh:
        fh.write('cohort_qc_triage:\\n  python: "3.10"\\n  status: "failed"\\n')
    sys.exit(1)

try:
    with open(meta_path, newline='') as fh:
        rdr = csv.DictReader(fh)
        headers = [h.strip() for h in (rdr.fieldnames or [])]
        rows = []
        for r in rdr:
            rows.append({(k.strip() if k else k): (v.strip() if isinstance(v, str) else v)
                         for k, v in r.items()})
except Exception as e:
    sys.stderr.write("ERROR: could not parse metadata_file: %s\\n" % e)
    with open('qc_triage_results.json', 'w') as fh:
        json.dump({'status': 'failed', 'error': 'unparseable metadata_file: %s' % e,
                   'dataset_id': dataset_id, 'verdict': None, 'checks': {}}, fh, indent=2)
    with open('sample_qc_flags.csv', 'w', newline='') as fh:
        csv.writer(fh).writerow(['sample_id', 'batch', 'group', 'flags'])
    with open('qc_triage_report.md', 'w') as fh:
        fh.write('# Cohort QC Triage — FAILED\\n\\nmetadata_file unparseable.\\n')
    with open('versions.yml', 'w') as fh:
        fh.write('cohort_qc_triage:\\n  python: "3.10"\\n  status: "failed"\\n')
    sys.exit(1)

n_samples = len(rows)
header_set = set(headers)

def sample_id_of(r, i):
    for key in ('sample_id', 'sample', 'id', 'sampleid', 'Sample_ID', 'Sample'):
        if key in r and _present(r.get(key)):
            return str(r.get(key)).strip()
    return 'sample_%d' % (i + 1)

# ============================================================ CHECK 1: completeness
# Fraction of required fields that are (a) present as a column AND (b) populated
# in a strong majority of samples. A column present but 90% blank is NOT complete.
completeness_detail = {}
present_fields = 0
missing_fields = []
partial_fields = []
for field in required:
    if field not in header_set:
        completeness_detail[field] = {'column_present': False, 'fill_rate': 0.0}
        missing_fields.append(field)
        continue
    filled = sum(1 for r in rows if _present(r.get(field)))
    fill_rate = (filled / n_samples) if n_samples else 0.0
    completeness_detail[field] = {'column_present': True, 'fill_rate': round(fill_rate, 4)}
    if fill_rate >= 0.90:
        present_fields += 1
    elif fill_rate > 0.0:
        partial_fields.append(field)
    else:
        missing_fields.append(field)

completeness = (present_fields / len(required)) if required else 1.0

# ============================================================ CHECK 3: provenance
provenance_detail = {}
provenance_missing = []
prov_present = 0
for field in provenance:
    if field not in header_set:
        provenance_detail[field] = {'column_present': False, 'fill_rate': 0.0}
        provenance_missing.append(field)
        continue
    filled = sum(1 for r in rows if _present(r.get(field)))
    fill_rate = (filled / n_samples) if n_samples else 0.0
    provenance_detail[field] = {'column_present': True, 'fill_rate': round(fill_rate, 4)}
    if fill_rate >= 0.90:
        prov_present += 1
    else:
        provenance_missing.append(field)
provenance_completeness = (prov_present / len(provenance)) if provenance else 1.0

# ================================================ CHECK 2: batch<->biology confounding
# Build the batch x group contingency table over samples that have BOTH values,
# then chi-square test of independence + Cramer's V effect size. Hand-rolled:
#   chi2 = sum((O-E)^2 / E);  E_ij = row_i * col_j / N
#   Cramer's V = sqrt(chi2 / (N * (min(r,c) - 1)))
#   p-value via a regularized-lower-incomplete-gamma chi-square survival function.

def _lower_incomplete_gamma_reg(s, x):
    # Regularized lower incomplete gamma P(s, x) via series expansion (x < s+1)
    # and continued fraction (x >= s+1). Good to ~1e-10 for our df range.
    if x <= 0:
        return 0.0
    gln = math.lgamma(s)
    if x < s + 1.0:
        ap = s
        total = 1.0 / s
        term = total
        for _ in range(500):
            ap += 1.0
            term *= x / ap
            total += term
            if abs(term) < abs(total) * 1e-12:
                break
        return total * math.exp(-x + s * math.log(x) - gln)
    # continued fraction for Q, then P = 1 - Q
    tiny = 1e-30
    b = x + 1.0 - s
    c = 1.0 / tiny
    d = 1.0 / b
    h = d
    for i in range(1, 500):
        an = -i * (i - s)
        b += 2.0
        d = an * d + b
        if abs(d) < tiny:
            d = tiny
        c = b + an / c
        if abs(c) < tiny:
            c = tiny
        d = 1.0 / d
        delta = d * c
        h *= delta
        if abs(delta - 1.0) < 1e-12:
            break
    q = math.exp(-x + s * math.log(x) - gln) * h
    return 1.0 - q

def chi2_sf(chi2, df):
    # survival function P(X > chi2) = 1 - regularized_lower_gamma(df/2, chi2/2)
    if df <= 0 or chi2 <= 0:
        return 1.0
    return max(0.0, 1.0 - _lower_incomplete_gamma_reg(df / 2.0, chi2 / 2.0))

have_batch = batch_field in header_set
have_group = group_field in header_set
confound = {
    'batch_field': batch_field, 'group_field': group_field,
    'computable': False, 'reason': None,
    'n_batches': 0, 'n_groups': 0, 'n_used': 0,
    'chi2': None, 'df': None, 'p_value': None, 'cramers_v': None,
    'confounded': False, 'partial': False,
}
if not have_batch or not have_group:
    confound['reason'] = 'missing %s column' % (
        batch_field if not have_batch else group_field)
else:
    pairs = [(str(r.get(batch_field)).strip(), str(r.get(group_field)).strip())
             for r in rows if _present(r.get(batch_field)) and _present(r.get(group_field))]
    batches = sorted({b for b, _ in pairs})
    groups = sorted({g for _, g in pairs})
    confound['n_batches'] = len(batches)
    confound['n_groups'] = len(groups)
    confound['n_used'] = len(pairs)
    if len(batches) < 2 or len(groups) < 2:
        confound['reason'] = ('only one batch — nothing to confound' if len(batches) < 2
                              else 'only one group — nothing to confound')
    else:
        bi = {b: i for i, b in enumerate(batches)}
        gi = {g: j for j, g in enumerate(groups)}
        table = [[0] * len(groups) for _ in batches]
        for b, g in pairs:
            table[bi[b]][gi[g]] += 1
        N = len(pairs)
        row_tot = [sum(row) for row in table]
        col_tot = [sum(table[i][j] for i in range(len(batches))) for j in range(len(groups))]
        chi2 = 0.0
        for i in range(len(batches)):
            for j in range(len(groups)):
                exp = row_tot[i] * col_tot[j] / N if N else 0.0
                if exp > 0:
                    chi2 += (table[i][j] - exp) ** 2 / exp
        df = (len(batches) - 1) * (len(groups) - 1)
        p = chi2_sf(chi2, df)
        k = min(len(batches), len(groups))
        cv = math.sqrt(chi2 / (N * (k - 1))) if (N > 0 and k > 1) else 0.0
        cv = min(1.0, cv)
        confound.update({
            'computable': True, 'chi2': round(chi2, 4), 'df': df,
            'p_value': round(p, 6), 'cramers_v': round(cv, 4),
            'contingency': {b: {g: table[bi[b]][gi[g]] for g in groups} for b in batches},
        })
        significant = (p is not None and p < alpha)
        confound['confounded'] = bool(significant and cv >= v_reject)
        confound['partial'] = bool(significant and (v_warn <= cv < v_reject))

# ================================================ CHECK 4: per-sample QC-metric flags
qc_path = os.environ.get('PARAM_QC_METRICS', 'NONE')
qc_metric_cols = ['pct_mito', 'n_genes', 'library_size']
sample_flags = {}   # sample_id -> list[str]
qc_summary = {'metrics_provided': False, 'n_outlier_samples': 0, 'metrics': {}}

def _median(xs):
    s = sorted(xs)
    n = len(s)
    if n == 0:
        return None
    mid = n // 2
    return s[mid] if n % 2 else (s[mid - 1] + s[mid]) / 2.0

if qc_path and qc_path not in ('NONE', '') and os.path.exists(qc_path):
    qc_summary['metrics_provided'] = True
    with open(qc_path, newline='') as fh:
        qc_rows = list(csv.DictReader(fh))
    qc_headers = set((qc_rows[0].keys()) if qc_rows else [])
    for col in qc_metric_cols:
        if col not in qc_headers:
            continue
        vals = []
        for r in qc_rows:
            v = _f(r.get(col))
            if v is not None:
                vals.append(v)
        if len(vals) < 3:
            continue
        med = _median(vals)
        abs_dev = [abs(v - med) for v in vals]
        mad = _median(abs_dev) or 0.0
        # 1.4826 scales MAD to a normal-consistent sigma estimate
        sigma = 1.4826 * mad if mad > 0 else 0.0
        lo = med - mad_k * sigma if sigma > 0 else None
        hi = med + mad_k * sigma if sigma > 0 else None
        n_out = 0
        for i, r in enumerate(qc_rows):
            v = _f(r.get(col))
            if v is None:
                continue
            sid = None
            for key in ('sample_id', 'sample', 'id'):
                if _present(r.get(key)):
                    sid = str(r.get(key)).strip()
                    break
            if sid is None:
                sid = 'qc_row_%d' % (i + 1)
            if sigma > 0 and (v < lo or v > hi):
                sample_flags.setdefault(sid, []).append('%s_outlier(%.3g)' % (col, v))
                n_out += 1
        qc_summary['metrics'][col] = {
            'median': round(med, 4), 'mad': round(mad, 4),
            'lo': (round(lo, 4) if lo is not None else None),
            'hi': (round(hi, 4) if hi is not None else None),
            'n_outliers': n_out,
        }
    qc_summary['n_outlier_samples'] = len(sample_flags)

# ==================================================================== VERDICT ==
reasons = []
fixables = []

# REJECT drivers
if confound['confounded']:
    reasons.append('REJECT: batch is confounded with biological %s '
                   '(Cramer\\'s V=%.2f, p=%s) — the batch effect and biology are '
                   'mathematically inseparable; batch correction cannot recover the '
                   'true signal.' % (group_field, confound['cramers_v'] or 0.0,
                                     confound['p_value']))
if completeness < min_complete:
    reasons.append('REJECT: metadata completeness %.0f%% is below the %.0f%% floor '
                   'required to harmonize (missing: %s).'
                   % (completeness * 100, min_complete * 100,
                      ', '.join(missing_fields) or 'none'))

# TRIAGE drivers (fixable)
if confound['partial']:
    fixables.append('Partial batch/biology confounding (Cramer\\'s V=%.2f) — rebalance '
                    'samples across batches or add batch as a covariate downstream.'
                    % (confound['cramers_v'] or 0.0))
if missing_fields and completeness >= min_complete:
    fixables.append('Missing required metadata field(s): %s — recover from source '
                    'records before integration.' % ', '.join(missing_fields))
if partial_fields:
    fixables.append('Partially-populated required field(s): %s — fill remaining '
                    'samples.' % ', '.join(partial_fields))
if provenance_missing:
    fixables.append('Incomplete provenance (BRISQ/MIxS) field(s): %s — needed for '
                    'harmonization traceability.' % ', '.join(provenance_missing))
if qc_summary['n_outlier_samples'] > 0:
    fixables.append('%d sample(s) flagged as QC-metric outliers — inspect and '
                    'exclude before integration.' % qc_summary['n_outlier_samples'])

if reasons:
    verdict = 'REJECT'
elif fixables:
    verdict = 'TRIAGE'
else:
    verdict = 'INTEGRATE'
    reasons.append('INTEGRATE: metadata complete (%.0f%%), batch NOT confounded with '
                   'biology (Cramer\\'s V=%s), provenance complete — safe to harmonize.'
                   % (completeness * 100,
                      confound['cramers_v'] if confound['computable'] else 'n/a'))

# ==================================================================== OUTPUTS ==
result = {
    'status': 'completed',
    'dataset_id': dataset_id,
    'verdict': verdict,
    'n_samples': n_samples,
    'reasons': reasons,
    'fixables': fixables,
    'checks': {
        'metadata_completeness': {
            'score': round(completeness, 4),
            'required_fields': required,
            'present_fields': present_fields,
            'missing_fields': missing_fields,
            'partial_fields': partial_fields,
            'per_field': completeness_detail,
            'floor': min_complete,
        },
        'batch_biology_confounding': confound,
        'provenance_completeness': {
            'score': round(provenance_completeness, 4),
            'fields': provenance,
            'missing': provenance_missing,
            'per_field': provenance_detail,
        },
        'qc_metrics': qc_summary,
    },
    'references': [
        'Moore et al. 2011 (BRISQ minimum biospecimen reporting)',
        'Yilmaz et al. 2011 (MIxS minimum information standard)',
        'Leek et al. 2010 (batch effects in high-throughput data)',
    ],
}

with open('qc_triage_results.json', 'w') as fh:
    json.dump(result, fh, indent=2)

# per-sample flags CSV --------------------------------------------------------
with open('sample_qc_flags.csv', 'w', newline='') as fh:
    w = csv.writer(fh)
    w.writerow(['sample_id', 'batch', 'group', 'flags'])
    for i, r in enumerate(rows):
        sid = sample_id_of(r, i)
        b = r.get(batch_field, '') if have_batch else ''
        g = r.get(group_field, '') if have_group else ''
        flags = []
        # per-sample metadata completeness flags
        for field in required:
            if field in header_set and not _present(r.get(field)):
                flags.append('missing_%s' % field)
        flags.extend(sample_flags.get(sid, []))
        w.writerow([sid, b, g, ';'.join(flags)])

# markdown report -------------------------------------------------------------
def pct(x):
    return '—' if x is None else ('%.0f%%' % (x * 100))

L = []
badge = {'INTEGRATE': 'INTEGRATE ✅', 'TRIAGE': 'TRIAGE ⚠', 'REJECT': 'REJECT ⛔'}[verdict]
L.append('# Cohort QC Triage — %s' % dataset_id)
L.append('')
L.append('## Verdict: **%s**' % badge)
L.append('')
L.append('**Samples:** %d' % n_samples)
L.append('')
for rsn in reasons:
    L.append('- %s' % rsn)
L.append('')

L.append('## 1. Metadata completeness — %s' % pct(completeness))
L.append('')
L.append('| Field | Column present | Fill rate |')
L.append('|-------|:--------------:|----------:|')
for field in required:
    d = completeness_detail[field]
    L.append('| %s | %s | %s |' % (
        field, 'yes' if d['column_present'] else 'NO', pct(d['fill_rate'])))
L.append('')

L.append('## 2. Batch <-> biology confounding (most important)')
L.append('')
if not confound['computable']:
    L.append('_Not computable: %s._' % (confound['reason'] or 'insufficient data'))
else:
    verdict_txt = ('CONFOUNDED — un-integratable' if confound['confounded']
                   else ('partial confounding' if confound['partial']
                         else 'not confounded — separable'))
    L.append('- **Cramer\\'s V:** %.3f  (chi2=%.2f, df=%d, p=%s)' % (
        confound['cramers_v'], confound['chi2'], confound['df'], confound['p_value']))
    L.append('- **%d batches x %d groups** over %d samples => **%s**' % (
        confound['n_batches'], confound['n_groups'], confound['n_used'], verdict_txt))
    L.append('')
    L.append('Contingency (batch x %s):' % group_field)
    L.append('')
    grp_keys = sorted({g for b in confound['contingency'] for g in confound['contingency'][b]})
    L.append('| batch \\\\ %s | %s |' % (group_field, ' | '.join(grp_keys)))
    L.append('|%s|%s|' % ('---', '|'.join(['---:'] * len(grp_keys))))
    for b in sorted(confound['contingency']):
        cells = confound['contingency'][b]
        L.append('| %s | %s |' % (b, ' | '.join(str(cells.get(g, 0)) for g in grp_keys)))
L.append('')

L.append('## 3. Provenance completeness (BRISQ / MIxS) — %s' % pct(provenance_completeness))
L.append('')
if provenance_missing:
    L.append('Missing/incomplete: %s' % ', '.join(provenance_missing))
else:
    L.append('All provenance fields present.')
L.append('')

L.append('## 4. QC-metric flags')
L.append('')
if not qc_summary['metrics_provided']:
    L.append('_No qc_metrics_file provided — per-sample metric outliers not evaluated._')
else:
    L.append('%d sample(s) flagged as outliers (MAD rule, k=%.1f).'
             % (qc_summary['n_outlier_samples'], mad_k))
    for col, d in qc_summary['metrics'].items():
        L.append('- **%s**: median=%.3g, %d outlier(s)' % (col, d['median'], d['n_outliers']))
L.append('')

if fixables:
    L.append('## Triage — fixable items')
    L.append('')
    for f in fixables:
        L.append('- %s' % f)
    L.append('')

L.append('## Methodology')
L.append('')
L.append('Metadata completeness = fraction of required fields present as a column '
         'and populated in >=90%% of samples. Batch/biology confounding uses a '
         'chi-square test of independence on the batch x %s contingency table with '
         'Cramer\\'s V effect size (V>=%.2f with p<%.2f => un-integratable). '
         'Provenance follows BRISQ (Moore 2011) and MIxS (Yilmaz 2011); the '
         'confounding rationale follows Leek et al. (2010). Per-sample QC outliers '
         'use a robust median/MAD rule (k=%.1f).'
         % (group_field, v_reject, alpha, mad_k))

with open('qc_triage_report.md', 'w') as fh:
    fh.write('\\n'.join(L) + '\\n')

# console summary -------------------------------------------------------------
print('=== COHORT QC TRIAGE: %s ===' % dataset_id)
print('  samples=%d  completeness=%s  provenance=%s' % (
    n_samples, pct(completeness), pct(provenance_completeness)))
if confound['computable']:
    print('  confounding: Cramers V=%.3f p=%s -> %s' % (
        confound['cramers_v'], confound['p_value'],
        'CONFOUNDED' if confound['confounded'] else ('partial' if confound['partial'] else 'ok')))
print('  VERDICT: %s' % verdict)

with open('versions.yml', 'w') as fh:
    fh.write('cohort_qc_triage:\\n')
    fh.write('  python: "3.10"\\n')
    fh.write('  method: "chi-square + Cramers V confounding; BRISQ/MIxS completeness; MAD outliers"\\n')
PYEOF
    """
}

workflow COHORT_QC_TRIAGE_WORKFLOW {
    take: meta_ch
    main: COHORT_QC_TRIAGE(meta_ch)
    emit:
        results = COHORT_QC_TRIAGE.out.results
        report  = COHORT_QC_TRIAGE.out.report
        flags   = COHORT_QC_TRIAGE.out.flags
}

workflow {
    meta = [id: params.dataset_id ?: 'cohort_qc_run', single_end: false]
    Channel.value(meta) | COHORT_QC_TRIAGE_WORKFLOW
}
