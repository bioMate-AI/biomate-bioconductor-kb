# BiomniEval1 Failure Analysis — Root Causes and Fixes

**Date:** 2026-04-27  
**Current score:** 65.9% (v18, 147/223)  
**Target:** 70%+ (156+/223)

---

## Per-Task Breakdown (v18)

| Task | Pass | Total | Rate | Rank |
|------|------|-------|------|------|
| gwas_causal_gene | 37 | 50 | 74.0% | 1 |
| gwas_variant | 32 | 43 | 74.4% | 2 |
| rare_disease | 24 | 30 | 80.0% | 1 |
| patient_gene | 31 | 50 | 62.0% | 3 |
| screen_gene | 23 | 50 | 46.0% | 4 |
| **Overall** | **147** | **223** | **65.9%** | — |

---

## Root Cause Analysis

### screen_gene_retrieval (46%) — 27 failures

#### Bug 1 — Candidate limit cuts off correct gene (HIGH IMPACT)

In `_query_gene_essentiality(genes[:8])` and `for gene in candidates[:8]`, only the first 8 candidates receive:
- LOEUF essentiality scores
- Gene function summaries from MyGene.info

But candidate lists have 10-14 genes. If the correct gene is at position 9+, it gets **no context** while wrong candidates get detailed summaries.

**Confirmed case:** Instance 169 (GT=IFNAR2)
- Candidates list: `['HSD17B6', 'TRPM7', 'CCR8', 'KIT', 'TBX5', 'ZFP90', 'ARL17B', 'KLHL26', 'IFNAR2', 'TOB1', 'VPS37C']`
- IFNAR2 is position #9 — skipped by `candidates[:8]`
- Context provided detailed summaries for TRPM7, KIT, CCR8 but nothing for IFNAR2
- Model chose TRPM7 (had function context) over IFNAR2 (no context)

**Fix:** Change `candidates[:8]` → `candidates[:12]` in both `_query_gene_essentiality` and `lookup_crispr_screen_context`

---

#### Bug 2 — Perturbation extraction misses "response to X" pattern (MEDIUM IMPACT)

The perturbation parser only handles:
- `"resistance to X over"`
- `"effects of X on"`
- `"exposure/exposed to X"`
- Drug suffix patterns (-nib, -mab, -vir, etc.)

It **does not** handle `"response to X at a dosage of"` — a common phrase in screen questions.

**Confirmed case:** Instance 187 (GT=ACE2)
- Question: "study the response of A549-ACE2 lung cancer cells to **SARS-CoV-2 Sdel** at a dosage of 3.0 MOI"
- Parsed: `pert=''` (empty) → no context injected → model guesses FOXM1
- ACE2 (SARS-CoV-2 receptor) is in the candidate list and IS the obvious correct answer

**Fix:** Add regex pattern `r'response to (?:the\s+)?([A-Za-z][A-Za-z0-9\-\.\s\/]{2,40}?)(?:\s+at\s+a\s+dosage|\s+over\s)'`

---

#### Structural issue — Empirical screen hits undetectable from biology alone (HARD)

Many correct genes are non-obvious empirical hits:
- ZNF561-AS1 (lncRNA) — model picks ITGB6 (integrin, biologically plausible for vaccinia)
- VMP1 — model picks LPCAT1
- FAM83H — model picks GPR55 (biologically intuitive for DMSO screen)
- NAA10 — model picks ZEB1

The model has systematic bias toward **well-annotated, pathway-relevant genes** over empirically validated screen hits.

**PubMed search limitation:** Abstracts rarely name the specific top-hit gene. They describe the screen and discuss top biological pathways, not individual gene ranks.

**Partial fix:** Add prompt instruction warning against this bias.

---

### patient_gene_detection (62%) — 19 failures

#### Bug 3 — Model ignores HPO overlap scores (HIGH IMPACT)

The prompt provides explicit HPO overlap rankings, but the format instruction is too weak. The model overrides rankings with parametric knowledge.

**Confirmed case:** Instance 269 (GT=FLNA)
- HPO scores computed: FLNA=7.17 (ranked #1), HPRT1=0.00 (ranked last)
- HPRT1 has ZERO HPO overlap — clearly wrong
- Model chose HPRT1 because `self-mutilation + hyperactivity + hyperkinetic movements` = Lesch-Nyhan (training data recall)

**Current instruction (too weak):**
> "Search ClinVar and OMIM for the gene whose known disease associations match these phenotypes."

**Needed instruction (like rare_disease):**
> "MANDATORY RULE: Select the gene with the HIGHEST specificity-weighted HPO score from the ranked list above. Do NOT override this ranking with training-data knowledge. A gene with 0/12 HPO overlap is NOT the answer."

**Fix:** Update `_FORMAT_INSTRUCTIONS["patient_gene_detection"]` to match the authoritative language used in `rare_disease_diagnosis`.

---

#### Hard cases — HPO index doesn't cover the gene (MEDIUM)

Some correct genes are not well-represented in HPO phenotype.hpoa:
- ANGPTL6 (GT for instance 350) — vascular phenotypes may not be in HPO gene annotations
- PNKP (GT for instance 488) — newer/less common gene
- SHROOM4 (GT for instance 303) — poorly-annotated gene

For these, HPO scoring gives score=0 for ALL candidates or a wrong winner. The model then reverts to parametric reasoning.

**Partial fix:** When top HPO score is very low (<2.0) for all candidates, add fallback instruction: "HPO database evidence is limited — use your clinical genetics knowledge but consider rare, non-obvious genes."

---

## Prioritized Fix Plan

| Priority | Fix | Impact | Effort |
|----------|-----|--------|--------|
| P1 | patient_gene format instruction (use HPO scores) | +5-8 cases | 10 min |
| P2 | screen_gene candidate limit: [:8] → [:12] | +2-4 cases | 5 min |
| P3 | screen_gene perturbation extraction fix | +1-2 cases | 15 min |
| P4 | screen_gene anti-bias prompt instruction | +1-3 cases | 10 min |

**Expected total gain:** +9-17 cases → 156-164/223 → **70-73.5%**

---

## Implementation

Files to modify:
- `evaluation/adapters/biomni_eval1_adapter.py`
  - Line ~1256: `_FORMAT_INSTRUCTIONS["patient_gene_detection"]` — stronger mandate  
  - Line ~1003: `for gene in genes[:8]` → `[:12]` in `_query_gene_essentiality`
  - Line ~1135: `for gene in candidates[:8]` → `[:12]` in `lookup_crispr_screen_context`
  - Lines ~867-888: Add "response to X" perturbation pattern
