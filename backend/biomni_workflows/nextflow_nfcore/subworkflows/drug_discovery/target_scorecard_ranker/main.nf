#!/usr/bin/env nextflow
/*
 * drug_discovery/target_scorecard_ranker
 *
 * THE TARGET-DISCOVERY RANKING ENGINE ("the brain").
 *
 * Fuses per-target, multi-omic evidence collected across a disease cohort
 * into a single ranked, provenance-backed target scorecard. This is the
 * "AI converts disease-biology layers into ranked decisions" step from the
 * UCB modern-target-discovery workflow (stage 4: Target Identification &
 * Prioritisation — genetic support, cell specificity, biological relevance,
 * tractability).
 *
 * Design principles (matching the client's stated requirements):
 *   - TRANSPARENT: a weighted, auditable aggregation — no black-box ranker.
 *     Every axis keeps its raw value, source and normalised value.
 *   - COVERAGE-AWARE: targets with partial evidence are scored over the axes
 *     actually present (weights renormalised) and flagged, never silently
 *     zeroed.
 *   - HUMAN-IN-THE-LOOP: emits explicit "confirm biological plausibility"
 *     review actions for every priority target; AI ranks, humans decide.
 *
 * Evidence axes (each normalised to 0-1):
 *   genetic_support      Causal genetic link to disease (GWAS/OpenTargets
 *                        genetic score, eQTL colocalisation, rare-variant
 *                        burden). Strongest predictor of clinical success
 *                        (Nelson et al. Nat Genet 2015).
 *   cell_specificity     Expression specificity to the disease-relevant cell
 *                        type (scRNA tau index / disease-cell fraction).
 *   expression_evidence  Differential expression magnitude x significance in
 *                        disease vs control (bulk / pseudobulk), derived from
 *                        expression_lfc + expression_padj.
 *   biological_relevance Pathway-enrichment membership / network centrality /
 *                        disease literature support.
 *   tractability         Druggability (Target Tractability Scorer / TDL /
 *                        protein class).
 *   safety_liability     Penalty axis (essentiality / vital-tissue expression).
 *
 * Framework references: OpenTargets association-score aggregation
 * (Ochoa et al. NAR 2021); genetic-support-of-success (Nelson 2015);
 * Target Development Level (Oprea 2018).
 *
 * Input:  evidence_file (CSV or JSON) of candidate targets + per-axis evidence.
 *         If the file is absent, a bundled illustrative cohort is generated so
 *         the workflow is runnable standalone for demos / smoke tests.
 * Output: target_scorecard.csv, target_scorecard.json, target_ranking_report.md,
 *         scorecard_results.json, versions.yml
 */

nextflow.enable.dsl = 2

params.outdir       = './results'
params.evidence_file = 'NONE'          // REQUIRED path to real per-target evidence CSV/JSON
params.disease       = 'unspecified disease'

// -- Axis weights (must be interpretable; sum is renormalised internally) -----
params.w_genetic      = '0.30'
params.w_specificity  = '0.15'
params.w_expression   = '0.20'
params.w_biological   = '0.15'
params.w_tractability = '0.20'
params.safety_penalty = '0.30'          // max fractional score reduction at liability=1

// -- Normalisation caps for raw differential-expression inputs ----------------
params.lfc_cap       = '3.0'            // |log2FC| at/above which magnitude=1.0
params.sig_cap       = '10.0'           // -log10(padj) at/above which significance=1.0

// -- Minimum axis coverage below which a target is flagged low-confidence -----
params.min_coverage  = '0.5'

// -- Advanced ranker (advisory second opinion; never overrides transparent) ---
//    'auto'      -> network_propagation if network_file given, else harmonic_sum
//    'harmonic'  -> non-linear harmonic-sum aggregation (OpenTargets production)
//    'network'   -> Random Walk with Restart over network_file (graph-relational)
//    'off'       -> skip second opinion
params.advanced_method        = 'auto'
params.network_file           = 'NONE'   // edge list: geneA,geneB[,weight]
params.rwr_restart            = '0.40'   // RWR restart probability
params.disagreement_rank_delta = '2'     // |rank shift| that triggers human-review flag

process TARGET_SCORECARD_RANKER {
    tag "$meta.id"
    label 'process_low'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("scorecard_results.json"),    emit: results
    tuple val(meta), path("target_scorecard.csv"),      emit: scorecard
    tuple val(meta), path("target_scorecard.json"),     emit: scorecard_json
    tuple val(meta), path("target_ranking_report.md"),  emit: report
    tuple val(meta), path("ranker_comparison.csv"),     emit: comparison
    path "versions.yml",                                emit: versions

    script:
    """
    export PARAM_EVIDENCE='${params.evidence_file}'
    export PARAM_DISEASE='${params.disease}'
    export PARAM_W_GENETIC='${params.w_genetic}'
    export PARAM_W_SPEC='${params.w_specificity}'
    export PARAM_W_EXPR='${params.w_expression}'
    export PARAM_W_BIO='${params.w_biological}'
    export PARAM_W_TRACT='${params.w_tractability}'
    export PARAM_SAFETY_PEN='${params.safety_penalty}'
    export PARAM_LFC_CAP='${params.lfc_cap}'
    export PARAM_SIG_CAP='${params.sig_cap}'
    export PARAM_MIN_COV='${params.min_coverage}'
    export PARAM_ADV_METHOD='${params.advanced_method}'
    export PARAM_NETWORK='${params.network_file}'
    export PARAM_RWR_RESTART='${params.rwr_restart}'
    export PARAM_DISAGREE_DELTA='${params.disagreement_rank_delta}'

    python3 << 'PYEOF'
import json, os, csv, math, sys

# ------------------------------------------------------------------ helpers ---
def _f(v, default=None):
    if v in (None, '', 'null', 'None', 'NA', 'nan'): return default
    try: return float(v)
    except Exception: return default

def clamp01(x):
    if x is None: return None
    return max(0.0, min(1.0, x))

def norm_weights(w):
    s = sum(w.values())
    if s <= 0: return {k: 0.0 for k in w}
    return {k: v / s for k, v in w.items()}

# ------------------------------------------------------------------- params ---
disease   = os.environ.get('PARAM_DISEASE', 'unspecified disease')
lfc_cap   = _f(os.environ.get('PARAM_LFC_CAP'), 3.0)
sig_cap   = _f(os.environ.get('PARAM_SIG_CAP'), 10.0)
min_cov   = _f(os.environ.get('PARAM_MIN_COV'), 0.5)
safety_pen = _f(os.environ.get('PARAM_SAFETY_PEN'), 0.30)

WEIGHTS = norm_weights({
    'genetic_support':      _f(os.environ.get('PARAM_W_GENETIC'), 0.30),
    'cell_specificity':     _f(os.environ.get('PARAM_W_SPEC'),    0.15),
    'expression_evidence':  _f(os.environ.get('PARAM_W_EXPR'),    0.20),
    'biological_relevance': _f(os.environ.get('PARAM_W_BIO'),     0.15),
    'tractability':         _f(os.environ.get('PARAM_W_TRACT'),   0.20),
})
AXES = list(WEIGHTS.keys())

# ------------------------------------------------------ load evidence (real only)
def _rows_from_csv(path):
    rows = []
    with open(path, newline='') as fh:
        for r in csv.DictReader(fh):
            rows.append(r)
    return rows

def _rows_from_json(path):
    with open(path) as fh:
        data = json.load(fh)
    if isinstance(data, dict) and 'targets' in data:
        data = data['targets']
    return data

evidence_path = os.environ.get('PARAM_EVIDENCE', 'NONE')
if (not evidence_path) or evidence_path in ('NONE', '') or not os.path.exists(evidence_path):
    sys.stderr.write(
        "ERROR: --evidence_file is required and must point to a real per-target "
        "evidence CSV/JSON (e.g. the target_evidence.csv emitted by query_opentarget, "
        "GMRP, or a multi-omics run). No synthetic data is generated.\\n")
    with open('scorecard_results.json', 'w') as _f:
        json.dump({'status': 'failed',
                   'error': 'evidence_file missing or not found: %r' % evidence_path,
                   'targets': []}, _f, indent=2)
    sys.exit(1)
source_label = os.path.basename(evidence_path)
raw_rows = (_rows_from_json(evidence_path) if evidence_path.lower().endswith('.json')
            else _rows_from_csv(evidence_path))

# ---------------------------------------------------------- axis normalisation
def expression_evidence(lfc, padj):
    '''Combine effect magnitude and significance into a single 0-1 axis.'''
    if lfc is None and padj is None:
        return None
    mag = None if lfc is None else clamp01(abs(lfc) / lfc_cap)
    sig = None
    if padj is not None and padj > 0:
        sig = clamp01((-math.log10(padj)) / sig_cap)
    if mag is not None and sig is not None:
        return round(0.5 * mag + 0.5 * sig, 4)
    return round(mag if mag is not None else sig, 4)

def normalise_target(row):
    gene = (row.get('gene') or row.get('symbol') or row.get('name') or '').strip()
    axes = {
        'genetic_support':      clamp01(_f(row.get('genetic_support'))),
        'cell_specificity':     clamp01(_f(row.get('cell_specificity'))),
        'expression_evidence':  expression_evidence(_f(row.get('expression_lfc')),
                                                     _f(row.get('expression_padj'))),
        'biological_relevance': clamp01(_f(row.get('biological_relevance'))),
        'tractability':         clamp01(_f(row.get('tractability'))),
    }
    safety = clamp01(_f(row.get('safety_liability')))
    return gene, axes, safety, row

# ------------------------------------------------------------- scoring engine
def score_target(axes, safety):
    present = {a: v for a, v in axes.items() if v is not None}
    covered_w = sum(WEIGHTS[a] for a in present)              # of total 1.0
    if covered_w <= 0:
        base = None
    else:
        base = sum(WEIGHTS[a] * present[a] for a in present) / covered_w
    penalty = 0.0 if (safety is None or base is None) else safety_pen * safety
    final = None if base is None else round(base * (1.0 - penalty), 4)
    return {
        'base_score': None if base is None else round(base, 4),
        'safety_liability': safety,
        'safety_penalty_applied': round(penalty, 4) if base is not None else None,
        'overall_score': final,
        'coverage': round(covered_w, 4),
        'n_axes_present': len(present),
    }

def tier_of(score, coverage):
    if score is None:
        return 'UNSCORED', 'Insufficient evidence — collect orthogonal data'
    low = coverage < min_cov
    if score >= 0.75:
        t = 'TIER 1 — Priority target'
        rec = 'Advance to disease-model validation (human review: confirm biological plausibility)'
    elif score >= 0.60:
        t = 'TIER 2 — Strong candidate'
        rec = 'Queue for validation pending orthogonal confirmation (human review)'
    elif score >= 0.45:
        t = 'TIER 3 — Watch'
        rec = 'Insufficient conviction — gather more evidence before committing resources'
    else:
        t = 'TIER 4 — Deprioritise'
        rec = 'Below prioritisation threshold'
    if low:
        rec += f' [LOW COVERAGE {coverage:.0%} — score is provisional]'
    return t, rec

# --------------------------------------------------------------- run all rows
scored = []
for row in raw_rows:
    gene, axes, safety, orig = normalise_target(row)
    if not gene:
        continue
    sc = score_target(axes, safety)
    tier, rec = tier_of(sc['overall_score'], sc['coverage'])
    scored.append({
        'gene': gene,
        'axes_normalised': axes,
        **sc,
        'tier': tier,
        'recommendation': rec,
        'disease_cell_type': orig.get('disease_cell_type', ''),
        'notes': orig.get('notes', ''),
        'evidence_raw': {
            'genetic_support': _f(orig.get('genetic_support')),
            'cell_specificity': _f(orig.get('cell_specificity')),
            'expression_lfc': _f(orig.get('expression_lfc')),
            'expression_padj': _f(orig.get('expression_padj')),
            'biological_relevance': _f(orig.get('biological_relevance')),
            'tractability': _f(orig.get('tractability')),
            'safety_liability': _f(orig.get('safety_liability')),
        },
    })

# scored (numeric) first, descending; unscored last
scored.sort(key=lambda d: (d['overall_score'] is not None, d['overall_score'] or 0.0),
            reverse=True)
for i, d in enumerate(scored, 1):
    d['rank'] = i

# ============================================================================
# ADVANCED RANKER — advisory second opinion (never overrides transparent score)
# ----------------------------------------------------------------------------
# Two relational/non-linear methods, both unsupervised (no training labels):
#   harmonic_sum          OpenTargets' production non-linear aggregation. Rewards
#                         targets with MULTIPLE converging strong axes; penalises
#                         reliance on a single axis. Different ordering than the
#                         linear weighted mean.
#   network_propagation   Random Walk with Restart over a gene network. Diffuses
#                         the transparent scores through interaction/co-expression
#                         edges (guilt-by-association / module membership) — the
#                         same evidence-propagation a message-passing GNN performs,
#                         without needing a labelled training set. A supervised
#                         GNN/learning-to-rank can later replace this behind the
#                         same interface once target-outcome labels exist.
# ----------------------------------------------------------------------------
adv_method_req = (os.environ.get('PARAM_ADV_METHOD', 'auto') or 'auto').lower()
network_path   = os.environ.get('PARAM_NETWORK', 'NONE')
rwr_restart    = _f(os.environ.get('PARAM_RWR_RESTART'), 0.40)
disagree_delta = int(_f(os.environ.get('PARAM_DISAGREE_DELTA'), 2) or 2)

def harmonic_sum_score(axes):
    '''OpenTargets-style harmonic sum over present, weight-scaled axis values.'''
    contribs = sorted((WEIGHTS[a] * v for a, v in axes.items() if v is not None),
                      reverse=True)
    if not contribs:
        return None
    hs     = sum(c / ((i + 1) ** 2) for i, c in enumerate(contribs))
    hs_max = sum(WEIGHTS[a] / ((i + 1) ** 2)
                 for i, a in enumerate(sorted(WEIGHTS, key=WEIGHTS.get, reverse=True)))
    return round(hs / hs_max, 4) if hs_max > 0 else None

def load_network(path):
    '''edge list geneA,geneB[,weight] -> adjacency dict. Undirected.'''
    adj = {}
    with open(path, newline='') as fh:
        rdr = csv.reader(fh)
        first = True
        for row in rdr:
            if not row or len(row) < 2:
                continue
            if first:
                first = False
                # skip header if non-numeric third col / obvious header
                if row[0].lower() in ('gene', 'genea', 'source', 'from'):
                    continue
            a, b = row[0].strip(), row[1].strip()
            w = _f(row[2], 1.0) if len(row) > 2 else 1.0
            if not a or not b or a == b:
                continue
            adj.setdefault(a, {})[b] = w
            adj.setdefault(b, {})[a] = w
    return adj

def random_walk_with_restart(seed, adj, restart=0.40, iters=100, tol=1e-6):
    '''Power-iteration RWR. seed: {gene: score>=0}. Returns stationary dist.'''
    genes = list(seed.keys())
    s_total = sum(seed.values()) or 1.0
    seed_n = {g: seed[g] / s_total for g in genes}
    p = dict(seed_n)
    # column-normalise adjacency (restrict to scored genes)
    norm = {}
    for g in genes:
        nbrs = {n: w for n, w in adj.get(g, {}).items() if n in seed_n}
        tot = sum(nbrs.values())
        norm[g] = {n: w / tot for n, w in nbrs.items()} if tot > 0 else {}
    for _ in range(iters):
        nxt = {g: restart * seed_n[g] for g in genes}
        for g in genes:
            for n, w in norm[g].items():
                nxt[n] += (1 - restart) * w * p[g]
        diff = sum(abs(nxt[g] - p[g]) for g in genes)
        p = nxt
        if diff < tol:
            break
    return p

# choose method
advanced = None
adv_method = 'off'
have_network = network_path not in ('NONE', '', None) and os.path.exists(network_path)
if adv_method_req == 'auto':
    adv_method = 'network_propagation' if have_network else 'harmonic_sum'
elif adv_method_req in ('network', 'network_propagation'):
    adv_method = 'network_propagation' if have_network else 'harmonic_sum'  # graceful fallback
elif adv_method_req in ('harmonic', 'harmonic_sum'):
    adv_method = 'harmonic_sum'
else:
    adv_method = 'off'

scorable = [d for d in scored if d['overall_score'] is not None]
if adv_method == 'harmonic_sum':
    for d in scorable:
        d['advanced_score'] = harmonic_sum_score(d['axes_normalised'])
elif adv_method == 'network_propagation':
    adj = load_network(network_path)
    seed = {d['gene']: d['overall_score'] for d in scorable}
    stat = random_walk_with_restart(seed, adj, restart=rwr_restart)
    lo, hi = (min(stat.values()), max(stat.values())) if stat else (0.0, 1.0)
    span = (hi - lo) or 1.0
    for d in scorable:
        d['advanced_score'] = round((stat.get(d['gene'], lo) - lo) / span, 4)

comparison = []
disagreements = []
if adv_method != 'off' and scorable:
    by_adv = sorted(scorable, key=lambda d: d.get('advanced_score') or 0.0, reverse=True)
    adv_rank = {d['gene']: i for i, d in enumerate(by_adv, 1)}
    for d in scorable:
        t_rank = d['rank']
        a_rank = adv_rank[d['gene']]
        delta = t_rank - a_rank            # +ve => advanced ranks it HIGHER
        d['advanced_method'] = adv_method
        d['advanced_rank'] = a_rank
        d['rank_delta'] = delta
        is_disagree = abs(delta) >= disagree_delta
        d['ranker_disagreement'] = is_disagree
        comparison.append({
            'gene': d['gene'], 'transparent_score': d['overall_score'],
            'transparent_rank': t_rank, 'advanced_score': d.get('advanced_score'),
            'advanced_rank': a_rank, 'rank_delta': delta,
            'advanced_method': adv_method, 'disagreement': is_disagree,
        })
        if is_disagree:
            direction = ('advanced ranks HIGHER' if delta > 0 else 'advanced ranks LOWER')
            disagreements.append({
                'gene': d['gene'], 'transparent_rank': t_rank, 'advanced_rank': a_rank,
                'rank_delta': delta, 'direction': direction,
            })
    disagreements.sort(key=lambda x: abs(x['rank_delta']), reverse=True)

# ------------------------------------------------------------------- outputs
run_meta = {
    'disease': disease,
    'evidence_source': source_label,
    'n_targets': len(scored),
    'weights': WEIGHTS,
    'safety_penalty_max': safety_pen,
    'min_coverage_flag': min_cov,
    'expression_caps': {'lfc_cap': lfc_cap, 'sig_cap': sig_cap},
    'framework': 'OpenTargets-style transparent weighted aggregation; '
                 'genetic-support-of-success (Nelson 2015); TDL (Oprea 2018)',
    'advanced_ranker': {
        'method': adv_method,
        'role': 'advisory second opinion — transparent score remains decision of record',
        'rwr_restart': rwr_restart if adv_method == 'network_propagation' else None,
        'disagreement_rank_delta': disagree_delta,
        'n_disagreements': len(disagreements),
    },
}

with open('target_scorecard.json', 'w') as fh:
    json.dump({'run': run_meta, 'targets': scored}, fh, indent=2)

with open('scorecard_results.json', 'w') as fh:
    json.dump({'status': 'completed', 'disease': disease,
               'n_targets': len(scored),
               'top_targets': [d['gene'] for d in scored[:5]],
               'run': run_meta, 'targets': scored}, fh, indent=2)

# CSV -------------------------------------------------------------------------
csv_cols = ['rank', 'gene', 'overall_score', 'tier', 'coverage', 'n_axes_present',
            'genetic_support', 'cell_specificity', 'expression_evidence',
            'biological_relevance', 'tractability', 'safety_liability',
            'disease_cell_type', 'recommendation', 'notes']
with open('target_scorecard.csv', 'w', newline='') as fh:
    w = csv.writer(fh)
    w.writerow(csv_cols)
    for d in scored:
        a = d['axes_normalised']
        w.writerow([
            d['rank'], d['gene'], d['overall_score'], d['tier'],
            f"{d['coverage']:.2f}", d['n_axes_present'],
            a['genetic_support'], a['cell_specificity'], a['expression_evidence'],
            a['biological_relevance'], a['tractability'], d['safety_liability'],
            d['disease_cell_type'], d['recommendation'], d['notes'],
        ])

# Ranker comparison CSV -------------------------------------------------------
with open('ranker_comparison.csv', 'w', newline='') as fh:
    w = csv.writer(fh)
    w.writerow(['gene', 'transparent_score', 'transparent_rank',
                'advanced_score', 'advanced_rank', 'rank_delta',
                'advanced_method', 'disagreement'])
    for c in sorted(comparison, key=lambda x: x['transparent_rank']):
        w.writerow([c['gene'], c['transparent_score'], c['transparent_rank'],
                    c['advanced_score'], c['advanced_rank'], c['rank_delta'],
                    c['advanced_method'], 'YES' if c['disagreement'] else ''])

# Markdown report -------------------------------------------------------------
def fmt(v):
    return '—' if v is None else (f'{v:.2f}' if isinstance(v, float) else str(v))

lines = []
lines.append(f'# Target Scorecard — {disease}')
lines.append('')
lines.append(f'**Evidence source:** `{source_label}`  |  **Targets scored:** {len(scored)}')
lines.append('')
lines.append('AI-ranked, provenance-backed prioritisation. Rankings are a decision '
             'aid — every Tier 1/2 target requires human confirmation of biological '
             'plausibility before resourcing.')
lines.append('')
lines.append('**Axis weights:** ' + ', '.join(f'{k}={v:.2f}' for k, v in WEIGHTS.items())
             + f'  |  safety penalty (max) = {safety_pen:.2f}')
lines.append('')
lines.append('## Ranked targets')
lines.append('')
lines.append('| Rank | Gene | Score | Tier | Cov | Genetic | CellSpec | Expr | Biol | Tract | Safety |')
lines.append('|-----:|------|------:|------|----:|--------:|---------:|-----:|-----:|------:|-------:|')
for d in scored:
    a = d['axes_normalised']
    lines.append(
        f"| {d['rank']} | {d['gene']} | {fmt(d['overall_score'])} | "
        f"{d['tier'].split(' — ')[0]} | {d['coverage']:.0%} | "
        f"{fmt(a['genetic_support'])} | {fmt(a['cell_specificity'])} | "
        f"{fmt(a['expression_evidence'])} | {fmt(a['biological_relevance'])} | "
        f"{fmt(a['tractability'])} | {fmt(d['safety_liability'])} |")
lines.append('')
lines.append('## Priority targets — human review required')
lines.append('')
priority = [d for d in scored if d['tier'].startswith(('TIER 1', 'TIER 2'))]
if not priority:
    lines.append('_No target cleared the Tier 2 threshold on current evidence._')
for d in priority:
    lines.append(f"### {d['rank']}. {d['gene']} — {d['tier']} (score {fmt(d['overall_score'])})")
    lines.append(f"- **Recommendation:** {d['recommendation']}")
    if d['disease_cell_type']:
        lines.append(f"- **Disease cell type:** {d['disease_cell_type']}")
    if d['notes']:
        lines.append(f"- **Evidence note:** {d['notes']}")
    lines.append(f"- **Coverage:** {d['coverage']:.0%} ({d['n_axes_present']}/5 axes)")
    lines.append('')

low_cov = [d for d in scored if d['coverage'] < min_cov]
if low_cov:
    lines.append('## ⚠ Low-coverage targets (provisional scores)')
    lines.append('')
    for d in low_cov:
        missing = [a for a in AXES if d['axes_normalised'][a] is None]
        lines.append(f"- **{d['gene']}** — {d['coverage']:.0%} coverage; "
                     f"missing: {', '.join(missing) or 'none'}. Gather orthogonal evidence.")
    lines.append('')

if adv_method != 'off' and comparison:
    method_label = ('Random Walk with Restart (network propagation)'
                    if adv_method == 'network_propagation'
                    else 'Harmonic-sum aggregation (OpenTargets production)')
    lines.append('## Advanced ranker — second opinion (advisory)')
    lines.append('')
    lines.append(f'**Method:** {method_label}. This is a decision *aid* only — the '
                 'transparent weighted score above remains the ranking of record. '
                 'The advanced ranker captures non-linear / relational signal; where '
                 'the two disagree, a human should look closer.')
    lines.append('')
    if disagreements:
        lines.append(f'**{len(disagreements)} disagreement(s) flagged for human review** '
                     f'(rank shift ≥ {disagree_delta}):')
        lines.append('')
        lines.append('| Gene | Transparent rank | Advanced rank | Δ | Signal |')
        lines.append('|------|-----------------:|--------------:|--:|--------|')
        for x in disagreements:
            lines.append(f"| {x['gene']} | {x['transparent_rank']} | {x['advanced_rank']} | "
                         f"{x['rank_delta']:+d} | {x['direction']} |")
        lines.append('')
        lines.append('_A target the advanced ranker lifts may have converging or '
                     'network-connected evidence the linear score under-weights; one it '
                     'drops may be riding a single strong axis. Confirm biologically._')
    else:
        lines.append('_Both rankers agree within tolerance — no target shifted '
                     f'≥ {disagree_delta} ranks._')
    lines.append('')

lines.append('## Methodology')
lines.append('')
lines.append('Each axis is normalised to 0–1. The overall score is a weighted mean over '
             'the axes **actually present** for a target (weights renormalised to the '
             'covered set), then reduced by a safety-liability penalty '
             '(`score × (1 − penalty_max × liability)`). Coverage-aware scoring avoids '
             'unfairly zeroing partially-characterised targets, and every score carries '
             'its per-axis provenance for audit. Framework: OpenTargets-style association '
             'aggregation (Ochoa 2021); genetic support of clinical success (Nelson 2015); '
             'Target Development Level (Oprea 2018).')

with open('target_ranking_report.md', 'w') as fh:
    fh.write('\\n'.join(lines) + '\\n')

# console summary -------------------------------------------------------------
print(f'=== TARGET SCORECARD: {disease} ({len(scored)} targets) ===')
for d in scored[:8]:
    print(f"  #{d['rank']:<2} {d['gene']:<10} score={fmt(d['overall_score']):>5} "
          f"cov={d['coverage']:.0%}  {d['tier']}")

with open('versions.yml', 'w') as fh:
    fh.write('target_scorecard_ranker:\\n')
    fh.write('  python: "3.10"\\n')
    fh.write('  framework: "OpenTargets-style weighted aggregation + Nelson 2015 + Oprea TDL 2018"\\n')
PYEOF
    """
}

workflow TARGET_SCORECARD_WORKFLOW {
    take: meta_ch
    main: TARGET_SCORECARD_RANKER(meta_ch)
    emit:
        results   = TARGET_SCORECARD_RANKER.out.results
        scorecard = TARGET_SCORECARD_RANKER.out.scorecard
        report    = TARGET_SCORECARD_RANKER.out.report
}

workflow {
    meta = [id: 'scorecard_run', single_end: false]
    Channel.value(meta) | TARGET_SCORECARD_WORKFLOW
}
