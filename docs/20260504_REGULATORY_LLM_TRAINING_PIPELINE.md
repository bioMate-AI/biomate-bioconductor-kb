# Regulatory LLM Training Pipeline — Session 2026-05-04/05

**Date:** 2026-05-04/05  
**Status:** Phase 1 complete; Phase 3 TRAINING IN PROGRESS (Qwen2.5-7B QLoRA, ~6-10h)

---

## What Was Built

### Scripts

| Script | Purpose |
|--------|---------|
| `scripts/collect_regulatory_training_data.py` | Download regulatory corpora from 7 sources |
| `scripts/build_training_pairs.py` | Convert raw docs → ChatML fine-tuning pairs |
| `scripts/finetune_regulatory_llm.py` | QLoRA fine-tuning + NGC container setup |

### Docker Image

```
biomate/regulatory-llm-train:latest (17.3 GB)
  Base: nvcr.io/nvidia/pytorch:24.10-py3
  Extra: bitsandbytes>=0.43, peft>=0.10, trl>=0.8, datasets, rouge_score
  GB10 note: sm_121 runs sm_90 PTX via CUDA backward compat — UserWarning, not failure
```

### Data Collected (Phase 1 — FINAL)

| Source | Raw Examples | Status |
|--------|-------------|--------|
| ICH Guidelines (9 PDFs) | 429 | ✓ Complete |
| EMA EPAR (188/500 catalogue entries) | 276 | ✓ Complete (session 2) |
| openFDA Drug Labels (nonclinical_toxicology) | 500 | ✓ Complete (session 2) |
| FDA NDA reviews | 9 | ✓ Partial (URL fix needed) |
| TGA AusPAR | 0 | ⚠ Timeout — skip for now |
| Health Canada SBD | Uses openFDA | ✓ (HC portal is JS-only) |

**Total raw corpus: 1,214 examples**

### Bugs Fixed (Session 2)

1. **`combine_examples()` used `glob()` instead of `rglob()`** — missed all subdirectory JSONL files. Fixed to `rglob()` with corrected `tasks/splits` filter using `Path.parts`.
2. **`collect_health_canada_sbd()` referenced undefined `HC_SBD_DOC_API`** — replaced entire function with openFDA API collector (`/api/drug/label.json`, 40K+ labels).
3. **`combine_examples()` was including processed task JSONL files** — filter now checks `"tasks" in jsonl.parts`.
4. **EPAR 500-medicine run stopped at 188 with examples** — expected behavior (25% of catalogue entries have downloadable PDFs).

### Training Dataset (CURRENT STATE — ready for training)

```
Total pairs:       3,868 (2x augmented)
  Train:           3,089
  Dev:               384
  Test:              395

SFT pairs (Tasks 1+2):   3,234
  Task 1 — section_generation: 2,390
  Task 2 — regulatory_qa:       844
  Task 3 — region_adaptation:   616
  Task 4 — table_generation:     18

By section type:
  tox_overview:  794  (§2.6.3 toxicology — mostly from openFDA)
  pbpk:          772  (§2.6.2 PBPK)
  overview:      630  (§2.6.1 methods overview)
  pk_overview:   464  (§2.6.2 PK overview)
  admet:         230  (§2.6.1.3 ADMET screening)
  tox_genotox:   112  (§2.6.3.3 genotoxicity)
  tox_cardiac:     4  (§2.6.3.7 cardiac safety)
  unknown:       862  (ICH preamble/TOC text — will filter in v2)
```

---

## Phase 3 — Training (IN PROGRESS)

### Command running now

```bash
docker run --rm --gpus all --ipc=host \
  --ulimit memlock=-1 --ulimit stack=67108864 \
  -v $(pwd):/workspace -w /workspace \
  biomate/regulatory-llm-train:latest \
  python3 scripts/finetune_regulatory_llm.py \
    --model qwen2.5-7b-instruct \
    --data data/regulatory_training/tasks/splits \
    --output models/regulatory_llm_v1 \
    --task section_generation regulatory_qa \
    --epochs 3 --lora-r 16 --batch-size 2 --grad-accum 8
```

### Logs

- Live: `/tmp/finetune_v1.log`
- Output: `models/regulatory_llm_v1/lora_adapter/`
- Eval metrics: `models/regulatory_llm_v1/eval_metrics.json`

### Expected duration

~6-10 hours (3,000 training examples × 3 epochs ÷ batch=16 effective)

### Hardware

- GPU: NVIDIA GB10 Grace Blackwell, sm_121, 128 GB unified memory
- Container: NGC PyTorch 24.10 (CUDA 12.6, PyTorch 2.5.0)
- sm_121 note: runs on sm_90 PTX compilation — functional, not ideal. NGC 25.04 would be native.

---

## Phase 0 (already deployed — no training needed)

These improvements went live in `_llm_narrative()`:

1. **RAG injection** — `_build_rag_context()` pulls narrative patterns from `regulatory_skills_db` per section
2. **Region-specific system prompts** — `_NARRATIVE_SYSTEM_BY_REGION` per FDA/EMA/NMPA/PMDA
3. **OSP benchmark context** — PBPK sections receive OSP-approved range comparison
4. **Audit-triggered regeneration** — `audit_constraint` parameter for regenerating failed sections
5. **All 13 `_llm_narrative()` call sites** pass `region=ctx.get("region","FDA")`

All 76/76 IND gold standard tests still passing.

---

## Next Steps

### After training completes

```bash
# Check adapter quality
ls models/regulatory_llm_v1/lora_adapter/
cat models/regulatory_llm_v1/eval_metrics.json

# Quick inference test
docker run --rm --gpus all --ipc=host \
  -v $(pwd):/workspace -w /workspace \
  biomate/regulatory-llm-train:latest \
  python3 scripts/finetune_regulatory_llm.py \
    --model qwen2.5-7b-instruct \
    --resume models/regulatory_llm_v1/lora_adapter \
    --inference-only --prompt "Write the PBPK qualification section for compound XYZ"

# Verify against gold standard
python3 backend/lib/galaxy/ai/drug_discovery/test_phase3_autoretrain_ind.py
```

### After adapter quality verified

1. Replace `call_gemini_flash()` in `_llm_narrative()` with local model endpoint:
   - Add `_call_local_regulatory_llm()` wrapper in `ind_assembly.py`
   - Load adapter: `PeftModel.from_pretrained(base_model, "models/regulatory_llm_v1/lora_adapter")`
   - Route all 13 narrative call sites through local model
2. A/B test audit scores (MAJOR findings per document) vs. Gemini baseline
3. Target: ROUGE-L ≥ 0.35, citation recall ≥ 0.5, MAJOR findings ≤ baseline

### Data expansion (if training quality is poor)

```bash
# Expand EPAR to scan all 1554 catalogue entries (3-4 hours)
python3 scripts/collect_regulatory_training_data.py \
  --epar --epar-max 1554 \
  --output data/regulatory_training

# Expand openFDA to 2000 labels
python3 scripts/collect_regulatory_training_data.py \
  --hc-sbd --hc-max 2000 \
  --output data/regulatory_training

# Add DailyMed SPL XML archive (~155K labels, 2-3 GB download)
python3 scripts/collect_regulatory_training_data.py \
  --dailymed --dailymed-max 10000 \
  --output data/regulatory_training
```

**Target for Phase 2 data: 20,000–50,000 pairs** (currently 3,868)

### FDA NDA URL pattern fix (30-min task)

```python
# Current: direct URL guessing fails for ~75% of NDAs
# Fix: use openFDA API to discover PDF URLs
FDA_SEARCH_API = "https://api.fda.gov/drug/drugsfda.json?search=application_number.exact:NDA{nda}&limit=1"
# Extract PDF URLs from structured response
```

---

## Key Design Decisions

**Value extraction from regulatory prose (reverse engineering):**
Real regulatory documents contain prose but not the structured upstream data (ADMET/PBPK numbers) that generated it. We solve this by extracting numeric values from the prose using regex patterns (`extract_pbpk_values()`, `extract_admet_values()`), then constructing a plausible structured input. This gives Task 1 training pairs that teach the model to go from numbers → prose.

**openFDA as primary FDA nonclinical source:**
DailyMed SPL XML API doesn't return JSON for individual labels (returns HTML). openFDA `/drug/label.json` endpoint has 40K+ labels with `nonclinical_toxicology` field in clean JSON. This is the right source.

**Section classifier:**
`classify_section()` uses keyword scoring to map raw regulatory text to 8 section types. Accuracy ~70% on ICH guidelines; "unknown" (862 pairs) is primarily from guideline preamble/TOC text. Will filter in v2.

**GB10 CUDA compatibility:**
sm_121 (Blackwell) runs sm_90 PTX compiled code via CUDA backward compat. NGC 24.10 (CUDA 12.6) works with a UserWarning — not a crash. NGC 25.04 would support sm_121 natively.
