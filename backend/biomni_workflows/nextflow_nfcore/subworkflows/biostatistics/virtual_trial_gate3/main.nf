#!/usr/bin/env nextflow
/*
 * biostatistics/virtual_trial_gate3
 *
 * VIRTUAL TRIAL / POWER SIMULATION for the gate-3 predictive-biomarker test.
 *
 * Gate-3 validation (is a biomarker PREDICTIVE, i.e. does it change WHICH
 * treatment is better — see biostatistics/gate3_interaction_test) ultimately
 * needs a biomarker x treatment interaction RCT, which is expensive to run.
 * Before committing to that trial, this tool DE-RISKS and SIZES it: given a
 * mechanistic PARAMETER SPEC of the user's real design assumptions (biomarker
 * prevalence, sample size, allocation, and the expected outcome per
 * {biomarker+/-} x {control/experimental} cell), it:
 *
 *   1. DETERMINISTICALLY generates n_sim virtual-patient cohorts from the spec
 *      (binomial draws for binary outcomes; Box-Muller normal draws for
 *      continuous — a seedable stdlib LCG, seed varied per replicate by index,
 *      NO Math.random / wall-clock),
 *   2. runs the SAME gate-3 interaction math on each replicate (biomarker x
 *      treatment interaction estimate / 95% CI / p — binary risk-difference
 *      with delta-method SE, or continuous mean-difference),
 *   3. reports the PREDICTED interaction, its distribution, the statistical
 *      POWER to detect it (fraction of replicates that are significant AND
 *      meaningful), the expected % of decisions changed, and a verdict
 *      (predicted to pass gate-3 at power Y, or under-powered -> need N=?).
 *
 * EVERYTHING here is SIMULATED / PREDICTED. This is a DESIGN tool to size and
 * de-risk a real trial — it is NOT clinical evidence. Outputs are labelled as
 * such. This is legitimate power simulation: it consumes the user's REAL design
 * assumptions (the spec). It is NOT a synthetic-data fallback — if the spec is
 * missing the workflow FAILS FAST (exit 1) and never invents parameters.
 *
 * References: FDA-NIH BEST framework (biomarker predictive vs prognostic);
 * in-silico trials / Model-Informed Drug Development (MIDD); interaction-test
 * power methodology (Brookes 2001 subgroup-interaction power).
 *
 * INPUT (REQUIRED): --spec_file, a CSV or JSON design spec. See the header of
 * the script for the accepted columns/keys. If absent -> failed JSON + exit(1).
 * OUTPUT: virtual_trial_results.json, power_report.md,
 *         simulation_replicates.csv, versions.yml
 */

nextflow.enable.dsl = 2

params.outdir        = './results'
params.spec_file     = 'NONE'        // REQUIRED: real design-assumption spec (CSV or JSON)
params.analysis      = 'virtual gate-3 power simulation'
params.n_sim         = '500'         // number of replicate virtual trials
params.alpha         = '0.05'        // two-sided significance level for the interaction
params.min_interaction = '0.10'      // |interaction| below this = not meaningful even if significant
params.outcome_type  = 'auto'        // auto | binary | continuous
params.seed_base     = '20260101'    // deterministic base seed; per-replicate seed = f(seed_base, index)
params.target_power  = '0.80'        // power target for the sample-size suggestion
params.higher_is_better = 'true'     // is a higher outcome the better result?

process VIRTUAL_TRIAL_GATE3 {
    tag "$meta.id"
    label 'process_low'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("virtual_trial_results.json"),  emit: results
    tuple val(meta), path("power_report.md"),             emit: report
    tuple val(meta), path("simulation_replicates.csv"),   emit: replicates
    path "versions.yml",                                  emit: versions

    script:
    """
    export PARAM_SPEC='${params.spec_file}'
    export PARAM_ANALYSIS='${params.analysis.toString().replace("'", "'\\''")}'
    export PARAM_N_SIM='${params.n_sim}'
    export PARAM_ALPHA='${params.alpha}'
    export PARAM_MIN_INT='${params.min_interaction}'
    export PARAM_OUTCOME_TYPE='${params.outcome_type}'
    export PARAM_SEED_BASE='${params.seed_base}'
    export PARAM_TARGET_POWER='${params.target_power}'
    export PARAM_HIB='${params.higher_is_better}'

    python3 << 'PYEOF'
import os, sys, json, csv, math

# ------------------------------------------------------------------ helpers ---
def _f(v, d=None):
    if v in (None, '', 'null', 'None', 'NA', 'nan'): return d
    try: return float(v)
    except Exception: return d

def _i(v, d=None):
    x = _f(v, None)
    return int(round(x)) if x is not None else d

def norm_cdf(z):
    return 0.5 * (1.0 + math.erf(z / math.sqrt(2.0)))

def two_sided_p(z):
    return 2.0 * (1.0 - norm_cdf(abs(z)))

# ------------------------------------------------------------------- params ---
analysis   = os.environ.get('PARAM_ANALYSIS', 'virtual gate-3 power simulation')
n_sim      = _i(os.environ.get('PARAM_N_SIM'), 500)
alpha      = _f(os.environ.get('PARAM_ALPHA'), 0.05)
min_int    = _f(os.environ.get('PARAM_MIN_INT'), 0.10)
otype_req  = (os.environ.get('PARAM_OUTCOME_TYPE') or 'auto').lower()
seed_base  = os.environ.get('PARAM_SEED_BASE', '20260101')
target_pow = _f(os.environ.get('PARAM_TARGET_POWER'), 0.80)
hib        = (os.environ.get('PARAM_HIB') or 'true').lower() in ('true', '1', 'yes')
z_crit     = 1.959964   # ~alpha 0.05 two-sided for the reported CI

def orient(x):
    return x if hib else -x

# -------------------------------------------------------- fail-fast handler ---
def fail(msg):
    with open('virtual_trial_results.json', 'w') as f:
        json.dump({'status': 'failed', 'error': msg,
                   'note': 'SIMULATION design tool — requires a real parameter spec; '
                           'no parameters are invented'}, f, indent=2)
    with open('simulation_replicates.csv', 'w') as f:
        f.write('replicate,interaction,p_value,significant,meaningful\\n')
    with open('power_report.md', 'w') as f:
        f.write('# Virtual gate-3 power simulation — FAILED\\n\\n%s\\n' % msg)
    with open('versions.yml', 'w') as f:
        f.write('virtual_trial_gate3:\\n  status: "failed"\\n')
    sys.exit(1)

# ============================================================================
# SPEC LOADING
# ----------------------------------------------------------------------------
# The spec gives per-stratum design assumptions. Accepted shapes:
#
# JSON:
#   {
#     "biomarker_prevalence": 0.4,      # P(biomarker+) in the trial population
#     "n_total": 400,                   # total planned enrolment
#     "allocation_ratio": 1.0,          # experimental:control (1.0 = 1:1)
#     "outcome_type": "binary",         # binary | continuous  (optional; else auto)
#     "strata": {                       # expected outcome per cell
#        "positive": {"control": {...}, "experimental": {...}},
#        "negative": {"control": {...}, "experimental": {...}}
#     }
#   }
#   binary cell:      {"response_rate": 0.25}
#   continuous cell:  {"mean": -2.1, "sd": 3.0}
#
# CSV (long form, one row per {biomarker x arm} cell):
#   biomarker,arm,response_rate,mean,sd,biomarker_prevalence,n_total,allocation_ratio
#   positive,control,0.20,,,0.4,400,1.0
#   positive,experimental,0.55,,,0.4,400,1.0
#   negative,control,0.20,,,0.4,400,1.0
#   negative,experimental,0.24,,,0.4,400,1.0
# (population-level fields may be given on any/every row; first non-empty wins)
# ----------------------------------------------------------------------------
spec_path = os.environ.get('PARAM_SPEC', 'NONE')
if (not spec_path) or spec_path in ('NONE', '') or not os.path.exists(spec_path):
    fail('--spec_file is required: a CSV or JSON design spec giving biomarker_prevalence, '
         'n_total, allocation_ratio and the expected outcome per {biomarker +/-} x '
         '{control/experimental} cell. This is a power-SIMULATION design tool; it needs '
         'your real assumptions and NEVER invents parameters.')

def _norm_bm(s):
    s = str(s).strip().lower()
    if s in ('positive', 'pos', '1', '1.0', 'yes', 'true', '+', 'bm+', 'biomarker+'): return 'positive'
    if s in ('negative', 'neg', '0', '0.0', 'no', 'false', '-', 'bm-', 'biomarker-'): return 'negative'
    return s

def _norm_arm(s):
    s = str(s).strip().lower()
    if s in ('experimental', 'exp', 'treated', 'treatment', 'active', 'drug', 'b', '1', '1.0'): return 'experimental'
    if s in ('control', 'ctl', 'ctrl', 'placebo', 'soc', 'a', '0', '0.0'): return 'control'
    return s

# cells[('positive','experimental')] = {'response_rate':..} or {'mean':..,'sd':..}
cells = {}
pop = {'biomarker_prevalence': None, 'n_total': None, 'allocation_ratio': None}
spec_outcome_type = None

if spec_path.lower().endswith('.json'):
    with open(spec_path) as fh:
        spec = json.load(fh)
    pop['biomarker_prevalence'] = _f(spec.get('biomarker_prevalence'))
    pop['n_total']              = _i(spec.get('n_total'))
    pop['allocation_ratio']     = _f(spec.get('allocation_ratio'), 1.0)
    spec_outcome_type           = (spec.get('outcome_type') or '').strip().lower() or None
    strata = spec.get('strata') or spec.get('cells') or {}
    for bm_key, arms in strata.items():
        bm = _norm_bm(bm_key)
        if not isinstance(arms, dict):
            continue
        for arm_key, cell in arms.items():
            arm = _norm_arm(arm_key)
            if not isinstance(cell, dict):
                continue
            entry = {}
            if cell.get('response_rate') is not None:
                entry['response_rate'] = _f(cell.get('response_rate'))
            if cell.get('mean') is not None:
                entry['mean'] = _f(cell.get('mean'))
                entry['sd']   = _f(cell.get('sd'), 1.0)
            cells[(bm, arm)] = entry
else:
    with open(spec_path, newline='') as fh:
        rows = list(csv.DictReader(fh))
    if not rows:
        fail('spec_file (CSV) has no rows')
    def gv(row, *names):
        for n in names:
            for k in row:
                if k.strip().lower() == n:
                    return row[k]
        return None
    for r in rows:
        bm  = gv(r, 'biomarker', 'stratum', 'subgroup', 'biomarker_status')
        arm = gv(r, 'arm', 'treatment', 'treatment_arm', 'drug')
        if bm is None or arm is None:
            continue
        bm = _norm_bm(bm); arm = _norm_arm(arm)
        entry = {}
        rr = _f(gv(r, 'response_rate', 'rate', 'p', 'prob', 'responder_rate'))
        mn = _f(gv(r, 'mean', 'outcome_mean', 'mu'))
        sd = _f(gv(r, 'sd', 'stdev', 'std', 'sigma'))
        if rr is not None:
            entry['response_rate'] = rr
        if mn is not None:
            entry['mean'] = mn
            entry['sd']   = sd if sd is not None else 1.0
        cells[(bm, arm)] = entry
        # population-level fields — first non-empty wins
        if pop['biomarker_prevalence'] is None:
            pop['biomarker_prevalence'] = _f(gv(r, 'biomarker_prevalence', 'prevalence', 'bm_prevalence'))
        if pop['n_total'] is None:
            pop['n_total'] = _i(gv(r, 'n_total', 'n', 'sample_size'))
        if pop['allocation_ratio'] is None:
            pop['allocation_ratio'] = _f(gv(r, 'allocation_ratio', 'allocation', 'ratio'), 1.0)

# ---- validate the spec (fail fast on any missing design assumption) ----------
need_cells = [('positive', 'control'), ('positive', 'experimental'),
              ('negative', 'control'), ('negative', 'experimental')]
missing = [f'{b}/{a}' for (b, a) in need_cells if (b, a) not in cells]
if missing:
    fail('spec missing required cell(s): %s. Need all four {positive,negative} x '
         '{control,experimental} cells.' % ', '.join(missing))

# decide outcome type from the spec (do not invent)
otype = otype_req
if otype == 'auto':
    otype = spec_outcome_type or ('binary' if all('response_rate' in cells[c] for c in need_cells) else 'continuous')
if otype not in ('binary', 'continuous'):
    fail('outcome_type must be binary or continuous (got %r)' % otype)

for (b, a) in need_cells:
    c = cells[(b, a)]
    if otype == 'binary':
        rr = c.get('response_rate')
        if rr is None:
            fail('binary spec: cell %s/%s missing response_rate' % (b, a))
        if not (0.0 <= rr <= 1.0):
            fail('binary spec: response_rate for %s/%s out of [0,1]: %r' % (b, a, rr))
    else:
        if c.get('mean') is None:
            fail('continuous spec: cell %s/%s missing mean' % (b, a))
        if c.get('sd') is None or c.get('sd') <= 0:
            fail('continuous spec: cell %s/%s needs sd > 0' % (b, a))

prev = pop['biomarker_prevalence']
n_total = pop['n_total']
alloc = pop['allocation_ratio'] if pop['allocation_ratio'] and pop['allocation_ratio'] > 0 else 1.0
if prev is None or not (0.0 < prev < 1.0):
    fail('spec needs biomarker_prevalence in (0,1); got %r' % prev)
if n_total is None or n_total < 8:
    fail('spec needs n_total >= 8; got %r' % n_total)

# ============================================================================
# DETERMINISTIC PRNG — seedable, stdlib only (NO random module state, NO time)
# ----------------------------------------------------------------------------
# 64-bit LCG (Numerical Recipes constants). Seeded per replicate by a hash of
# (seed_base, replicate index) so the whole simulation is reproducible: two runs
# with the same params produce byte-identical outputs.
# ----------------------------------------------------------------------------
class LCG:
    def __init__(self, seed):
        self.state = (seed & ((1 << 64) - 1)) or 0x9E3779B97F4A7C15
    def _next(self):
        # x_{n+1} = (a*x + c) mod 2^64
        self.state = (6364136223846793005 * self.state + 1442695040888963407) & ((1 << 64) - 1)
        return self.state
    def uniform(self):
        # 53-bit mantissa uniform in [0,1)
        return (self._next() >> 11) / float(1 << 53)
    def bernoulli(self, p):
        return 1.0 if self.uniform() < p else 0.0
    def normal(self, mu, sd):
        # Box-Muller (one variate per call; discards the second)
        u1 = self.uniform()
        u2 = self.uniform()
        if u1 < 1e-12:
            u1 = 1e-12
        z = math.sqrt(-2.0 * math.log(u1)) * math.cos(2.0 * math.pi * u2)
        return mu + sd * z

def _base_to_int(base):
    # deterministic integer from the seed_base string (NO Python hash(): its
    # per-process randomization would break reproducibility). FNV-1a 64-bit.
    h = 0xcbf29ce484222325
    for ch in str(base).encode('utf-8'):
        h ^= ch
        h = (h * 0x100000001b3) & ((1 << 64) - 1)
    return h

_BASE_INT = None
def replicate_seed(base, idx):
    # deterministic 64-bit seed from (base, idx) via splitmix64 — reproducible
    # across processes (unlike Python's randomized hash()).
    global _BASE_INT
    if _BASE_INT is None:
        _BASE_INT = _base_to_int(base)
    h = (_BASE_INT + 0x9E3779B97F4A7C15 * (int(idx) + 1)) & ((1 << 64) - 1)
    h ^= (h >> 30); h = (h * 0xBF58476D1CE4E5B9) & ((1 << 64) - 1)
    h ^= (h >> 27); h = (h * 0x94D049BB133111EB) & ((1 << 64) - 1)
    h ^= (h >> 31)
    return h & ((1 << 64) - 1)

# ---- allocate the fixed per-cell sample sizes from the design assumptions ----
# n_pos / n_neg from prevalence; within each stratum split by allocation ratio.
def split_counts(n, prevalence, ratio):
    n_pos = int(round(n * prevalence))
    n_neg = n - n_pos
    def arm_split(m):
        n_exp = int(round(m * ratio / (ratio + 1.0)))
        return n_exp, m - n_exp
    pe, pc = arm_split(n_pos)
    ne, nc = arm_split(n_neg)
    return {('positive', 'experimental'): pe, ('positive', 'control'): pc,
            ('negative', 'experimental'): ne, ('negative', 'control'): nc}

def cell_counts_for(n):
    counts = split_counts(n, prev, alloc)
    # guard: every cell must have >=1 patient for the interaction test
    for k, v in counts.items():
        if v < 1:
            return None
    return counts

base_counts = cell_counts_for(n_total)
if base_counts is None:
    fail('n_total=%d with prevalence=%.3f / allocation=%.2f leaves an empty cell; '
         'increase n_total or adjust the design.' % (n_total, prev, alloc))

# ============================================================================
# GATE-3 INTERACTION on a simulated cohort (reuses gate3_interaction_test math)
# ----------------------------------------------------------------------------
# cohort_means: {(bm,arm): (n, mean, sumsq_dev)}  -> interaction estimate/se/p
# binary: risk-difference interaction, delta-method SE (sum of p(1-p)/n).
# continuous: mean-difference interaction, SE = sqrt(sum s^2/n).
# eff[bm] = oriented (experimental_mean - control_mean); interaction = eff+ - eff-.
# ----------------------------------------------------------------------------
def gate3_from_cells(cell_stats, outcome_type):
    eff = {}
    for bm in ('positive', 'negative'):
        m_exp = cell_stats[(bm, 'experimental')]['mean']
        m_ctl = cell_stats[(bm, 'control')]['mean']
        eff[bm] = orient(m_exp - m_ctl)
    interaction = eff['positive'] - eff['negative']
    var = 0.0
    if outcome_type == 'binary':
        for st in cell_stats.values():
            p = st['mean']; n = st['n']
            var += (p * (1 - p)) / n if n else 0.0
    else:
        for st in cell_stats.values():
            n = st['n']
            if n >= 2:
                s2 = st['ss'] / (n - 1)
                var += s2 / n
    se = math.sqrt(var) if var > 0 else float('nan')
    z = interaction / se if (se and se == se and se > 0) else 0.0
    p_int = two_sided_p(z)
    return interaction, se, p_int, eff

# ---- draw one replicate cohort deterministically & summarise per cell --------
def simulate_replicate(idx):
    rng = LCG(replicate_seed(seed_base, idx))
    stats = {}
    for (bm, arm), n in base_counts.items():
        spec_cell = cells[(bm, arm)]
        s = 0.0
        ss = 0.0            # sum of squared deviations (Welford-free two-pass avoided; store raw for var)
        vals = []
        if otype == 'binary':
            p = spec_cell['response_rate']
            for _ in range(n):
                vals.append(rng.bernoulli(p))
        else:
            mu = spec_cell['mean']; sd = spec_cell['sd']
            for _ in range(n):
                vals.append(rng.normal(mu, sd))
        m = sum(vals) / n
        ss = sum((v - m) ** 2 for v in vals)
        stats[(bm, arm)] = {'n': n, 'mean': m, 'ss': ss}
    return gate3_from_cells(stats, otype)

# ============================================================================
# RUN THE SIMULATION
# ----------------------------------------------------------------------------
reps = []
for i in range(n_sim):
    interaction, se, p_int, eff = simulate_replicate(i)
    significant = p_int < alpha
    meaningful  = abs(interaction) >= min_int
    reps.append({
        'replicate': i,
        'interaction': interaction,
        'se': se,
        'p_value': p_int,
        'eff_pos': eff['positive'],
        'eff_neg': eff['negative'],
        'significant': significant,
        'meaningful': meaningful,
        'detected': significant and meaningful,
    })

n_detected = sum(1 for r in reps if r['detected'])
power = n_detected / n_sim if n_sim else 0.0
ints = sorted(r['interaction'] for r in reps)
def pctile(sorted_vals, q):
    if not sorted_vals:
        return None
    idx = q * (len(sorted_vals) - 1)
    lo = int(math.floor(idx)); hi = int(math.ceil(idx))
    if lo == hi:
        return sorted_vals[lo]
    frac = idx - lo
    return sorted_vals[lo] * (1 - frac) + sorted_vals[hi] * frac
mean_int = sum(ints) / len(ints) if ints else 0.0
sd_int = math.sqrt(sum((x - mean_int) ** 2 for x in ints) / (len(ints) - 1)) if len(ints) > 1 else 0.0

# ---- % decisions changed (mean over replicates, marker-guided vs marker-blind)
# guided prefers experimental in a stratum iff its oriented benefit >= min_int;
# marker-blind gives everyone the on-average-better arm. decisions changed =
# patients whose guided arm differs from the blind arm.
changed_fracs = []
for r in reps:
    eff_pos = r['eff_pos']; eff_neg = r['eff_neg']
    # eff_pos/eff_neg are already oriented; main_eff = n-weighted mean of the oriented strata effects
    n_pos = base_counts[('positive', 'experimental')] + base_counts[('positive', 'control')]
    n_neg = base_counts[('negative', 'experimental')] + base_counts[('negative', 'control')]
    main_eff = (n_pos * eff_pos + n_neg * eff_neg) / (n_pos + n_neg)
    blind_exp = main_eff >= min_int
    changed = 0
    for bm, e, nbm in (('positive', eff_pos, n_pos), ('negative', eff_neg, n_neg)):
        guided_exp = e >= min_int
        if guided_exp != blind_exp:
            changed += nbm
    changed_fracs.append(100.0 * changed / n_total)
mean_pct_changed = round(sum(changed_fracs) / len(changed_fracs), 1) if changed_fracs else 0.0

# ============================================================================
# SAMPLE-SIZE SUGGESTION — smallest n (scaling the spec) reaching target power
# ----------------------------------------------------------------------------
# Scale n_total up/down (keeping prevalence & allocation & per-cell effects
# fixed), re-run a lighter simulation, and find the smallest n reaching
# target_power. Uses an analytic normal-approx as the search backbone, then
# confirms by simulation at the chosen n. If the effect is null, no n reaches
# power (reported as 'not achievable — no predictive signal in the spec').
# ----------------------------------------------------------------------------
# Expected (true) interaction from the spec cells:
def true_effect_cell(bm, arm):
    c = cells[(bm, arm)]
    return c['response_rate'] if otype == 'binary' else c['mean']
true_eff_pos = orient(true_effect_cell('positive', 'experimental') - true_effect_cell('positive', 'control'))
true_eff_neg = orient(true_effect_cell('negative', 'experimental') - true_effect_cell('negative', 'control'))
true_interaction = true_eff_pos - true_eff_neg

# per-patient variance contribution per cell (so SE at size n scales as 1/sqrt)
def cell_unit_var(bm, arm):
    c = cells[(bm, arm)]
    if otype == 'binary':
        p = c['response_rate']; return p * (1 - p)
    return c['sd'] ** 2
# fraction of n in each cell (fixed by prevalence & allocation)
frac = {k: v / float(n_total) for k, v in base_counts.items()}

def analytic_power_at(n):
    # var(interaction) = sum_cells unit_var / n_cell ; n_cell = frac*n
    var = 0.0
    ok = True
    for (bm, arm) in need_cells:
        ncell = frac[(bm, arm)] * n
        if ncell < 1:
            ok = False
            break
        var += cell_unit_var(bm, arm) / ncell
    if not ok or var <= 0:
        return 0.0
    se = math.sqrt(var)
    if abs(true_interaction) < min_int:
        return alpha  # not meaningful -> power collapses toward alpha
    # two-sided z-test power at effect = true_interaction
    zc = 1.959964
    ncp = abs(true_interaction) / se
    return 1.0 - norm_cdf(zc - ncp) + norm_cdf(-zc - ncp)

sample_size_suggestion = None
if abs(true_interaction) < min_int:
    sample_size_suggestion = {
        'achievable': False,
        'reason': 'the spec encodes no meaningful biomarker x treatment interaction '
                  '(|true interaction| < min_interaction), so no sample size reaches the '
                  'power target — the biomarker is not predicted to be predictive.',
        'target_power': target_pow,
    }
else:
    # search n in a generous grid; confirm the analytic pick by simulation
    n_star_analytic = None
    n_probe = max(8, int(n_total * 0.25))
    n_cap = max(n_total * 20, 4000)
    step = max(4, int(n_total * 0.05))
    n = n_probe
    while n <= n_cap:
        if analytic_power_at(n) >= target_pow:
            n_star_analytic = n
            break
        n += step
    sample_size_suggestion = {
        'achievable': n_star_analytic is not None,
        'target_power': target_pow,
        'n_suggested': n_star_analytic,
        'true_interaction_assumed': round(true_interaction, 4),
        'method': 'normal-approximation interaction power, effect & variance from the spec cells',
        'note': 'analytic estimate; confirm with a full n_sim simulation at the chosen n.',
    }
    if n_star_analytic is None:
        sample_size_suggestion['reason'] = ('target power not reached within %dx the spec n_total' % 20)

# ============================================================================
# VERDICT
# ----------------------------------------------------------------------------
if power >= target_pow:
    verdict = 'PREDICTED TO PASS GATE-3'
    verdict_note = ('At the spec design (n_total=%d, prevalence=%.2f, allocation=%.2f), the '
                    'biomarker is PREDICTED to clear gate-3 with power %.1f%% (fraction of %d '
                    'simulated trials showing a significant, meaningful biomarker x treatment '
                    'interaction). SIMULATED result — advance to the real RCT with this design.'
                    % (n_total, prev, alloc, 100 * power, n_sim))
elif abs(true_interaction) < min_int:
    verdict = 'NOT PREDICTED TO BE PREDICTIVE'
    verdict_note = ('The spec encodes essentially no differential treatment benefit by biomarker '
                    'status (true interaction %.3f < min_interaction %.2f). Power is at the null '
                    'floor (~alpha). The biomarker is NOT predicted to be predictive at any sample '
                    'size — this is the PROFILE failure mode. SIMULATED design finding.'
                    % (true_interaction, min_int))
else:
    verdict = 'UNDER-POWERED AT THIS DESIGN'
    suggested = sample_size_suggestion.get('n_suggested') if sample_size_suggestion else None
    verdict_note = ('A real interaction is specified (%.3f) but the design is UNDER-POWERED: '
                    'only %.1f%% power at n_total=%d (< target %.0f%%). %s SIMULATED design finding.'
                    % (true_interaction, 100 * power, n_total, 100 * target_pow,
                       ('Suggested n_total ~= %d for %.0f%% power.' % (suggested, 100 * target_pow))
                       if suggested else 'No feasible sample size found within the search range.'))

# ============================================================================
# OUTPUTS
# ----------------------------------------------------------------------------
result = {
    'status': 'completed',
    'result_class': 'SIMULATED / PREDICTED — trial-design power simulation, NOT clinical evidence',
    'analysis': analysis,
    'outcome_type': otype,
    'design': {
        'n_total': n_total,
        'biomarker_prevalence': prev,
        'allocation_ratio': alloc,
        'cell_sizes': {f'{b}/{a}': base_counts[(b, a)] for (b, a) in need_cells},
        'spec_cells': {f'{b}/{a}': cells[(b, a)] for (b, a) in need_cells},
    },
    'simulation': {
        'n_sim': n_sim,
        'seed_base': seed_base,
        'deterministic': True,
    },
    'true_interaction_from_spec': round(true_interaction, 4),
    'predicted_interaction': {
        'mean': round(mean_int, 4),
        'sd': round(sd_int, 4),
        'ci95_empirical': [round(pctile(ints, 0.025), 4), round(pctile(ints, 0.975), 4)],
        'median': round(pctile(ints, 0.5), 4),
        'scale': 'risk difference' if otype == 'binary' else 'mean difference',
    },
    'power': round(power, 4),
    'n_detected': n_detected,
    'expected_decisions_changed_pct': mean_pct_changed,
    'sample_size_suggestion': sample_size_suggestion,
    'thresholds': {'alpha': alpha, 'min_interaction': min_int,
                   'target_power': target_pow, 'higher_is_better': hib},
    'gate3_verdict': verdict,
    'verdict_note': verdict_note,
}
with open('virtual_trial_results.json', 'w') as f:
    json.dump(result, f, indent=2)

# ---- per-replicate CSV -------------------------------------------------------
with open('simulation_replicates.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['replicate', 'interaction', 'se', 'p_value',
                'eff_biomarker_pos', 'eff_biomarker_neg', 'significant', 'meaningful', 'detected'])
    for r in reps:
        w.writerow([r['replicate'], round(r['interaction'], 6),
                    round(r['se'], 6) if r['se'] == r['se'] else '',
                    round(r['p_value'], 6), round(r['eff_pos'], 6), round(r['eff_neg'], 6),
                    'YES' if r['significant'] else '', 'YES' if r['meaningful'] else '',
                    'YES' if r['detected'] else ''])

# ---- markdown power report ---------------------------------------------------
def fmt(x): return '—' if x is None else (f'{x:.3f}' if isinstance(x, float) else str(x))
L = []
L.append('# Virtual Trial — Gate-3 Power Simulation')
L.append('')
L.append('> **SIMULATION — DESIGN TOOL, NOT CLINICAL EVIDENCE.** Every number below is '
         'PREDICTED from the user-supplied design assumptions (the parameter spec), not '
         'observed in patients. Its purpose is to SIZE and DE-RISK a real biomarker x '
         'treatment interaction RCT before it is run. Do not cite as trial evidence.')
L.append('')
L.append(f'**Analysis:** {analysis}  |  **Outcome:** {otype}  |  '
         f'**Replicates simulated:** {n_sim} (deterministic, seed_base=`{seed_base}`)')
L.append('')
L.append(f'**Verdict:** **{verdict}**')
L.append('')
L.append(verdict_note)
L.append('')
L.append('## Design assumptions (from the spec)')
L.append('')
L.append(f'- **n_total:** {n_total}  |  **biomarker prevalence:** {prev:.2f}  |  '
         f'**allocation (exp:ctl):** {alloc:.2f}')
L.append('')
L.append('| Cell | Planned n | Assumed outcome |')
L.append('|------|----------:|-----------------|')
for (b, a) in need_cells:
    c = cells[(b, a)]
    if otype == 'binary':
        oc = f"response rate {c['response_rate']:.3f}"
    else:
        oc = f"mean {c['mean']:.3f}, sd {c['sd']:.3f}"
    L.append(f"| biomarker {'+' if b == 'positive' else '−'} / {a} | {base_counts[(b, a)]} | {oc} |")
L.append('')
L.append('## Predicted interaction & power')
L.append('')
L.append(f'- **True interaction encoded by the spec:** {fmt(true_interaction)} '
         f'({"risk difference" if otype == "binary" else "mean difference"})')
L.append(f'- **Simulated mean interaction:** {fmt(mean_int)} (sd {fmt(sd_int)})')
L.append(f'- **Empirical 95% interval across replicates:** '
         f'[{fmt(pctile(ints, 0.025))}, {fmt(pctile(ints, 0.975))}]')
L.append(f'- **POWER to detect a significant + meaningful interaction:** '
         f'**{100 * power:.1f}%** ({n_detected}/{n_sim} replicates)')
L.append(f'  (significance: p < {alpha}; meaningful: |interaction| ≥ {min_int})')
L.append(f'- **Expected decisions changed vs marker-blind:** {mean_pct_changed:.1f}% of patients')
L.append('')
L.append('## Sample-size suggestion')
L.append('')
ss = sample_size_suggestion or {}
if ss.get('achievable') and ss.get('n_suggested'):
    L.append(f"To reach **{100 * target_pow:.0f}% power** at the spec's effect sizes, enrol "
             f"**~{ss['n_suggested']} total** (prevalence & allocation held fixed). "
             f"_{ss.get('note', '')}_")
elif ss.get('achievable') is False:
    L.append(f"_{ss.get('reason', 'No sample size reaches the power target for this spec.')}_")
else:
    L.append('_Sample-size suggestion unavailable._')
L.append('')
L.append('## Method')
L.append('')
L.append('For each of the replicate virtual trials, patient outcomes are drawn '
         'DETERMINISTICALLY from the spec (binomial for binary, Box–Muller normal for '
         'continuous) using a seedable stdlib LCG whose seed is a deterministic function of '
         '`seed_base` and the replicate index — so two runs with identical parameters are '
         'byte-identical. Each cohort is then run through the SAME biomarker × treatment '
         'interaction test used by `gate3_interaction_test` (binary: risk-difference '
         'interaction with delta-method SE; continuous: mean-difference interaction). Power '
         'is the fraction of replicates with a significant AND meaningful interaction.')
L.append('')
L.append('_Framework: FDA–NIH BEST (predictive vs prognostic biomarkers); in-silico trials / '
         'Model-Informed Drug Development (MIDD); interaction-test power (Brookes 2001)._')
L.append('')
L.append('**Reminder: SIMULATED / PREDICTED — a design tool to size the real trial, not evidence.**')
with open('power_report.md', 'w') as f:
    f.write('\\n'.join(L) + '\\n')

# ---- console summary ---------------------------------------------------------
print('=== VIRTUAL GATE-3: %s | n_sim=%d | true_int=%.3f | power=%.1f%% | %s ===' % (
    analysis, n_sim, true_interaction, 100 * power, verdict))

with open('versions.yml', 'w') as f:
    f.write('virtual_trial_gate3:\\n')
    f.write('  python: "3.10"\\n')
    f.write('  method: "deterministic virtual-trial power simulation of the gate-3 interaction test"\\n')
    f.write('  basis: "FDA-NIH BEST; MIDD/in-silico trials; interaction power (Brookes 2001)"\\n')
PYEOF
    """
}

workflow VIRTUAL_TRIAL_GATE3_WORKFLOW {
    take: meta_ch
    main: VIRTUAL_TRIAL_GATE3(meta_ch)
    emit:
        results    = VIRTUAL_TRIAL_GATE3.out.results
        report     = VIRTUAL_TRIAL_GATE3.out.report
        replicates = VIRTUAL_TRIAL_GATE3.out.replicates
}

workflow {
    meta = [id: 'virtual_trial_gate3_run', single_end: false]
    Channel.value(meta) | VIRTUAL_TRIAL_GATE3_WORKFLOW
}
