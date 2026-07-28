#!/usr/bin/env nextflow
/*
 * biostatistics/qsp_virtual_population
 *
 * QSP VIRTUAL-PATIENT POPULATION GENERATOR — the "real cohort -> virtual
 * population -> gate-3" bridge.
 *
 * The mature, MIDD-endorsed way to generate biomarker-stratified response
 * hypotheses and de-risk a trial BEFORE running it is a QSP virtual-patient
 * population: sample a plausible population from a REAL cohort's covariate
 * structure, then push each virtual patient through a mechanistic RESPONSE
 * MODEL to get their outcome. This tool does exactly that and emits the cohort
 * in the gate-3 schema (patient_id, biomarker, treatment, outcome, + covariates)
 * so it can be fed straight into biostatistics/virtual_trial_gate3 /
 * gate3_interaction_test.
 *
 * It combines TWO user-provided, REAL inputs — it invents NEITHER:
 *
 *   1. covariate_file  A REAL cohort's covariate distribution SUMMARY (per
 *      covariate: name, type, and mean+sd for continuous OR category:frequency
 *      for categorical). This GROUNDS the virtual population in a real cohort's
 *      structure. The tool does NOT fabricate distributions — if this is
 *      missing it FAILS FAST (exit 1).
 *
 *   2. model_file      A user-provided mechanistic RESPONSE MODEL spec: an
 *      intercept + coefficients for covariates, biomarker, treatment and the
 *      biomarker x treatment INTERACTION term, plus outcome_type
 *      (binary|continuous) and (for continuous) a residual noise sd. This is
 *      the mechanistic ASSUMPTION the user is testing — the tool NEVER
 *      fabricates coefficients. Missing -> FAIL FAST (exit 1).
 *
 * Everything emitted is SIMULATED — grounded in the real cohort's covariate
 * structure and the user's mechanistic model, but NOT real patient data. The
 * report is labelled as such. This is a legitimate QSP virtual population; it
 * is NOT a synthetic-data fallback for the INPUTS: both real inputs are
 * required and no distribution or coefficient is ever invented.
 *
 * Method (all DETERMINISTIC — a seedable stdlib LCG whose seed derives from
 * seed_base via FNV-1a + splitmix64; NO Python hash()/random module/wall-clock):
 *   1. Sample N virtual patients' covariates from the cohort summary
 *      (Box-Muller normal for continuous; inverse-CDF categorical draw).
 *   2. Assign biomarker status by biomarker_prevalence and treatment arm by
 *      allocation_ratio.
 *   3. Compute the linear predictor from the model (intercept + covariate betas
 *      + biomarker + treatment + biomarker*treatment interaction), then draw the
 *      outcome: logistic -> Bernoulli for binary; linear + gaussian noise for
 *      continuous.
 *   4. Emit the virtual cohort in the gate-3 schema.
 *
 * References: quantitative-systems-pharmacology virtual populations
 * (Allen/Rieger/Musante, CPT:PSP 2016, plausible-population + prevalence-
 * weighting method); a PRECISESADS-style mechanistic QSP model of a
 * stratified autoimmune (lupus/SADS) response as the class of user response
 * model this consumes; MIDD / ICH M15 model-informed drug development and
 * general model-informed evidence.
 *
 * INPUT (both REQUIRED): --covariate_file, --model_file. Either missing ->
 *   failed JSON + exit(1).
 * OUTPUT: virtual_population.csv (patient_id, biomarker, treatment, outcome,
 *   + covariates), qsp_population_results.json, qsp_population_report.md,
 *   versions.yml
 */

nextflow.enable.dsl = 2

params.outdir             = './results'
params.covariate_file     = 'NONE'        // REQUIRED: real cohort covariate distribution summary (CSV or JSON)
params.model_file         = 'NONE'        // REQUIRED: user mechanistic response-model spec (CSV or JSON)
params.analysis           = 'QSP virtual-patient population'
params.n_patients         = '400'         // number of virtual patients to generate
params.biomarker_prevalence = '0.4'       // P(biomarker+) in the virtual population
params.allocation_ratio   = '1.0'         // experimental:control (1.0 = 1:1)
params.seed_base          = '20260101'    // deterministic base seed; patient seeds = f(seed_base, index)

process QSP_VIRTUAL_POPULATION {
    tag "$meta.id"
    label 'process_low'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("qsp_population_results.json"), emit: results
    tuple val(meta), path("virtual_population.csv"),      emit: population
    tuple val(meta), path("qsp_population_report.md"),    emit: report
    path "versions.yml",                                  emit: versions

    script:
    """
    export PARAM_COVARIATE='${params.covariate_file}'
    export PARAM_MODEL='${params.model_file}'
    export PARAM_ANALYSIS='${params.analysis.toString().replace("'", "'\\''")}'
    export PARAM_N_PATIENTS='${params.n_patients}'
    export PARAM_BM_PREV='${params.biomarker_prevalence}'
    export PARAM_ALLOC='${params.allocation_ratio}'
    export PARAM_SEED_BASE='${params.seed_base}'

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

# ------------------------------------------------------------------- params ---
analysis   = os.environ.get('PARAM_ANALYSIS', 'QSP virtual-patient population')
n_patients = _i(os.environ.get('PARAM_N_PATIENTS'), 400)
bm_prev    = _f(os.environ.get('PARAM_BM_PREV'), 0.4)
alloc      = _f(os.environ.get('PARAM_ALLOC'), 1.0)
seed_base  = os.environ.get('PARAM_SEED_BASE', '20260101')
if alloc is None or alloc <= 0:
    alloc = 1.0

# -------------------------------------------------------- fail-fast handler ---
def fail(msg):
    with open('qsp_population_results.json', 'w') as f:
        json.dump({'status': 'failed', 'error': msg,
                   'note': 'QSP virtual-population generator — requires BOTH a real cohort '
                           'covariate summary and a user mechanistic response model; it '
                           'invents neither distributions nor coefficients'}, f, indent=2)
    with open('virtual_population.csv', 'w') as f:
        f.write('patient_id,biomarker,treatment,outcome\\n')
    with open('qsp_population_report.md', 'w') as f:
        f.write('# QSP virtual-patient population — FAILED\\n\\n%s\\n' % msg)
    with open('versions.yml', 'w') as f:
        f.write('qsp_virtual_population:\\n  status: "failed"\\n')
    sys.exit(1)

# ============================================================================
# DETERMINISTIC PRNG — seedable, stdlib only (NO random module, NO time, NO hash())
# ----------------------------------------------------------------------------
# 64-bit LCG (Numerical Recipes constants). One global stream seeded from a
# deterministic function of seed_base, so two runs with identical params produce
# byte-identical output.
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
        return 1 if self.uniform() < p else 0
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

def splitmix64(x):
    # deterministic 64-bit mix (reproducible across processes)
    x = (x + 0x9E3779B97F4A7C15) & ((1 << 64) - 1)
    x ^= (x >> 30); x = (x * 0xBF58476D1CE4E5B9) & ((1 << 64) - 1)
    x ^= (x >> 27); x = (x * 0x94D049BB133111EB) & ((1 << 64) - 1)
    x ^= (x >> 31)
    return x & ((1 << 64) - 1)

# single deterministic stream seeded from seed_base
rng = LCG(splitmix64(_base_to_int(seed_base)))

def sigmoid(x):
    # numerically stable logistic
    if x >= 0:
        z = math.exp(-x)
        return 1.0 / (1.0 + z)
    z = math.exp(x)
    return z / (1.0 + z)

# ============================================================================
# LOAD THE REAL COHORT COVARIATE SUMMARY  (grounds the population; never invented)
# ----------------------------------------------------------------------------
# Accepted shapes:
#
# JSON:
#   {"covariates": [
#      {"name": "age",  "type": "continuous",  "mean": 42.0, "sd": 12.0},
#      {"name": "sex",  "type": "categorical", "categories": {"F": 0.66, "M": 0.34}}
#   ]}
#
# CSV (one row per covariate; categorical categories as "cat:freq;cat:freq"):
#   name,type,mean,sd,categories
#   age,continuous,42.0,12.0,
#   sex,categorical,,,F:0.66;M:0.34
# ----------------------------------------------------------------------------
cov_path = os.environ.get('PARAM_COVARIATE', 'NONE')
if (not cov_path) or cov_path in ('NONE', '') or not os.path.exists(cov_path):
    fail('--covariate_file is required: a REAL cohort covariate distribution summary '
         '(per covariate: name, type=continuous|categorical, and mean+sd OR '
         'category:frequency). This grounds the virtual population in a real cohort; '
         'no distribution is ever invented.')

def _parse_categories(s):
    # "F:0.66;M:0.34" -> {'F':0.66,'M':0.34}
    out = {}
    if not s:
        return out
    for part in str(s).replace(',', ';').split(';'):
        part = part.strip()
        if not part or ':' not in part:
            continue
        k, v = part.rsplit(':', 1)
        fv = _f(v)
        if fv is not None:
            out[k.strip()] = fv
    return out

covariates = []   # list of dicts: {name,type,mean,sd} or {name,type,categories}
if cov_path.lower().endswith('.json'):
    with open(cov_path) as fh:
        cdata = json.load(fh)
    clist = cdata.get('covariates') if isinstance(cdata, dict) else cdata
    if not isinstance(clist, list):
        fail('covariate_file JSON must have a "covariates" list')
    for c in clist:
        name = str(c.get('name') or '').strip()
        ctype = str(c.get('type') or '').strip().lower()
        if not name or ctype not in ('continuous', 'categorical'):
            continue
        if ctype == 'continuous':
            mean = _f(c.get('mean')); sd = _f(c.get('sd'))
            covariates.append({'name': name, 'type': 'continuous', 'mean': mean, 'sd': sd})
        else:
            cats = c.get('categories') or {}
            if isinstance(cats, str):
                cats = _parse_categories(cats)
            cats = {str(k): _f(v) for k, v in cats.items() if _f(v) is not None}
            covariates.append({'name': name, 'type': 'categorical', 'categories': cats})
else:
    with open(cov_path, newline='') as fh:
        rows = list(csv.DictReader(fh))
    def gv(row, *names):
        for n in names:
            for k in row:
                if k.strip().lower() == n:
                    return row[k]
        return None
    for r in rows:
        name = gv(r, 'name', 'covariate', 'variable')
        ctype = (gv(r, 'type', 'kind') or '').strip().lower()
        if not name or not name.strip():
            continue
        name = name.strip()
        if ctype in ('categorical', 'cat', 'factor', 'discrete'):
            cats = _parse_categories(gv(r, 'categories', 'levels', 'cats'))
            covariates.append({'name': name, 'type': 'categorical', 'categories': cats})
        else:
            mean = _f(gv(r, 'mean', 'mu')); sd = _f(gv(r, 'sd', 'stdev', 'std', 'sigma'))
            covariates.append({'name': name, 'type': 'continuous', 'mean': mean, 'sd': sd})

if not covariates:
    fail('covariate_file parsed to zero usable covariates (need name + type + '
         'mean/sd or category:frequency)')

# validate each covariate has usable distribution params
for c in covariates:
    if c['type'] == 'continuous':
        if c.get('mean') is None or c.get('sd') is None or c['sd'] < 0:
            fail('continuous covariate %r needs mean and sd>=0' % c['name'])
    else:
        cats = c.get('categories') or {}
        tot = sum(cats.values())
        if not cats or tot <= 0:
            fail('categorical covariate %r needs at least one category:frequency' % c['name'])
        # normalise frequencies to a proper distribution
        c['categories'] = {k: v / tot for k, v in cats.items()}

cov_names = [c['name'] for c in covariates]

# ============================================================================
# LOAD THE USER MECHANISTIC RESPONSE MODEL  (the assumption; never fabricated)
# ----------------------------------------------------------------------------
# Accepted shapes:
#
# JSON:
#   {"outcome_type": "binary",       # binary | continuous
#    "intercept": -1.0,
#    "noise_sd": 2.0,                 # continuous only (residual sd)
#    "biomarker_coef": 0.0,
#    "treatment_coef": 0.3,
#    "interaction_coef": 2.5,         # biomarker x treatment  (the predictive term)
#    "covariate_coefs": {"age": 0.02, "sex_M": 0.4}}
#
# CSV (one row per term):
#   term,coefficient
#   outcome_type,binary            # special rows: outcome_type, noise_sd
#   intercept,-1.0
#   biomarker,0.0
#   treatment,0.3
#   interaction,2.5
#   age,0.02
#   sex_M,0.4
#
# Encoding used for the linear predictor:
#   biomarker = 1 for biomarker+, 0 for biomarker-
#   treatment = 1 for experimental, 0 for control
#   continuous covariate contributes coef * value
#   categorical covariate "name" with level L contributes coef keyed "name_L"
#     (one-hot; the reference level simply has no coefficient -> 0)
# ----------------------------------------------------------------------------
model_path = os.environ.get('PARAM_MODEL', 'NONE')
if (not model_path) or model_path in ('NONE', '') or not os.path.exists(model_path):
    fail('--model_file is required: a user-provided mechanistic response-model spec '
         '(intercept + coefficients for covariates, biomarker, treatment and the '
         'biomarker x treatment interaction; outcome_type binary|continuous; noise_sd '
         'for continuous). The mechanistic assumption comes from the user; no '
         'coefficient is ever fabricated.')

model = {
    'outcome_type': None,
    'intercept': 0.0,
    'noise_sd': 1.0,
    'biomarker_coef': 0.0,
    'treatment_coef': 0.0,
    'interaction_coef': 0.0,
    'covariate_coefs': {},
}

_reserved = {'outcome_type', 'intercept', 'noise_sd', 'biomarker', 'biomarker_coef',
             'treatment', 'treatment_coef', 'interaction', 'interaction_coef'}

if model_path.lower().endswith('.json'):
    with open(model_path) as fh:
        m = json.load(fh)
    model['outcome_type']    = (m.get('outcome_type') or '').strip().lower() or None
    model['intercept']       = _f(m.get('intercept'), 0.0)
    model['noise_sd']        = _f(m.get('noise_sd'), 1.0)
    model['biomarker_coef']  = _f(m.get('biomarker_coef', m.get('biomarker')), 0.0)
    model['treatment_coef']  = _f(m.get('treatment_coef', m.get('treatment')), 0.0)
    model['interaction_coef'] = _f(m.get('interaction_coef', m.get('interaction')), 0.0)
    cc = m.get('covariate_coefs') or {}
    for k, v in cc.items():
        fv = _f(v)
        if fv is not None:
            model['covariate_coefs'][str(k)] = fv
else:
    with open(model_path, newline='') as fh:
        rows = list(csv.DictReader(fh))
    if not rows:
        fail('model_file (CSV) has no rows')
    def gv(row, *names):
        for n in names:
            for k in row:
                if k.strip().lower() == n:
                    return row[k]
        return None
    for r in rows:
        term = (gv(r, 'term', 'name', 'parameter') or '').strip()
        if not term:
            continue
        raw = gv(r, 'coefficient', 'coef', 'value', 'beta')
        tl = term.lower()
        if tl == 'outcome_type':
            model['outcome_type'] = (str(raw).strip().lower() or None)
        elif tl == 'noise_sd':
            model['noise_sd'] = _f(raw, 1.0)
        elif tl == 'intercept':
            model['intercept'] = _f(raw, 0.0)
        elif tl in ('biomarker', 'biomarker_coef'):
            model['biomarker_coef'] = _f(raw, 0.0)
        elif tl in ('treatment', 'treatment_coef'):
            model['treatment_coef'] = _f(raw, 0.0)
        elif tl in ('interaction', 'interaction_coef'):
            model['interaction_coef'] = _f(raw, 0.0)
        else:
            fv = _f(raw)
            if fv is not None:
                model['covariate_coefs'][term] = fv

otype = model['outcome_type']
if otype not in ('binary', 'continuous'):
    fail('model outcome_type must be binary or continuous (got %r)' % otype)
if otype == 'continuous':
    if model['noise_sd'] is None or model['noise_sd'] <= 0:
        fail('continuous model needs noise_sd > 0 (got %r)' % model['noise_sd'])

# ============================================================================
# GENERATE THE VIRTUAL POPULATION
# ----------------------------------------------------------------------------
# Deterministic per-patient covariate draw from the real cohort summary, then
# outcome from the user's mechanistic model. Biomarker by prevalence; treatment
# by allocation.
# ----------------------------------------------------------------------------
if n_patients is None or n_patients < 4:
    fail('n_patients must be >= 4 (got %r)' % n_patients)
if bm_prev is None or not (0.0 <= bm_prev <= 1.0):
    fail('biomarker_prevalence must be in [0,1] (got %r)' % bm_prev)

# treatment probability from allocation ratio (experimental:control)
p_exp = alloc / (alloc + 1.0)

def draw_categorical(cats):
    # inverse-CDF draw over {level: prob}
    u = rng.uniform()
    cum = 0.0
    last = None
    for level, prob in cats.items():
        cum += prob
        last = level
        if u < cum:
            return level
    return last

def draw_covariates():
    vals = {}
    for c in covariates:
        if c['type'] == 'continuous':
            vals[c['name']] = rng.normal(c['mean'], c['sd'])
        else:
            vals[c['name']] = draw_categorical(c['categories'])
    return vals

def linear_predictor(cov_vals, biomarker, treatment):
    lp = model['intercept']
    lp += model['biomarker_coef'] * biomarker
    lp += model['treatment_coef'] * treatment
    lp += model['interaction_coef'] * biomarker * treatment
    for c in covariates:
        v = cov_vals[c['name']]
        if c['type'] == 'continuous':
            beta = model['covariate_coefs'].get(c['name'])
            if beta is not None:
                lp += beta * v
        else:
            # one-hot: coefficient keyed "name_level"; reference level -> 0
            beta = model['covariate_coefs'].get('%s_%s' % (c['name'], v))
            if beta is not None:
                lp += beta
    return lp

patients = []
for idx in range(n_patients):
    cov_vals = draw_covariates()
    biomarker = 1 if rng.uniform() < bm_prev else 0
    treatment = 1 if rng.uniform() < p_exp else 0
    lp = linear_predictor(cov_vals, biomarker, treatment)
    if otype == 'binary':
        pr = sigmoid(lp)
        outcome = rng.bernoulli(pr)
    else:
        outcome = lp + rng.normal(0.0, model['noise_sd'])
    patients.append({
        'patient_id': 'VP%05d' % (idx + 1),
        'biomarker': biomarker,
        'treatment': treatment,
        'outcome': outcome,
        'covariates': cov_vals,
    })

# ============================================================================
# PER-STRATUM SUMMARY  (so the interaction is visible before gate-3)
# ----------------------------------------------------------------------------
# cell (biomarker, treatment) -> outcome rate (binary) or mean (continuous)
# ----------------------------------------------------------------------------
def cell_key(bm, tx):
    return '%s/%s' % ('bm+' if bm else 'bm-', 'exp' if tx else 'ctl')

strata = {}
for p in patients:
    k = cell_key(p['biomarker'], p['treatment'])
    d = strata.setdefault(k, {'n': 0, 'sum': 0.0})
    d['n'] += 1
    d['sum'] += p['outcome']

stratum_stats = {}
for k, d in strata.items():
    rate = (d['sum'] / d['n']) if d['n'] else None
    stratum_stats[k] = {'n': d['n'],
                        ('rate' if otype == 'binary' else 'mean'): round(rate, 4) if rate is not None else None}

# observed interaction (effect in bm+ minus effect in bm-), oriented by treatment
def _val(k):
    s = stratum_stats.get(k)
    if not s:
        return None
    return s.get('rate', s.get('mean'))

pe, pc = _val('bm+/exp'), _val('bm+/ctl')
ne, nc = _val('bm-/exp'), _val('bm-/ctl')
eff_pos = (pe - pc) if (pe is not None and pc is not None) else None
eff_neg = (ne - nc) if (ne is not None and nc is not None) else None
observed_interaction = (eff_pos - eff_neg) if (eff_pos is not None and eff_neg is not None) else None

# ============================================================================
# OUTPUTS
# ----------------------------------------------------------------------------
# gate-3 schema: patient_id, biomarker, treatment, outcome (+ covariates).
# biomarker/treatment emitted as positive/negative & experimental/control so
# gate3_interaction_test / virtual_trial_gate3 normalisers accept them directly.
# ----------------------------------------------------------------------------
def bm_label(b):
    return 'positive' if b else 'negative'
def tx_label(t):
    return 'experimental' if t else 'control'

def fmt_outcome(v):
    if otype == 'binary':
        return int(v)
    return round(v, 6)

with open('virtual_population.csv', 'w', newline='') as fh:
    w = csv.writer(fh)
    w.writerow(['patient_id', 'biomarker', 'treatment', 'outcome'] + cov_names)
    for p in patients:
        row = [p['patient_id'], bm_label(p['biomarker']), tx_label(p['treatment']),
               fmt_outcome(p['outcome'])]
        for name in cov_names:
            v = p['covariates'][name]
            row.append(round(v, 6) if isinstance(v, float) else v)
        w.writerow(row)

model_summary = {
    'outcome_type': otype,
    'intercept': model['intercept'],
    'biomarker_coef': model['biomarker_coef'],
    'treatment_coef': model['treatment_coef'],
    'interaction_coef': model['interaction_coef'],
    'covariate_coefs': model['covariate_coefs'],
    'noise_sd': model['noise_sd'] if otype == 'continuous' else None,
}

results = {
    'status': 'completed',
    'result_class': 'SIMULATED — QSP virtual population grounded in a real cohort covariate '
                    'summary + a user mechanistic response model; NOT real patient data',
    'analysis': analysis,
    'outcome_type': otype,
    'n_patients': len(patients),
    'biomarker_prevalence_target': bm_prev,
    'allocation_ratio': alloc,
    'seed_base': seed_base,
    'deterministic': True,
    'covariate_source': os.path.basename(cov_path),
    'covariates_used': cov_names,
    'model_source': os.path.basename(model_path),
    'model': model_summary,
    'per_stratum': stratum_stats,
    'observed_effect': {
        'metric': 'risk difference' if otype == 'binary' else 'mean difference',
        'effect_biomarker_pos': round(eff_pos, 4) if eff_pos is not None else None,
        'effect_biomarker_neg': round(eff_neg, 4) if eff_neg is not None else None,
        'observed_interaction': round(observed_interaction, 4) if observed_interaction is not None else None,
    },
    'gate3_schema': ['patient_id', 'biomarker', 'treatment', 'outcome'],
    'downstream': 'feed virtual_population.csv to biostatistics/virtual_trial_gate3 / '
                  'gate3_interaction_test',
}
with open('qsp_population_results.json', 'w') as fh:
    json.dump(results, fh, indent=2)

# ---- markdown report ---------------------------------------------------------
def fmt(x):
    return '—' if x is None else (f'{x:.4f}' if isinstance(x, float) else str(x))

L = []
L.append('# QSP Virtual-Patient Population')
L.append('')
L.append('> **SIMULATED — NOT REAL PATIENT DATA.** Every virtual patient below is '
         'generated by sampling covariates from the REAL cohort\\'s covariate-distribution '
         'summary (`%s`) and computing the outcome from the USER-SUPPLIED mechanistic '
         'response model (`%s`). It is grounded in a real cohort\\'s structure and a '
         'user\\'s mechanistic assumption; it is NOT observed clinical data. Its purpose '
         'is to generate biomarker-stratified response hypotheses and de-risk a trial '
         'BEFORE it is run.' % (os.path.basename(cov_path), os.path.basename(model_path)))
L.append('')
L.append(f'**Analysis:** {analysis}  |  **Outcome:** {otype}  |  '
         f'**Virtual patients:** {len(patients)} (deterministic, seed_base=`{seed_base}`)')
L.append('')
L.append('## Grounding inputs')
L.append('')
L.append(f'- **Cohort covariate summary (real):** `{os.path.basename(cov_path)}` — '
         f'{len(covariates)} covariate(s): {", ".join(cov_names)}')
L.append(f'- **Mechanistic response model (user):** `{os.path.basename(model_path)}`')
L.append('')
L.append('| Model term | Coefficient |')
L.append('|------------|------------:|')
L.append(f'| intercept | {fmt(model["intercept"])} |')
L.append(f'| biomarker | {fmt(model["biomarker_coef"])} |')
L.append(f'| treatment | {fmt(model["treatment_coef"])} |')
L.append(f'| biomarker x treatment (interaction) | {fmt(model["interaction_coef"])} |')
for k, v in model['covariate_coefs'].items():
    L.append(f'| {k} | {fmt(v)} |')
if otype == 'continuous':
    L.append(f'| residual noise sd | {fmt(model["noise_sd"])} |')
L.append('')
L.append(f'- **biomarker prevalence (target):** {bm_prev:.2f}  |  '
         f'**allocation (exp:ctl):** {alloc:.2f}')
L.append('')
L.append('## Per-stratum outcome (the interaction, visible before gate-3)')
L.append('')
metric = 'response rate' if otype == 'binary' else 'mean outcome'
L.append(f'| Stratum | n | {metric} |')
L.append('|---------|--:|----------:|')
for k in ('bm+/exp', 'bm+/ctl', 'bm-/exp', 'bm-/ctl'):
    s = stratum_stats.get(k)
    if s:
        val = s.get('rate', s.get('mean'))
        L.append(f'| {k} | {s["n"]} | {fmt(val)} |')
L.append('')
L.append(f'- **Treatment effect in biomarker+ ({"risk diff" if otype == "binary" else "mean diff"}):** '
         f'{fmt(eff_pos)}')
L.append(f'- **Treatment effect in biomarker−:** {fmt(eff_neg)}')
L.append(f'- **Observed biomarker x treatment interaction:** **{fmt(observed_interaction)}** '
         f'(effect in bm+ minus effect in bm−)')
L.append('')
if observed_interaction is not None and abs(observed_interaction) > 0:
    direction = ('biomarker+ patients benefit MORE from treatment'
                 if observed_interaction > 0 else
                 'biomarker− patients benefit MORE from treatment')
    L.append(f'_The strata show a {"positive" if observed_interaction > 0 else "negative"} '
             f'interaction: {direction}. This is the predictive-biomarker hypothesis to '
             f'carry into gate-3._')
L.append('')
L.append('## Downstream')
L.append('')
L.append('`virtual_population.csv` is emitted in the gate-3 schema '
         '(`patient_id, biomarker, treatment, outcome`, + covariates) and can be fed '
         'directly into `biostatistics/virtual_trial_gate3` / `gate3_interaction_test` '
         'to formally test the biomarker x treatment interaction.')
L.append('')
L.append('## Method')
L.append('')
L.append('Each virtual patient\\'s covariates are drawn DETERMINISTICALLY from the real '
         'cohort summary (Box–Muller normal for continuous; inverse-CDF for categorical) '
         'using a seedable stdlib LCG whose seed is a deterministic function of '
         '`seed_base` (FNV-1a + splitmix64 — NO `hash()`, NO `random` module, NO '
         'wall-clock), so two runs with identical parameters are byte-identical. Biomarker '
         'status is assigned by prevalence and treatment by allocation. The outcome is the '
         'user model\\'s linear predictor (intercept + covariate betas + biomarker + '
         'treatment + biomarker×treatment interaction), then a logistic→Bernoulli draw '
         '(binary) or linear + gaussian-noise draw (continuous).')
L.append('')
L.append('_Framework: QSP virtual-population methods (Allen/Rieger/Musante, CPT:PSP 2016); '
         'PRECISESADS-style stratified-autoimmune QSP response model as the class of user '
         'model consumed; MIDD / ICH M15 model-informed drug development._')
L.append('')
L.append('**Reminder: SIMULATED — grounded in a real cohort + a user model, NOT real patient data.**')
with open('qsp_population_report.md', 'w') as fh:
    fh.write('\\n'.join(L) + '\\n')

# ---- console summary ---------------------------------------------------------
print('=== QSP VIRTUAL POPULATION: %s | N=%d | outcome=%s | seed_base=%s ===' % (
    analysis, len(patients), otype, seed_base))
for k in ('bm+/exp', 'bm+/ctl', 'bm-/exp', 'bm-/ctl'):
    s = stratum_stats.get(k)
    if s:
        val = s.get('rate', s.get('mean'))
        print('  %-8s n=%-4d %s=%s' % (k, s['n'], ('rate' if otype == 'binary' else 'mean'), fmt(val)))
print('  eff(bm+)=%s  eff(bm-)=%s  interaction=%s' % (
    fmt(eff_pos), fmt(eff_neg), fmt(observed_interaction)))

with open('versions.yml', 'w') as fh:
    fh.write('qsp_virtual_population:\\n')
    fh.write('  python: "3.10"\\n')
    fh.write('  method: "deterministic QSP virtual-patient population from a real cohort covariate summary + a user mechanistic response model"\\n')
    fh.write('  basis: "QSP virtual populations (Allen/Rieger/Musante CPT:PSP 2016); MIDD/ICH M15"\\n')
PYEOF
    """
}

workflow QSP_VIRTUAL_POPULATION_WORKFLOW {
    take: meta_ch
    main: QSP_VIRTUAL_POPULATION(meta_ch)
    emit:
        results    = QSP_VIRTUAL_POPULATION.out.results
        population = QSP_VIRTUAL_POPULATION.out.population
        report     = QSP_VIRTUAL_POPULATION.out.report
}

workflow {
    meta = [id: 'qsp_virtual_population_run', single_end: false]
    Channel.value(meta) | QSP_VIRTUAL_POPULATION_WORKFLOW
}
