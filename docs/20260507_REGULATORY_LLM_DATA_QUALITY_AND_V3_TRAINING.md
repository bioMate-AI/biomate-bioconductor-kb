# Regulatory LLM Data Quality Fixes + v3 Training

**Date:** 2026-05-07  
**Branch:** integration/next-phase

## Summary

Completed a comprehensive data quality audit and fix pass on the regulatory LLM training dataset,
then launched v3 training on the cleaned data.

## Data Quality Issues Fixed

### Raw Corpus Cleaning (346 records removed)
- **ICH ToC fragments (136)**: Table of contents entries like "4.5 Route of Exposure....5" 
  with dots pattern `......` — not ICH guideline content
- **EMA EPAR preambles (210)**: Full EMA CHMP assessment report headers that were incorrectly
  used as training targets — model would learn to output "28 January 2021 EMA/112177/2021 
  Committee for Medicinal Products..." instead of regulatory prose

Final clean corpus: **1,724 records** (was 2,070)

| Source | Before | After |
|--------|--------|-------|
| ICH_Guideline | 1,186 | 1,050 |
| EMA_EPAR | 375 | 165 |
| openFDA_FDA_Labels | 500 | 500 |
| FDA_NDA_Review | 9 | 9 |

### Training Pair Rebuild (augment=3)
Running `build_training_pairs.py --augment 3` on the clean corpus:
- 573 unique pairs → 1,719 after 3× augmentation
- **Train: 1,370 / Dev: 169 / Test: 180**

| Task | Count |
|------|-------|
| section_generation | 1,161 |
| region_adaptation | 510 |
| regulatory_qa | 36 |
| table_generation | 12 |

### Task3 Region Adaptation Verified
- 311/311 unique pairs (100%) contain region-specific content (FDA/EMA/PMDA/ICH citations)
- Previously 0% — the fix from last session (budget-aware insertion before last sentence) confirmed working

### No Boilerplate in Training Targets
- 0 records with ToC dots in training splits
- 0 records with EMA preamble headers in training splits

## v3 Training Configuration

| Parameter | Value |
|-----------|-------|
| Base model | Qwen/Qwen3-8B |
| LoRA r | 16 |
| LoRA α | 32 |
| Epochs | 3 |
| LR | 2e-4 |
| Quantization | NF4 4-bit |
| Train examples | 1,370 |
| Container | nvcr.io/nvidia/pytorch:24.10-py3 |
| GPU | NVIDIA GB10 (128.5 GB) |
| Container name | regulatory_v3_training |

Training started: `2026-05-07 05:35:43`  
Estimated completion: ~12 hours (754 min was v2 with 2093 examples; 1370 examples ≈ 9.5h)

## v2 Metrics (for comparison)

| Metric | v1 | v2 | Expected v3 |
|--------|----|----|-------------|
| eval loss | 0.415 | 0.182 | <0.15 |
| citation_recall | 0.75% | 9.25% | >15% |
| avg_length_words | — | 158.1 | 150-180 |

The main improvement expected in v3:
1. No boilerplate targets → lower eval loss
2. Region-specific task3 data → better cross-jurisdiction generalization
3. Clean EPAR data → better EMA-style prose (was getting committee report headers)

## Known Remaining Gaps

- **FDA_NDA_Review: 9 records** — still very sparse; need more NDA review documents
- **HC SBD file**: 500 records with `openFDA_FDA_Labels` source and FDA header contamination;
  deferred — need header stripping before adding to corpus
- **tox_genotox: 300 train pairs** — all from openFDA, need ICH S2(R1) citation in 51%
- **DPO alignment**: Deferred until section classifier is fixed for carcinogenicity/genotox confusion

## Files Changed

- `data/regulatory_training/combined_regulatory_training.jsonl` — 346 bad records removed
- `data/regulatory_training/combined_regulatory_training.jsonl.bak` — original backup
- `data/regulatory_training/tasks/splits/train.jsonl` — rebuilt with augment=3
- `data/regulatory_training/tasks/dataset_stats.json` — updated stats
- `scripts/build_training_pairs.py` — augment=3 default, dedup improvements
