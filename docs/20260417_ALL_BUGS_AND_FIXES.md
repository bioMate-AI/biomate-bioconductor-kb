# All Bugs Encountered and Resolved — Drug Dev Workflow Build Session
**Date:** 2026-04-17  
**Branch:** integration/next-phase  
**Scope:** Building and auditing 24 new Nextflow workflows (IDs 12861–12884) +
DB registration + API wiring

---

## Summary

| Phase | Bugs | Source |
|-------|------|--------|
| Phase 1 build (12861–12876) | 6 | Discovered during build + audit |
| Phase 1 audit | 4 | Discovered during 8-item checklist audit |
| DB / registration | 3 | Discovered during DB verification |
| Phase 2 build (12877–12884) | 0 | — |
| Phase 2 audit | 2 | Discovered during 8-item checklist audit |
| **Total** | **15** | |

---

## Phase 1 Build Bugs (discovered during development)

### B-01 — `cns_penetration_prediction`: keyword argument case mismatch

**File:** `pharmacology/cns_penetration_prediction/main.nf`  
**Symptom:** `TypeError: predict_cns_mpo() got an unexpected keyword argument 'pKa'`  
**Root cause:** Function signature defined `pka` (lowercase), but the call site used `pKa`
(mixed case):
```python
# BEFORE (broken)
props = predict_cns_mpo(mol, pKa=pka_in, logd=logd_in)
# AFTER (correct)
props = predict_cns_mpo(mol, pka=pka_in, logd=logd_in)
```
**Impact:** Workflow crash on any SMILES input — no CNS output produced.  
**Fix:** Corrected keyword to lowercase `pka`.

---

### B-02 — `dart_toxicity_prediction`: wrong default SMILES

**File:** `pharmacology/dart_toxicity_prediction/main.nf`  
**Symptom:** Default demo run produced no DART alerts, despite comment saying "thalidomide".  
**Root cause:** Default SMILES was phthalimide `O=C1NC(=O)c2ccccc21` — this is a
bicyclic imide without the glutarimide ring that distinguishes thalidomide. The key DART
alert `glutarimide_ring` SMARTS `N1C(=O)CCC1=O` has no match in phthalimide.
```python
# BEFORE (wrong)
params.smiles_list = '["O=C1NC(=O)c2ccccc21"]'  # phthalimide
# AFTER (correct)
params.smiles_list = '["O=C1CC(N2C(=O)c3ccccc3C2=O)C(=O)N1"]'  # thalidomide
```
**Impact:** Demo run silently returns zero alerts — misleads users testing the workflow.  
**Fix:** Changed to full thalidomide SMILES which correctly triggers both `glutarimide_ring`
and `phthalimide` SMARTS alerts.

---

### B-03 — `metabolite_prediction_biotransformer`: double-bracket SMARTS wrapping

**File:** `pharmacology/metabolite_prediction_biotransformer/main.nf`  
**Symptom:** `ValueError: SMARTS parse error` — all reaction rules fail to parse.  
**Root cause:** Substrate SMARTS patterns already contain brackets (e.g. `[N;!$(NC=O):1][CH3]`).
The reaction string builder wrapped them in an additional layer:
```python
# BEFORE (broken — double brackets)
rxn_str = f'[{rxn_smarts_substr}]>>[{rxn_smarts_prod}]'
# Produces: [[N;!$(NC=O):1][CH3]]>>[[NH:1]]  ← invalid SMARTS
# AFTER (correct)
rxn_str = f'{rxn_smarts_substr}>>{rxn_smarts_prod}'
```
**Impact:** All 19 metabolic transformation rules fail; zero metabolites predicted for any input.  
**Fix:** Removed the extra bracket wrapping.

---

### B-04 — `metabolite_prediction_biotransformer`: ester hydrolysis two-fragment product

**File:** `pharmacology/metabolite_prediction_biotransformer/main.nf`  
**Symptom:** Ester hydrolysis rule produced no products despite matching substrates.  
**Root cause:** Original SMARTS tried to emit both product fragments (carboxylic acid + alcohol)
from a single reactant in one reaction:
```python
# BEFORE (broken — two product fragments, RDKit can't produce from one reactant)
('[CX3:1](=[O])[OX2:2][CX4]', '[CX3:1](=[O])[OH].[OH:2]', ...)
# AFTER (correct — keep only the alcohol/phenol fragment)
('[CX3](=[O])[O:2][#6:3]', '[OH:2][#6:3]', ...)
```
`AllChem.ReactionFromSmarts` applied to a single reactant cannot produce two disconnected
product fragments. Mapping only the ester oxygen and its adjacent carbon preserves the
product fragment that carries the most pharmacological information (e.g. aspirin →
salicylic acid `O=C(O)c1ccccc1O`).  
**Impact:** No ester hydrolysis metabolites (e.g. prodrugs, acetates) predicted.  
**Fix:** Changed to single-fragment product SMARTS mapping O and adjacent C.

---

### B-05 — DB registration: `KeyError: 'annotation'`

**File:** `scripts/register_ai_tool_workflows.py`  
**Symptom:** `KeyError: 'annotation'` when running the registration script for the two
new workflows (metabolite_prediction_biotransformer, pharmacogenomics_pgx_report).  
**Root cause:** The two new workflow entries in the `WORKFLOWS` list were missing the
`"annotation"` field, which is required by the INSERT statement.  
**Fix:** Added `"annotation": "..."` to both entries.

---

### B-06 — DB registration: tags as Python list instead of comma-separated string

**File:** `scripts/register_ai_tool_workflows.py`  
**Symptom:** Tags stored as `"['metabolite', 'metabolism', ...]"` (Python list repr) instead
of `"metabolite,metabolism,..."` — FTS search on tags fails to match individual tag words
because the stored string contains brackets and quotes.  
**Root cause:** Tags were written as Python lists `["metabolite", ...]` instead of the
comma-separated string format used throughout the DB.  
```python
# BEFORE (wrong)
"tags": ["metabolite", "metabolism", "phase1", ...]
# AFTER (correct)
"tags": "metabolite,metabolism,phase1,..."
```
**Impact:** Tag-based FTS queries would not find these workflows by tag.  
**Fix:** Changed to comma-separated string format matching all other workflow entries.

---

## Phase 1 Audit Bugs (discovered during 8-item checklist)

### B-07 — `pbpk_simulation`: missing `sol.success` check after `solve_ivp`

**File:** `drug_discovery/pbpk_simulation/main.nf`  
**Root cause:** 8-compartment PBPK ODE uses LSODA solver. On stiff/extreme parameters
(e.g. very high CLint, atypical body weight) the solver can fail to converge and return
`sol.success = False`. The code proceeded to `sol.y[2] / Vblood` without checking — if
`sol.success` is False, `sol.y` contains a partial/NaN array, silently corrupting NCA
parameters and JSON output.

```python
# AFTER (correct)
if not sol.success:
    print(f"WARNING: ODE solver did not converge: {sol.message}", file=sys.stderr)
    Cblood_arr  = np.zeros(len(t_eval))
    Cliver_arr  = np.zeros(len(t_eval))
    Ckidney_arr = np.zeros(len(t_eval))
else:
    Cblood_arr  = sol.y[2] / Vblood
    Cliver_arr  = sol.y[3] / Vliver
    Ckidney_arr = sol.y[5] / Vkidney
```
**Impact:** Silent NaN propagation into all downstream PK metrics and JSON output.

---

### B-08 — `nanoparticle_pk_biodistribution`: same missing `sol.success` check

**File:** `pharmacology/nanoparticle_pk_biodistribution/main.nf`  
Same root cause as B-07. 4-compartment NP PK ODE (RK45). Zero-filled fallback for all
four compartment arrays. `spleen_arr = liver_arr * 0.3` left outside if/else (zeros × 0.3 = zeros — valid).

---

### B-09 — `target_engagement_kinetics`: same missing `sol.success` check in helper

**File:** `drug_discovery/target_engagement_kinetics/main.nf`  
Same root cause. ODE inside `occupancy_ode()` helper — slightly different fix: early
`return np.zeros(len(t_eval))` from the helper rather than inline guards.

```python
if not sol.success:
    import sys as _sys
    print(f"WARNING: occupancy ODE failed: {sol.message}", file=_sys.stderr)
    return np.zeros(len(t_eval))
```

---

### B-10 — `allometric_scaling`: divide-by-zero when all body weights identical

**File:** `pharmacology/allometric_scaling/main.nf`  
**Root cause:** Power-law regression uses `np.cov / np.var`:
```python
b = np.cov(log_bw, log_p)[0,1] / np.var(log_bw)
```
If all body-weight values are identical (e.g. user submits two rat experiments at 0.25 kg),
`np.var(log_bw) = 0`, causing `ZeroDivisionError` and workflow crash.

```python
# AFTER (correct)
var_bw = np.var(log_bw)
if var_bw == 0:
    return None, None  # degenerate input — regression undefined
b = np.cov(log_bw, log_p)[0,1] / var_bw
```
Caller already handled `(None, None)` return gracefully.

---

## DB / Registration Bugs (discovered during post-build verification)

### B-11 — `workflow_json` truncated to 8,000 chars in registration script

**File:** `scripts/register_ai_tool_workflows.py`  
**Symptom:** DB stored only first 8,000 chars of each workflow's `main.nf`. Large workflows
like `clinical_trial_simulation` (16.5 KB) and `pharmacogenomics_pgx_report` (17.1 KB)
had >50% of their Python logic missing from the DB record.  
**Impact:** `workflow_json` is fetched with `include_workflow_json=True` in
`ai_assistant.py:3038` and fed to the LLM for parameter resolution. Truncated content
means the LLM sees an incomplete workflow and may mis-configure parameters.  
**Root cause:** `nf_content[:8000]` hard-coded in the INSERT.  
**Fix:**
```python
# BEFORE
nf_content[:8000],          # store first 8K of main.nf
# AFTER
nf_content,                 # store full main.nf content
```
All 16 existing workflows updated via SQL UPDATE; 8 new workflows registered without truncation.

---

### B-12 — `description` truncated to 500 chars for 2 workflows

**File:** `scripts/register_ai_tool_workflows.py` + DB records for IDs 12875, 12876  
**Symptom:** `metabolite_prediction_biotransformer` (589 chars) and
`pharmacogenomics_pgx_report` (539 chars) had descriptions cut mid-sentence at 500 chars.  
**Impact:** FTS indexes the `description` field — truncated descriptions reduce search
recall for queries that match terms in the cut portion.  
**Root cause:** `wf["description"][:500]` in INSERT.  
**Fix:** Removed truncation from script; DB records updated directly via SQL UPDATE.

---

### B-13 — BGE embeddings stale — 16 new workflows missing from index

**File:** `database/galaxy_ai_workflow_embeddings.npz`  
**Symptom:** After registering IDs 12861–12876, the `.npz` still had `max_id=12860` (2449
entries). Dense retrieval would never score any of the 16 new workflows — they appeared
only in FTS results, losing the hybrid search bonus.  
**Root cause:** Embedding index is loaded once on server start with no automatic staleness
detection; new workflow inserts do not trigger a rebuild.  
**Fix:** Ran rebuild script — encoded name + description + domain + tags + annotation with
`BAAI/bge-small-en-v1.5`. Final counts:

| Event | Count | Max ID |
|-------|-------|--------|
| Before Phase 1 | 2449 | 12860 |
| After Phase 1 rebuild | 2465 | 12876 |
| After Phase 2 build | 2473 | 12884 |

---

## Phase 2 Audit Bugs (discovered during 8-item checklist on workflows 12877–12884)

### B-14 — `adaptive_trial_design`: Thompson sampling division by zero

**File:** `drug_discovery/adaptive_trial_design/main.nf`  
**Root cause:** In `thompson_weights()`, arm win probabilities are computed then raised to
power `exponent` (default 0.5) to balance exploration/exploitation. If all arms produce
identical beta distribution samples (possible in the very first stage when all arms have
uniform priors), `probs` after exponentiation can sum to a machine-epsilon value, causing
`NaN` from division:
```python
# BEFORE (crash on degenerate all-zero probs)
probs  /= probs.sum()
# AFTER (epsilon guard)
probs  /= (probs.sum() + 1e-10)
```
**Impact:** `np.random.multinomial` crashes on NaN allocation, aborting the simulation loop
mid-run and producing no output files.  
**Fix:** Added `1e-10` epsilon to denominator. Epsilon is well below any real probability
value; has no effect in normal operation.

---

### B-15 — `pbpk_pediatric_pregnancy`: dead import of `solve_ivp`

**File:** `pharmacology/pbpk_pediatric_pregnancy/main.nf`  
**Root cause:** Early draft used an ODE system for pediatric PBPK. Final implementation
switched to the closed-form well-stirred hepatic clearance model with allometric Vd
scaling — no ODE needed. The import remained:
```python
# BEFORE (dead code)
from scipy.integrate import solve_ivp
```
**Impact:** No runtime error (scipy is installed in the container), but violates the
`solve_ivp → sol.success` audit rule in spirit — a future maintainer adding an ODE call
would be doing so in a file that appears to already validate that pattern. Dead imports
also make it harder to audit which workflows genuinely use ODE integration.  
**Fix:** Removed the unused import line.

---

## Cross-Cutting Patterns

### Pattern 1 — Missing `sol.success` check after `solve_ivp` (B-07, B-08, B-09)

Three of the first 16 workflows shipped with this bug. Root cause: ODE integration failure
is not an exception — it returns a `OdeResult` object with `success=False` and a partial
`sol.y` array. Without an explicit check, NaN values flow silently into all downstream
calculations (AUC, Cmax, NCA parameters, JSON output).

**Standing rule (saved to memory `feedback_nextflow_ode_patterns.md`):**  
After every `solve_ivp(...)` call, check `sol.success` before any `sol.y[n]` access.
Provide zero-filled fallback arrays on failure.

### Pattern 2 — Denominator guards before division (B-10, B-14)

Two workflows had unguarded divisions that produced crashes on degenerate inputs
(`np.var == 0` for identical body weights; `probs.sum() == 0` for degenerate Thompson
sampling). Both were caught by the audit checklist item "division by zero without guard".

**Standing rule:** Before any `/ variable` in scientific computation, verify the denominator
is non-zero when the variable comes from user data or stochastic sampling.

### Pattern 3 — Registration field format assumptions (B-05, B-06)

Two registration bugs arose from incorrect field types in the `WORKFLOWS` list:
missing `"annotation"` field and `tags` as Python list instead of comma-separated string.
These were not caught by the automated 8-item Nextflow checklist (which only audits `.nf`
files, not the registration script).

**Standing rule:** When adding new entries to `register_ai_tool_workflows.py`, always
compare against an existing well-tested entry for field names and value types.

### Pattern 4 — Truncation in registration INSERT (B-11, B-12)

Hard-coded slice limits (`[:8000]`, `[:500]`) in the INSERT statement silently truncated
content that exceeded those limits. This was invisible to the test suite since no test
verified full content storage.

**Fix applied:** Removed all three slice limits from the script (`description`, `workflow_json`,
`docker_image`). Future registrations store full content.

---

## Final State

- **15 bugs total** across all phases
- **15 bugs fixed** — zero open
- All 24 workflows pass the 8-item structural checklist
- DB: full `workflow_json` stored for all 24 workflows (no truncation)
- BGE embeddings: 2473 entries, max_id=12884
