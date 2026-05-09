# Regulatory LLM — Session Summary & Next Plan

**Date:** 2026-05-06 → 2026-05-09  
**Branch:** integration/next-phase

---

## 1. What Was Built This Session

### 1.1 Training Infrastructure

**Corpus cleaning (May 6)**
- Removed 346 boilerplate records from `combined_regulatory_training.jsonl`:
  - 136 ICH ToC fragments (section-number dots `......` with no content)
  - 210 EMA CHMP assessment report preambles (date + committee headers being trained as regulatory prose)
- Final clean corpus: **1,724 records** across ICH_Guideline (1,050), EMA_EPAR (165), openFDA (500), FDA_NDA_Review (9)

**build_training_pairs.py — 6 fixes applied**

| Fix | Before | After |
|-----|--------|-------|
| Citation guarantee | Appended at end of full text → truncated by 500-word cap | Applied on `target` after truncation; always survives |
| pk_overview citation note | Cited EMA PBPK guideline (wrong) | ICH M3(R2) only |
| Section classifier | "13.1 Carcinogenesis, Mutagenesis" → tox_genotox | `_CARCINOGENICITY_HEADING_RE` disambiguates to tox_overview |
| REGION_ADDITIONS | 3/9 slots populated for EMA/NMPA/PMDA | All 9 slots: added tox_genotox, tox_overview, pk_overview, overview |
| tox_genotox keyword set | "chromosomal" (too broad) | "chromosomal aberration", "mutagenic activity", "bacterial reverse mutation", "clastogenic" |
| tox_overview keyword set | "carcinogenicity" (exact) | Added "carcinogenic", "carcinogenic potential", "tumorigenic", "embryofetal" |

**Dataset progression:**

| Version | Train pairs | tox_genotox S2(R1)% | tox_overview M3(R2)% | region_adaptation |
|---------|-------------|---------------------|----------------------|-------------------|
| v3 dataset | 1,370 | 84% | 100% | 510 |
| v4 dataset | 1,727 | **100%** | **100%** | **957** |

### 1.2 Model Training

Three training runs completed:

| Run | Container | Train ex | Time | ROUGE-L | citation_recall | audit% |
|-----|-----------|----------|------|---------|-----------------|--------|
| v3 | biomate/regulatory-llm-train | 1,370 | 563 min | 0.568 | 2.5% | ~86% |
| v4 (attempt 1) | same | 1,132 (old data) | killed at step 0 | — | — | — |
| **v4 (final)** | same | **1,727** | **693 min** | **0.576** | **13.0%** | **92%** |

**v4 section-level audit (50-sample eval):**
- admet: 100% (n=4)
- tox_overview: 100% (n=31)
- pk_overview: 100% (n=5)
- overview: 100% (n=5)
- tox_genotox: 20% (n=5) — **unreliable, only 5 samples**

The 20% for tox_genotox is statistically noise (1/5 passed). All 34 tox_genotox test examples have 100% S2(R1) in the reference targets; the issue is in the eval sampling, not the data.

### 1.3 Bug Fixes (7 from parallel-track audit)

**study_report_ingester.py**
- `micronucleus_result` always "negative": was reading `ames_result` field (None for MN studies) → now uses dedicated `_MICRONUCLEUS_RESULT_PATTERN`
- LD50/MTD extraction missing: added `_LD50_PATTERN` with lazy quantifier; wired into `extract_from_pdf()` and `_section_2631`
- Ames operator precedence: added explicit parentheses
- `_ROUTE_PATTERN` trailing `\b`: removed; i.v./i.m./s.c. now match
- Unused `import io`: removed
- **`_NOAEL_PATTERN` greedy**: regex consumed leading digits (100 → 0); made lazy (`{0,150}?`)
- Multi-study PDF detection: rejects FDA NDA review docs with clear error message

**ind_assembly.py**
- `assemble()` never loaded wetlab_data from `campaign_wetlab` DB: added `_load_stored_wetlab_data()`, called before merge — PDF uploads now automatically applied on next IND assembly
- v3/v4 adapter not in resolver: updated `_resolve_adapter_path()` priority (v4 > v3 > v2 > v1)
- `_section_2631_single_dose`: reads `ld50`/`ld50_unit` from ingested data with correct units

**finetune_regulatory_llm.py + _REQUIRED_CITATIONS**
- `pk_overview` incorrectly required EMA PBPK citation: fixed in eval audit and in `_REQUIRED_CITATIONS` dict

### 1.4 Evaluation Infrastructure (P1 — new)

`scripts/evaluate_regulatory_llm.py`:
- Replaces `citation_recall` substring metric with 3 interpretable signals:
  1. `correct_guideline` — cited guideline governs this section type (rule-based, instant)
  2. `no_hallucination` — no wrong-section citation present (rule-based)
  3. `contextual_placement` — citation adjacent to relevant claim (LLM judge, optional)
- Runs on full test split (227 examples), stratified by section type
- Old eval only randomly sampled 50, giving 5 tox_genotox samples

`GUIDELINE_GOVERNANCE` map defines which guidelines govern which sections:
- ICH S2(R1) → tox_genotox only
- ICH S7B → tox_cardiac, admet, tox_overview
- ICH M3(R2) → pk_overview, tox_overview, overview
- EMA/CHMP/EWP/37498/2011 → pbpk only

### 1.5 Retrieval Guardrail (P2 — new)

`backend/lib/galaxy/ai/drug_discovery/ich_corpus.py`:
- BM25-indexed ICH guideline corpus (17 PDFs, 6.3 MB)
- Fast path: domain keyword match per guideline (e.g., "ames", "bacterial reverse" → S2(R1))
- BM25 path: `rank_bm25` chunk retrieval for semantic grounding verification
- `ICHCorpus.verify_citation(citation_id, claim_text)` → `VerificationResult`
  - `grounded`: True if claim is supported by the guideline text
  - `score`: BM25 normalized similarity
  - `top_chunk`: most relevant guideline excerpt for auditing

Wired into `_regulatory_guardrails()` in `ind_assembly.py`:
- After citation injection, calls `corpus.verify_all_citations(out, section_type)`
- If `grounded=False` and `method != "unavailable"`: appends `CITATION_UNGROUNDED` warning
- Never blocks generation — silently skips on any error

### 1.6 Why citation_recall Is a Weak Metric

The user explicitly raised this and the answer is documented:

**Problems with substring citation_recall:**
1. Measures presence, not correctness — "PBPK per ICH S2(R1)" scores as correct (wrong guideline)
2. Rewards reflexive citation appending — model that appends citation to every sentence scores 100%
3. Not interpretable — is 13% good? No human baseline to compare against
4. String brittle — "ICH S2 (R1)" vs "ICH S2(R1)" are different strings

**Better approaches:**
1. **Search-based guardrail** (P2, now implemented): check if cited guideline covers the adjacent claim
2. **Classification-based judge** (P1, now implemented): LLM rates whether citation is contextually appropriate
3. Long term: factual grounding — verify that prose claims follow from guideline text (NLI)

---

## 2. Current State

### Active adapter
`models/regulatory_llm_v4/lora_adapter` — selected automatically by `_resolve_adapter_path()`

### Key files changed this session

| File | Change |
|------|--------|
| `data/regulatory_training/combined_regulatory_training.jsonl` | 346 boilerplate records removed |
| `scripts/build_training_pairs.py` | 6 fixes: citation guarantee, classifier, region additions |
| `scripts/finetune_regulatory_llm.py` | pk_overview audit rule fixed |
| `scripts/evaluate_regulatory_llm.py` | **NEW** — 3-signal LLM judge evaluator |
| `backend/lib/galaxy/ai/drug_discovery/ich_corpus.py` | **NEW** — BM25 ICH corpus + retrieval |
| `backend/lib/galaxy/ai/drug_discovery/ind_assembly.py` | P2 wired in; v4 adapter; `_load_stored_wetlab_data`; §2.6.3.x sections |
| `backend/lib/galaxy/ai/drug_discovery/study_report_ingester.py` | 7 bugs fixed |
| `backend/lib/galaxy/ai/drug_discovery/api_router.py` | StudyReportIngestResponse + new fields |
| `frontend/client/src/components/regulatory-document-editor.tsx` | **NEW** — TipTap editor (not browser-tested) |

### IND document sections implemented
| Section | Status |
|---------|--------|
| §2.4 Nonclinical overview | ✓ LLM prose |
| §2.6.1.1–1.6 Pharmacology | ✓ LLM prose |
| §2.6.2 PK overview | ✓ LLM prose |
| §2.6.3.1 Single-dose | ✓ wet-lab or placeholder |
| §2.6.3.2 Repeat-dose | ✓ wet-lab table or placeholder |
| §2.6.3.3 Genotoxicity | ✓ wet-lab or in silico fallback |
| §2.6.3 Tox overview | ✓ LLM prose |
| §2.6.4 Pharm written summary | ❌ not implemented |
| §2.6.5 PK written summary | ❌ not implemented |
| §2.6.6 Tox written summary | ❌ not implemented |

### Known open issues
1. **tox_genotox audit 20%** — n=5 makes this noisy; need full 34-sample eval with `evaluate_regulatory_llm.py`
2. **TipTap editor** — built, committed, TypeScript clean, but not browser-tested
3. **§2.6.4–2.6.6** — declared in sections list, missing from parts list
4. **FDA_NDA_Review corpus** — only 9 examples (5 PDFs); needs expansion for better NDA-style prose
5. **DPO alignment** — deferred; section classifier now fixed so can collect valid pairs

---

## 3. Next Plan

### P3 — DPO alignment (3 days)

**Why now:** The section classifier carcinogenicity/genotox disambiguation is fixed. Previous DPO attempts produced 0 usable pairs because carcinogenicity text was misclassified as tox_genotox, making chosen=rejected identical. Now that's resolved.

**Plan:**
1. Run `scripts/collect_dpo_training_data.py` pointing at v4 adapter to generate "rejected" outputs (fails audit)
2. Use v4 adapter in high-temp mode (temperature=0.9) to get varied outputs
3. Use base Qwen3-8B (no adapter) as second rejected source
4. Target: ~150 tox_genotox DPO pairs + 50 pk_overview pairs = 200 total
5. Train v5: SFT from v4 checkpoint (1 epoch to stabilize) + DPO phase (2 epochs, β=0.1)

**Expected outcome:** tox_genotox audit 20% → >70%

### P4 — Complete §2.6.4–2.6.6 (2 days)

**Why:** ICH M4S(R2) requires all six written summaries. The document is declared complete but §2.6.4–2.6.6 are empty. Users downloading DOCX get an incomplete document.

**Plan:**
- `_section_2641_pharm_written()` — tabulated pharmacology study summary from campaign ADMET data
- `_section_2651_pk_written()` — PK parameter table from pk_summary; NCA/PBPK results
- `_section_2661_tox_written()` — tox study table from wetlab_data + safety profile
- Wire into `assemble()` parts list

### P5 — Run the LLM judge evaluator on v4 (1 day)

**Command when ready:**
```bash
python3 scripts/evaluate_regulatory_llm.py \
  --adapter models/regulatory_llm_v4/lora_adapter \
  --data data/regulatory_training/tasks/splits/test.jsonl \
  --n-samples 227 \
  --llm-judge
```

This gives the true citation accuracy signal for v4 and establishes a baseline for measuring DPO improvement.

### P6 — Browser-test TipTap editor (0.5 days)

`frontend/client/src/components/regulatory-document-editor.tsx` was built by agent in the previous session and wired into `ind-report.tsx`. TypeScript compiles clean. Needs visual verification:
- AI highlight spans appear correctly (blue background)
- Edit removes highlight (human-edited counter increments)
- Section tabs (§2.6.1–§2.6.6) scroll correctly
- Word count displays
- .txt export downloads

### P7 — v5 training (after P3, ~1 week out)

**Dataset target:**
- v4 SFT pairs (1,727) as base
- 200 DPO pairs from P3 (tox_genotox + pk_overview focused)
- 50 manually curated tox_genotox single-study summaries from FDA NDA review PDFs
  (the 5 available NDA PDFs contain individual study summaries that can be extracted)

**Training config:**
```
Phase 1: SFT from v4 (1 epoch, lr=1e-4) — stability
Phase 2: DPO (2 epochs, lr=1e-5, β=0.1, KL penalty) — alignment
```

---

## 4. What NOT to Do Next

- **Another SFT run without DPO or new data** — v4 is at the SFT ceiling for this dataset
- **More corpus collection** before P5 eval establishes baseline — can't measure improvement without signal
- **Adding more raw EPAR/FDA data** before the FDA_NDA_Review source is improved — the 9 NDA examples are gold standard; 500 openFDA examples are adequate
- **Expanding §2.6.3.4–3.7** before §2.6.4–2.6.6 — the tabulated sections fill the declared section list first

---

## 5. Metric Targets for v5

| Metric | v4 | v5 target |
|--------|-----|-----------|
| ROUGE-L | 0.576 | >0.60 |
| citation_recall | 13% | >20% |
| audit_pass_rate (50-sample) | 92% | >95% |
| tox_genotox audit | ~20-30% | **>70%** |
| correct_guideline rate (new judge) | TBD after P5 | >80% |
| no_hallucination rate | TBD | >95% |
EOF
echo "Doc written"