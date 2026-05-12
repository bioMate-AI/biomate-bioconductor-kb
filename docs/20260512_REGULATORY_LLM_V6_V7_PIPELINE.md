# Regulatory LLM v6/v7 Pipeline — Complete Reference

**Date:** 2026-05-12
**Status:** v6 training in progress (loss 0.04, eval 0.06 at epoch 1.6/3); v7 staged

This document is the single-source-of-truth for the regulatory LLM stack as
of v6/v7. Supersedes the v4 reference (`20260509_REGULATORY_LLM_SESSION_DOC.md`).

---

## Architecture (one diagram)

```
                        BASE: Qwen3-8B (NF4 4-bit, sm_121 PTX)
                                    │
                                    ▼
   ┌────────────────────────────────────────────────────────────────┐
   │  v6 SFT (LoRA r=16, α=32, 3 epochs, lr=2e-4)                   │
   │  • 5,892 train examples mixing existing prose + 5 new tasks    │
   │  • Each example self-verified by deterministic checker         │
   │  • Output: models/regulatory_llm_v6/lora_adapter               │
   └────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
   ┌────────────────────────────────────────────────────────────────┐
   │  evaluate_v6.py → v2 checklist per-task pass rates             │
   │  build_dpo_pairs.py --mode rejection-sample → real failures    │
   └────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
   ┌────────────────────────────────────────────────────────────────┐
   │  v7 DPO (2 epochs, lr=2e-4)                                     │
   │  • synthetic_pairs.jsonl (2,658 deterministic mutations)       │
   │  • + rejection-sampled pairs from v6                           │
   │  • Output: models/regulatory_llm_v7/lora_adapter               │
   └────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
                v7 production inference + v8 RL (future)
```

---

## v6 SFT corpus (committed in `data/regulatory_training/tasks/`)

| Task | Examples | Verifier | Boost ×N |
|---|---|---|---|
| task1 section generation (existing) | 532 | none | 1.0 |
| task3 region adaptation (existing) | 1,280 | none | 1.0 |
| task5 MRSD computation | 500 | `mrsd_verifier.py` | 2.0 |
| task6 §2.6.x skeleton completion | 1,288 | `structural_validator.py` | 1.5 |
| task7 ICH M3(R2) phase-gating | 300 | `phase_gating.py` | 2.0 |
| task8 §2.6.7 tabulated summary | 300 | `tabulated_summary.py` | 2.0 |
| task9 ICH adversity language | 300 | `adversity_language.py` | 2.0 |
| **train pool after boost** | **5,892** | | |
| dev | 326 | stratified by task | |
| test | 326 | stratified by task | |

Generation principle: **checker-first** — every synthetic example is rejected
if it doesn't pass the verifier. Verified yield: 100% of all 2,688 new
examples. See `docs/20260510_DOCUMENT_GENERATION_APPROACH.md` for full
methodology.

---

## Deterministic checker stack (9 total + 1 LLM judge)

All in `backend/lib/galaxy/ai/drug_discovery/`:

| ID | Module | What it checks |
|---|---|---|
| **A** | `structural_validator.py` | ICH M4S(R2) required subsections present + in order |
| **A2** | `tabulated_summary.py` | §2.6.7 markdown tables have required columns (5 templates) |
| **B3** | `structural_validator.py` (folded) | in vitro before in vivo ordering |
| **B4** | `adversity_language.py` | 5 ICH-distinct adversity categories matched correctly |
| **C1** | `mrsd_verifier.py` | NOAEL → HED → MRSD arithmetic via FDA BSA factors |
| **C2** | `phase_gating.py` | ICH M3(R2) Table 1 required studies enumerated |
| **D1** | `cross_section_consistency.py` | §2.6.6 NOAELs match §2.6.7 table |
| **D2** | `cross_section_consistency.py` | Study IDs in narrative present in table |
| **E1+E2** | `evaluate_regulatory_llm.py` | Citation governs section type; no hallucinated guideline |
| **E4** | `ich_corpus.py` | BM25 retrieval verifies cited guideline grounds claim |

Each checker doubles as: training-data filter → eval metric → inference
guardrail → RL reward component (v8).

**Deferred to v7+:** B1 numeric traceability + B2 unit specificity (needs
source-record DB shape decision).

---

## Wired into production (`ind_assembly.py`)

ICH M4S(R2) §2.6.2/§2.6.4/§2.6.6 written-summary builders:

```python
section_262_pharmacology_written(drug, region) → str  # 6 subsections
section_264_pk_written(drug, region) → str            # 9 subsections
section_266_tox_written(drug, region) → str           # 9 subsections
```

Each calls `_call_local_regulatory_llm` once per subsection. Output passes
`structural_validator` even when LLM unavailable ([NO DATA AVAILABLE]
fallback). Verified by `scripts/test_m4s_written_sections.py`.

---

## v6 training command

```bash
bash scripts/train_v6.sh
```

Internally: pulls `biomate/regulatory-llm-train:latest`, mounts the repo, runs
`finetune_regulatory_llm.py --data splits_v6 --output models/regulatory_llm_v6`
with QLoRA + bf16. Log to `logs/train_v6_<timestamp>.log`.

**Sm_121 note:** first step takes ~7min for PTX JIT compile. Subsequent steps
~30–60s. Total ~10–12hr for 3 epochs × 1,107 steps.

---

## v6 evaluation command

```bash
python scripts/evaluate_v6.py --adapter models/regulatory_llm_v6/lora_adapter
```

Loads v6, generates completions for `splits_v6/test.jsonl`, routes to the
right checker by `meta.task`, emits:
- `evaluation/results/regulatory_v6/test_predictions.jsonl` (per-example)
- `evaluation/results/regulatory_v6/summary.json` (aggregate per-task pass rate)

**Targets (per checkpoint v2 spec):**
| Task | v4 baseline | v6 target |
|---|---|---|
| MRSD computation | 0% grounded | ≥70% |
| Structural | 0% pass | ≥80% |
| Phase-gating | not measured | ≥80% |
| Tabulated | not measured | ≥70% |
| Adversity language | not measured | ≥80% |

---

## v7 DPO pipeline

```bash
# 1. After v6 finishes — collect real-model-failure pairs
python scripts/build_dpo_pairs.py --mode rejection-sample \
    --adapter models/regulatory_llm_v6/lora_adapter \
    --out data/regulatory_training/dpo/rejection_pairs.jsonl

# 2. Merge synthetic + rejection-sampled pairs (optional)
cat data/regulatory_training/dpo/synthetic_pairs.jsonl \
    data/regulatory_training/dpo/rejection_pairs.jsonl \
    > data/regulatory_training/dpo/merged_pairs.jsonl

# 3. Train v7
bash scripts/train_v7.sh data/regulatory_training/dpo/merged_pairs.jsonl
```

Existing synthetic pool: **2,658 pairs** across 5 tasks, every pair verified
contrastive (chosen passes checker, rejected fails).

---

## What v6/v7 will NOT solve

(Verified absent from training data; deferred to v8+:)

1. **Real-distribution sponsor §2.6.x prose** — sponsors don't publish CTD
   modules. Scrapers staged for TGA AusPAR + Health Canada SBD (network-gated
   in current sandbox).
2. **Numeric traceability to source records** — needs `campaign_wetlab` DB
   join + B1 checker (deferred).
3. **Document-level cross-section consistency over full §2.6.1–§2.6.7** —
   single-section generators don't enforce inter-section coherence; D1/D2
   checker exists but v6 doesn't train against it as a hard constraint
   (would need multi-section RL — v8).
4. **Adversity judgment** (whether a *novel* finding is adverse) — this is
   expert clinical judgment, not pattern matching. Always HITL.

---

## Files modified/added in v6/v7 sessions (2026-05-09 to 2026-05-12)

```
backend/lib/galaxy/ai/drug_discovery/
  ├── adversity_language.py       NEW (B4 checker)
  ├── cross_section_consistency.py NEW (D1/D2 checker)
  ├── ich_corpus.py                exists (E4 BM25)
  ├── ind_assembly.py              ADD 3× section_2X_written builders
  ├── mrsd_verifier.py             NEW (C1 checker)
  ├── phase_gating.py              NEW (C2 checker)
  ├── structural_validator.py      NEW (A/B3 checker)
  └── tabulated_summary.py         NEW (A2 checker)

scripts/
  ├── baseline_fda_checklist_on_corpus.py   NEW
  ├── baseline_v6_task_quality.py           NEW
  ├── build_dpo_pairs.py                    NEW
  ├── build_v6_sft_mix.py                   NEW
  ├── evaluate_v6.py                        NEW
  ├── generate_adversity_sft_task.py        NEW
  ├── generate_mrsd_sft_task.py             NEW
  ├── generate_phase_gating_sft_task.py     NEW
  ├── generate_skeleton_sft_task.py         NEW
  ├── generate_tabulated_sft_task.py        NEW
  ├── scrape_auspar_nonclinical.py          NEW
  ├── test_m4s_written_sections.py          NEW
  ├── train_v6.sh                           NEW
  └── train_v7.sh                           NEW

data/regulatory_training/
  ├── tasks/task5_mrsd_computation.jsonl       NEW (500)
  ├── tasks/task6_skeleton_completion.jsonl    NEW (1,288)
  ├── tasks/task7_phase_gating.jsonl           NEW (300)
  ├── tasks/task8_tabulated_summary.jsonl      NEW (300)
  ├── tasks/task9_adversity_language.jsonl     NEW (300)
  ├── tasks/splits_v6/{train,dev,test}.jsonl   NEW (5,892/326/326)
  └── dpo/synthetic_pairs.jsonl                NEW (2,658)

docs/
  ├── 20260509_FDA_REVIEWER_CHECKLIST_V2.md       NEW
  ├── 20260509_V6_CORPUS_STRATEGY.md              NEW
  ├── 20260510_DOCUMENT_GENERATION_APPROACH.md    NEW
  └── 20260512_REGULATORY_LLM_V6_V7_PIPELINE.md   NEW (this doc)
```

---

## Open items (post-v6 training completion)

1. **Run `evaluate_v6.py`** → establish per-task baseline. Update this doc
   with measured pass rates.
2. **Run rejection-sampling DPO collection** → merge with synthetic pairs.
3. **Launch `train_v7.sh`** → ~5hr.
4. **Compare v6 vs v7** on the v2 checklist. Expectation: v7 lifts low-
   performing checkers (e.g., adversity-language, phase-gating) by 10-20pp
   via preference signal.
5. **Real-data enrichment** (TGA AusPAR) — run on network-connected host
   when ready; mix 5-10% with v7 corpus for v8.
6. **v8 RL with composite checker reward** — covered in
   `20260509_FDA_REVIEWER_CHECKLIST_V2.md` §RL reward design.
