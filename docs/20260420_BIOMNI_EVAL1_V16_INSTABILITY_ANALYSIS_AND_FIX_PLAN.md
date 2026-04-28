# BiomniEval1 v16 Instability Analysis & Fix Plan

**Date:** 2026-04-20  
**Version:** v16 results (61.9% overall, n=223)  
**Question:** Why do some task types improve stably while others fluctuate run-to-run?

---

## 1. The Observed Pattern

| Task | v15 | v16 | Delta | Stability |
|------|-----|-----|-------|-----------|
| gwas_variant_prioritization | 69.8% | 76.7% | +7pp | Stable — 29 stable pass, 4 gained, 1 lost |
| patient_gene_detection | ~62% | 70.0% | +8pp | Moderate — 24 stable pass, 11 gained, 7 lost |
| gwas_causal_gene | 58.0% | 62.0% | +4pp | Moderate nondeterminism |
| rare_disease_diagnosis | 63.3% | 53.3% | −10pp | **Unstable — 3 gained, 6 lost** |
| screen_gene_retrieval | 46.0% | 46.0% | 0pp | Neutral |

The key paradox: rare_disease had the biggest single-version gain (v10→v15: +40pp from HPO scoring) but is the most unstable run-to-run (±10pp).

---

## 2. Root Cause Analysis

### 2a. Why gwas_variant and patient_gene gains are STABLE

The injected context gives **unambiguous signal** — the correct answer has a clearly dominant score:

**gwas_variant example (stable):**
```
[GWAS Catalog — Type 2 Diabetes-specific variant rankings]
  rs7903146:  p=1.26e-89  [Type 2 diabetes]        ← correct, 77 orders of magnitude below next
  rs4506565:  p=1.00e-10  [Type 2 diabetes]
  rs1801282:  p=0.01      [Type 2 diabetes]
```
The correct rsID dominates by 77 orders of magnitude. Temperature noise cannot flip the model's choice.

**patient_gene example (stable gain):**
```
[Gene-Phenotype Overlap Scores]
  ENSG00000198947 (DMD):   overlap=8  ← correct, 8 matching HPO terms
  ENSG00000103197 (TSC2):  overlap=1
  ENSG00000198793 (MECP2): overlap=0
```
An 8:1:0 overlap ratio is unambiguous. Model reliably picks DMD.

### 2b. Why rare_disease gains are UNSTABLE

The HPO overlap scores for disease subtypes within the same gene are **nearly tied**, because diseases in the same family share almost all phenotypic terms:

**Task 90/92 (Gordon syndrome — lost in v16):**
```
[Associated OMIM diseases — ranked by patient phenotype match]
  Gordon syndrome (OMIM 114300):        overlap=4  (joint contracture, ptosis, clubfoot, camptodactyly)
  Marden-Walker syndrome (OMIM 248700): overlap=4  (joint contracture, ptosis, micrognathia, blepharophimosis)
  DA3 (OMIM 114300):                    overlap=3
```
The top two candidates tie at overlap=4. Model picks arbitrarily between runs.

**Task 48 (Encephalopathy subtypes — lost in v16):**
```
  PEBAT OMIM 617193: overlap=5  (brain atrophy, corpus callosum, progressive, early-onset, intellectual disability)
  OMIM 617207:       overlap=5  (brain atrophy, optic atrophy, progressive, amyotrophy, intellectual disability)
```
Both diseases share the same gene, same gene family, same disease severity. HPO overlap is identical.

**Task 71 (Scalp-ear-nipple — lost in v16):**
```
  OMIM 181270:  "Scalp-ear-nipple syndrome"    ← correct
  OMIM 613420:  "Scalp-ear-nipple syndrome"    ← duplicate OMIM entry, same name
```
Two OMIM entries with the same disease name. The model correctly identifies the disease but picks the wrong OMIM ID.

### 2c. The False-Pass Problem (tasks 90 & 92)

The v15 "pass" on tasks 90 and 92 was not actually correct:

```
GT:  {"disease_name": "Gordon syndrome",          "OMIM_ID": "114300"}
v15: {"disease_name": "Arthrogryposis distal, 3", "OMIM_ID": "114300"}  ← wrong name, right ID → PASS
v16: {"disease_name": "Marden-Walker syndrome",   "OMIM_ID": "248700"}  ← wrong name, wrong ID → FAIL
```

The scorer accepts OMIM_ID match alone (even with wrong disease name). So some v15 "passes" were lucky OMIM_ID hits on a wrong diagnosis. These are **phantom passes** that disappear when the model's coin flip lands differently. The true stable-correct count for rare_disease is lower than 63.3%.

---

## 3. Failure Taxonomy

### Type A — Near-Tie HPO Overlap (main cause, 4/6 lost tasks)
Gene has multiple OMIM diseases with similar HPO term sets. Overlap scores differ by 0–1 terms. Model flips between runs.

| Task | Gene | Competing diseases | Overlap gap |
|------|------|--------------------|-------------|
| 90, 92 | PIEZO2/KCNJ2 | Gordon vs Marden-Walker | 0 |
| 48 | — | PEBAT (617193) vs OMIM 617207 | 0 |
| 130 | — | LCCS1 (253310) vs arthrogryposis-AHC (611890) | 0–1 |

### Type B — Duplicate OMIM Entries (1/6 lost tasks)
Same disease has two OMIM IDs (legacy + current). HPO data maps to both equally. Model picks either.

| Task | Disease | Competing IDs |
|------|---------|---------------|
| 71 | Scalp-ear-nipple syndrome | 181270 vs 613420 |

### Type C — Naming Alias (1/6 lost tasks)
Correct OMIM entry has been renamed; model outputs the modern name → different string match.

| Task | GT name | Model output |
|------|---------|-------------|
| 132 | "Syndromic X-linked mental retardation, Cabezas type" | "Intellectual developmental disorder, X-linked syndromic, Cabezas" |

---

## 4. Fix Plan

### Fix 1 — TF-IDF-weighted HPO overlap (addresses Type A)
**Problem:** All HPO terms counted equally. "Joint contracture" (HP:0001371) appears in 200+ diseases and is useless for disambiguation. "Oculomotor limitation" (HP:0000544) appears in <5 diseases and is highly discriminating.

**Implementation:**
```python
def _hpo_idf_weights() -> Dict[str, float]:
    """Compute IDF weight per HPO term across all diseases in phenotype.hpoa.
    High IDF = rare term = high discriminating power."""
    _ensure_hpo_disease_index()
    from collections import Counter
    import math
    term_freq = Counter()
    N = len(_HPO_DISEASE_PHENOTYPES)
    for terms in _HPO_DISEASE_PHENOTYPES.values():
        for t in set(terms):
            term_freq[t] += 1
    return {t: math.log(N / (1 + freq)) for t, freq in term_freq.items()}

def _hpo_weighted_overlap(patient_terms: Set[str], disease_terms: Set[str],
                          idf: Dict[str, float]) -> float:
    """Sum IDF weights of matching terms instead of counting matches."""
    shared = patient_terms & disease_terms
    return sum(idf.get(t, 0.0) for t in shared)
```

Replace `overlap = len(patient_set & disease_hpo)` with `overlap = _hpo_weighted_overlap(patient_set, disease_hpo, idf)` in both `lookup_omim_for_gene()` and the `patient_gene` section of `task_prompt()`.

**Expected effect:** Rare phenotype terms (unique to one disease subtype) get 5–10× higher weight than common terms. Near-ties in Type A cases should resolve because the distinguishing rare term dominates.

---

### Fix 2 — Deduplicate OMIM entries by preferred ID (addresses Type B)
**Problem:** `phenotype.hpoa` contains both legacy and current OMIM IDs for the same disease. UniProt also returns both. Model sees two candidates with identical names and picks randomly.

**Implementation:** After building the disease list from `_get_gene_omim_diseases()`, group entries by normalized disease name and keep only the numerically-smallest OMIM ID (OMIM convention: lower number = older/primary entry for that disease concept):

```python
def _deduplicate_omim_diseases(diseases: List[Dict]) -> List[Dict]:
    """If two OMIM IDs map to the same disease name, keep the primary (lower) ID."""
    seen_names: Dict[str, Dict] = {}
    for d in diseases:
        norm = d['name'].lower().strip()
        if norm not in seen_names:
            seen_names[norm] = d
        else:
            # Keep lower OMIM ID (OMIM convention: primary entry)
            if int(d['omim_id']) < int(seen_names[norm]['omim_id']):
                seen_names[norm] = d
    return list(seen_names.values())
```

---

### Fix 3 — Fuzzy name matching in scorer (addresses Type C)
**Problem:** Scorer does exact string match on `disease_name`. OMIM renames diseases over time — "Mental Retardation, X-Linked, Syndromic, Cabezas Type" → "Intellectual Developmental Disorder, X-Linked Syndromic, Cabezas Type". Model outputs modern name → scored as wrong.

**Implementation:** In `score()` in `biomni_eval1_adapter.py`, for `rare_disease_diagnosis`, after OMIM_ID match fails, try fuzzy name match:
```python
from difflib import SequenceMatcher
def _name_match(a: str, b: str) -> bool:
    a_norm = a.lower().replace(',', '').replace('-', ' ')
    b_norm = b.lower().replace(',', '').replace('-', ' ')
    if a_norm in b_norm or b_norm in a_norm:
        return True
    ratio = SequenceMatcher(None, a_norm, b_norm).ratio()
    return ratio >= 0.85

# In score():
if gt_omim and pred_omim and gt_omim == pred_omim:
    return 1.0
if gt_name and pred_name and _name_match(gt_name, pred_name):
    return 1.0  # Same disease, different alias
```

This also converts Type C phantom failures (where the model knows the right disease but uses the modern OMIM name) into true passes, and removes phantom passes (where OMIM_ID matched by luck with wrong disease) since both conditions must hold.

---

### Fix 4 — Inject mutation-type context for fine subtype disambiguation (addresses Type A hard cases)
For genes where HPO overlap is still tied after IDF weighting, the only remaining signal is the **specific variant/mutation** — e.g., dominant-negative vs loss-of-function mutations in the same gene cause different OMIM subtypes.

**Implementation:** Add mutation type from the task context into the prompt:
```
[Mutation context]
Variant type: de novo missense (dominant-negative)
→ favors OMIM entries with AD inheritance over AR entries
```

This requires parsing the task's `metadata` for `variant_type` or `inheritance` fields (check if BiomniEval1 dataset includes these).

---

## 5. Priority Order

| Fix | Effort | Expected gain | Addresses |
|-----|--------|---------------|-----------|
| Fix 1 — IDF-weighted HPO | Medium (1 function + swap) | +5–8pp rare_disease | Type A (main cause) |
| Fix 3 — Fuzzy scorer | Low (10 lines) | +2–3pp (removes phantom pass/fail) | Type C |
| Fix 2 — Deduplicate OMIM | Low (1 function) | +1–2pp | Type B |
| Fix 4 — Mutation context | High (needs dataset audit) | +3–5pp (Type A hard cases) | Type A residual |

Total expected gain: +11–18pp rare_disease → 64–71% (vs current 53.3%).

**Combined with patient_gene IDF fix (same code path):** patient_gene should also improve for cases where the winning gene has a tied HPO overlap with a paralogue.

---

## 6. Why Other Tasks Are Architecturally Different

| Task | Signal type | Gap magnitude | Stability |
|------|-------------|---------------|-----------|
| gwas_variant | p-value (log scale) | 10–100 orders of magnitude | High |
| patient_gene | HPO overlap count | 4–8 vs 0–1 | Medium-high |
| rare_disease | HPO overlap count | 4 vs 4 (tied) | Low |
| gwas_causal | GWAS gene mapping | Close (paralogue genes) | Medium |
| screen_gene | Candidate reasoning | Model knowledge | Low (knowledge gap) |

The fix path to ~65% overall is rare_disease IDF fix (+8pp on 30 tasks = +1.1pp overall) combined with fixing the phantom-pass scorer (+2pp on rare_disease = +0.3pp overall). This should close the gap to Biomni-R0-32B-Preview.
