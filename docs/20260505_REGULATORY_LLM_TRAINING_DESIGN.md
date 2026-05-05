# Regulatory LLM Training — Task, Dataset, Experiment & Evaluation Design

**Date:** 2026-05-05  
**Status:** v1 dataset built; training paused pending data quality review  
**Author:** BioMate AI  

---

## 1. Objective

Fine-tune a 7-8B parameter instruction-tuned LLM to generate ICH M4 CTD Module 2.6 nonclinical written summaries (§2.6.1–§2.6.6) for IND applications. The trained adapter replaces `call_gemini_flash()` in `backend/lib/galaxy/ai/drug_discovery/ind_assembly.py:_llm_narrative()` and operates entirely on-premises using the GB10 Grace Blackwell GPU.

**Success criterion:** The local model produces §2.6.x prose that passes BioMate's existing regulatory audit at a MAJOR-finding rate ≤ the Gemini Flash baseline.

---

## 2. Task Design

### 2.1 What the model must do

Given structured nonclinical data (ADMET results, PBPK qualification metrics, toxicology study summaries) and a target regulatory region (FDA/EMA/NMPA/PMDA), produce a complete prose narrative for a specific CTD Module 2.6 section — ready for inclusion in an IND submission.

**Canonical input (how `_llm_narrative()` calls the model at inference):**
```
System: You are a regulatory affairs scientist generating ICH M4 CTD Module 2.6 
        nonclinical written summaries...

User:   Write the §2.6.3 (Nonclinical Overview: Toxicology) section for compound X.
        Submit to FDA under 21 CFR Part 312.

        Nonclinical findings:
        - hERG IC50: 14.2 µM (Redfern Category 3, low risk)
        - Ames test: negative across 5 strains with/without S9
        - 28-day rat study: NOAEL 30 mg/kg/day; target organs: liver (↑ALT 2.3×)
        - Carcinogenicity: not yet conducted (Phase I IND justification provided)
```

**Target output:** 300–600 words of formal regulatory prose, no markdown, citations to ICH guidelines (S7A, S7B, S2(R1)) where relevant.

### 2.2 Training task definitions

| Task | Format | Goal | n (train, v1) |
|------|--------|------|--------------|
| **T1** `section_generation` | findings summary → §2.6.x prose | Core prose generation skill | 1,288 |
| **T2** `regulatory_qa` | question → cited answer | Regulatory knowledge grounding | 28 |
| **T3** `region_adaptation` | FDA prose → EMA/NMPA/PMDA prose | Multi-jurisdiction capability | 757 |
| **T4** `table_generation` | prose → tabulated summary row | §2.6.4–6 structured output | — |

**T1 is the primary task.** T2 injects regulatory knowledge. T3 teaches region-specific language. T4 is deferred (insufficient data).

### 2.3 Input/output format

All pairs are formatted in ChatML (compatible with Qwen3, Qwen2.5, LLaMA-3):

```
<|im_start|>system
You are a regulatory affairs scientist with expertise in ICH M4 CTD Module 2.6 
nonclinical written summaries...<|im_end|>
<|im_start|>user
Write the §2.6.2 (PBPK Model Qualification) section for lecanemab.
Submit to EMA. Cite EMA/CHMP/EWP/37498/2011 where relevant.

Nonclinical findings summary:
There were no test article-related adverse effects on CNS, cardiovascular 
system, or respiratory function at any doses up to 50 mg/kg...<|im_end|>
<|im_start|>assistant
In accordance with ICH guidelines S6(R1) and S7A no stand-alone safety 
pharmacology studies were performed. The effect of lecanemab on the 
cardiovascular system, CNS, and respiratory system was evaluated in the 
4-week GLP repeated-dose toxicity study in cynomolgus monkeys...<|im_end|>
```

**Qwen3 note:** The user message is prepended with `/no_think` to suppress chain-of-thought reasoning. Qwen3's thinking mode is designed for mathematical reasoning and adds latency without benefit for regulatory prose generation.

---

## 3. Dataset Design

### 3.1 Sources and rationale

| Source | Raw examples | Quality | CTD style match | License |
|--------|-------------|---------|-----------------|---------|
| **EMA EPAR** (188 medicines) | 276 | ★★★★★ | ★★★★★ | CC BY 4.0 |
| **openFDA Drug Labels** | 500 | ★★★☆☆ | ★★☆☆☆ | Public domain |
| **ICH Guidelines** (9 PDFs) | 429 | ★★☆☆☆ | ★★☆☆☆ | Public use |
| **FDA NDA Reviews** | 9 | ★★★☆☆ | ★★★☆☆ | Public domain |

**EMA EPAR** is the gold-standard source: these are actual public assessment reports following ICH M4 structure, evaluating the same §2.6.1–§2.6.6 content we need to generate. The nonclinical sections are written by regulatory scientists in ICH CTD prose style.

**openFDA** provides scale (500 labels, 40K+ available) but has a **style mismatch**: FDA drug labels are a different document type from CTD Module 2.6 nonclinical overviews. Drug labels use §12/§13 numbering and list findings as drug prescribing information; CTD §2.6 summaries synthesize findings with regulatory interpretation for IND review.

**ICH Guidelines** are guidance text, not nonclinical summaries — useful for regulatory QA grounding but not for section_generation.

### 3.2 Quality filtering decisions

**Applied filters (each with rationale):**

| Filter | Effect | Why |
|--------|--------|-----|
| Response < 120 words → drop | Removes ~28% | Too short to teach prose style |
| EMA cover page / TOC text → drop | Removes ~53% of EPAR raw | Administrative text, not nonclinical findings |
| `section_type == "unknown"` → drop | Removes ICH preamble/TOC | Can't be classified → can't be trained on |
| Strip FDA label headers (§12/§13) | Cleans openFDA outputs | Headers confuse the model about CTD section structure |
| Sliding window USER≠ASST | USER = words 60-140, ASST = words 0-600 | Prevents model from learning to copy context verbatim |
| Curated QA only for T2 | Drops 652 ICH echo pairs | ICH-derived QA was circular (answer = question text) |

**EMA EPAR survival rate:** 276 raw → 61 unique pairs after filtering (22%). Most losses are from cover pages, table of contents, and procedural sections that appear before the actual nonclinical content in each EPAR PDF.

### 3.3 Known dataset problems (open)

**1. Style mismatch — openFDA dominance (85% of T1 training data)**

The current T1 dataset is 85% openFDA (FDA drug label style) vs 14% EMA EPAR (ICH CTD style). Training on this distribution risks teaching the model to produce FDA label-style prose rather than ICH M4 CTD §2.6 summaries.

*Resolution path:* Expand EMA EPAR collection from 188 → 1,554 catalogue entries. Expected yield: ~500 additional usable pairs, shifting ratio to ~40% CTD-style.

**2. T1 task is continuation, not generation from structured data**

The ideal T1 task is: structured ADMET/PBPK JSON → prose. But we lack paired (structured data, prose) training examples — real IND Module 2.6 documents are confidential, and the public EMA/FDA sources contain prose without the upstream structured data.

Our proxy: use the first 60-140 words of real regulatory prose as "findings context" and train the model to extend/complete it. This teaches *prose style and vocabulary* but not the structured-data-to-prose transformation the model needs at inference time.

*Resolution path:* Collect synthetic paired data using BioMate's own PBPK/ADMET pipelines on known compounds, then write reference regulatory prose manually for 50-100 compounds. These 50-100 expert-written examples would be more valuable than 1,000 openFDA examples.

**3. Regulatory QA coverage is thin (12 curated pairs)**

12 high-quality expert QA pairs cover the most common regulatory questions (PBPK criterion, hERG thresholds, genotoxicity follow-up, DILI presentation, multi-region requirements, 21 CFR Part 11). This is enough for knowledge grounding but not for comprehensive Q&A capability.

*Resolution path:* Expand to 100 curated pairs covering all ICH safety guidelines (S1-S9), PMDA-specific requirements, and CDE/NMPA guidance.

### 3.4 Final dataset composition (v1)

```
Total pairs (3x augmented):    2,598
  Train:                        2,073
  Dev:                            254
  Test:                           271

Task 1 — section_generation:   1,288 train (62%)
  Source: openFDA (85%), EMA EPAR (14%), FDA NDA (1%)
  Sections: admet (33%), tox_genotox (27%), tox_overview (12%), 
            pk_overview (12%), overview (8%), pbpk (8%)

Task 2 — regulatory_qa:           28 train (1%)
  All curated expert pairs × 3 augmentation = 9 unique × 3

Task 3 — region_adaptation:      757 train (37%)
  FDA → EMA/NMPA/PMDA prose adaptation

Length distribution (section_generation):
  Median: 548 tokens | P90: 965 tokens | Max: ~1,300 tokens
  (All within 2,048 token budget — no truncation)
```

---

## 4. Experiment Design

### 4.1 Model choice

**Qwen3-8B** (`Qwen/Qwen3-8B`, released April 29, 2025)

| Property | Value |
|----------|-------|
| Parameters | 8.2B total, 43.6M trainable (0.53% with LoRA r=16) |
| Context | 128K tokens (32K used in training) |
| Thinking mode | Hybrid — disabled via `/no_think` for regulatory prose |
| Multilingual | Strong EN/ZH/JA/KO — important for EMA/NMPA/PMDA text |

Qwen3-8B was chosen over Qwen2.5-7B (released Sep 2024) because it has significantly better instruction following and multilingual performance, which matters for generating region-specific regulatory prose (EMA English, NMPA Chinese-influenced, PMDA Japanese-influenced formatting).

### 4.2 Training configuration

```
Method:          QLoRA (4-bit NF4 quantization + LoRA adapters)
LoRA rank:       r=16, alpha=32, dropout=0.05
Target modules:  q_proj, k_proj, v_proj, o_proj, gate_proj, up_proj, down_proj
Optimizer:       paged_adamw_8bit
Learning rate:   2e-4 with cosine decay
Warmup:          50 steps
Batch size:      2 per device × 8 gradient accumulation = 16 effective
Epochs:          3
Max seq length:  2,048 tokens
Eval strategy:   every 100 steps (dev set)
Save strategy:   every 200 steps, keep best 3 by eval_loss
```

**Memory:** Qwen3-8B in 4-bit NF4 ≈ 5 GB model weights + ~8 GB activations/gradients. 128 GB unified memory on GB10 provides ample headroom.

**Hardware:** NVIDIA GB10 Grace Blackwell (sm_121), 128 GB unified memory. Running in NGC PyTorch 24.10 container (CUDA 12.6). Note: GB10 sm_121 is not listed in PyTorch 24.10's supported capabilities but runs sm_90 PTX code via CUDA backward compatibility — functional with a UserWarning.

**Estimated training time:** 2,073 examples × 3 epochs / (16 effective batch) ≈ 389 steps. At ~45s/step on GB10, ~5 hours total.

### 4.3 Experiment variants planned

| Experiment | Change vs baseline | Purpose |
|-----------|-------------------|---------|
| **v1** (current) | openFDA dominant, 2,073 train | Baseline; identify style drift |
| **v2** | +EPAR expansion to 1,554 medicines | Fix 85/14 FDA/CTD ratio |
| **v3** | +50 synthetic expert-written examples | Fix structured-data-to-prose gap |
| **v4** | v3 + DPO on audit failures | Reduce MAJOR findings post-training |

---

## 5. Evaluation Design

### 5.1 Automated metrics (run at training end)

Computed on the 271-example test split (section_generation only):

| Metric | Target | What it measures |
|--------|--------|-----------------|
| **ROUGE-L** | ≥ 0.30 | Lexical overlap with reference regulatory prose |
| **Citation recall** | ≥ 0.40 | Fraction of expected ICH/FDA/EMA citations present in output |
| **Avg output length** | 300–600 words | Appropriate section length |
| **Eval loss** | < 1.5 | Model confidence (perplexity proxy) |

ROUGE-L target is intentionally modest (0.30) because regulatory prose generation is a many-to-one problem — there are multiple valid ways to write a section, and lexical match with a single reference underestimates quality.

### 5.2 Functional evaluation — 76/76 IND gold standard

The existing test suite `backend/lib/galaxy/ai/drug_discovery/test_phase3_autoretrain_ind.py` runs 76 assertions across the full IND generation pipeline. After training, we run this suite with the LoRA adapter loaded in `_llm_narrative()`:

```bash
# Load adapter in ind_assembly.py, then:
python3 backend/lib/galaxy/ai/drug_discovery/test_phase3_autoretrain_ind.py
```

**Pass criterion:** 76/76 must still pass. Any regression indicates the adapter breaks regulatory logic.

### 5.3 Regulatory audit scoring (MAJOR findings per document)

For 10 held-out compound profiles (not in training data), generate complete §2.6.1–§2.6.3 documents with both:
- **Baseline:** current Gemini Flash via `call_gemini_flash()`
- **Candidate:** Qwen3-8B adapter via `_call_local_regulatory_llm()`

Run BioMate's existing regulatory auditor (`regulatory_auditor.py`) on each output. Compare:

| Metric | Target |
|--------|--------|
| MAJOR findings per document | ≤ Gemini baseline |
| CRITICAL findings per document | 0 (hard requirement) |
| Section completeness (§2.6.1–§2.6.3 all present) | 100% |
| ICH citation rate (at least 2 citations per section) | ≥ 80% |

### 5.4 Style quality rubric (human evaluation — 5 documents)

A human reviewer with regulatory affairs background scores each document on a 1-5 scale for:

| Dimension | 5 (excellent) | 1 (unacceptable) |
|-----------|--------------|-----------------|
| **CTD compliance** | Reads as ICH M4 §2.6 nonclinical summary | Reads as FDA drug label or guideline text |
| **Scientific accuracy** | All numbers match input data | Numbers hallucinated or internally inconsistent |
| **Regulatory interpretation** | Correct regulatory framing (NOAEL → safety margin → IND justification) | Raw data only, no regulatory interpretation |
| **Citation appropriateness** | Cited guidelines match the claim being made | Wrong guideline cited or no citations |
| **Prose quality** | Formal, flowing, 2-6 sentences per subsection | Bullet points, lists, or fragmented sentences |

**Threshold for deployment:** Mean score ≥ 3.5 across all dimensions.

### 5.5 A/B test plan (post-deployment)

After initial deployment to a staging endpoint:
1. Route 20% of IND generation requests to local model, 80% to Gemini Flash
2. Track: MAJOR audit findings rate, user regeneration rate, session abandonment after IND generation
3. Promote to 100% if local model MAJOR rate ≤ Gemini rate for 50 consecutive documents
4. Keep Gemini as fallback if local model returns error or takes > 30s

---

## 6. Known Gaps and Priorities

### Priority 1: Fix the style mismatch (highest impact)

Expand EMA EPAR collection from 188 → 1,554 medicines. Expected: ~500 additional usable pairs. Estimated time: 3-4 hours (7s/medicine × 1,554 × 25% yield).

```bash
python3 scripts/collect_regulatory_training_data.py \
  --epar --epar-max 1554 \
  --output data/regulatory_training
```

### Priority 2: Expert-written synthetic data (highest quality)

Generate 50 BioMate compound profiles with known ADMET/PBPK values, have a regulatory affairs expert write reference §2.6.x narratives. These 50 examples, properly formatted as (structured data → prose) pairs, would be the highest-value additions to the training set because they directly match the inference-time task.

**Format needed:**
```json
{
  "source": "expert_written",
  "drug": "compound_X",
  "section_type": "tox_overview",
  "structured_input": {
    "herg_ic50_uM": 8.2,
    "ames_result": "negative",
    "noael_mg_kg": 30,
    "target_organs": ["liver"],
    ...
  },
  "response": "The nonclinical toxicology package for compound X..."
}
```

### Priority 3: DPO alignment on audit failures

After v1 training, collect examples where the model generates MAJOR audit findings. Use these as "rejected" responses and Gemini-corrected versions as "chosen" responses for DPO (Direct Preference Optimization). This directly optimizes the model to avoid the failures the regulatory auditor penalizes.

### Priority 4: PMDA/NMPA coverage

Currently 0 examples from PMDA (Japan) or NMPA (China) native sources. The region_adaptation task provides some coverage but is built from FDA→PMDA/NMPA transformation of FDA-style prose, which propagates FDA prose style artifacts.

---

## 7. File Map

| File | Purpose |
|------|---------|
| `scripts/collect_regulatory_training_data.py` | Data collection from 7 sources |
| `scripts/build_training_pairs.py` | Raw examples → ChatML pairs (v2 design) |
| `scripts/finetune_regulatory_llm.py` | QLoRA fine-tuning with TRL 1.x |
| `data/regulatory_training/` | Raw corpus by source |
| `data/regulatory_training/tasks/splits/` | Train/dev/test splits |
| `models/regulatory_llm_v1/lora_adapter/` | Trained adapter (after run) |
| `models/regulatory_llm_v1/eval_metrics.json` | Automated metric results |
| `backend/lib/galaxy/ai/drug_discovery/ind_assembly.py` | Integration point |
| `backend/lib/galaxy/ai/drug_discovery/test_phase3_autoretrain_ind.py` | 76/76 gold standard |
