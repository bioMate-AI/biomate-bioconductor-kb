# Regulatory LLM Training — Session Progress Report

**Date:** 2026-05-05  
**Status:** ✓ Training complete — adapter at `models/regulatory_llm_v1/lora_adapter/`  
**Next:** Wire adapter into `_llm_narrative()`, run 76/76 gold standard, A/B vs Gemini

---

## 1. What Was Built This Session

### Data Pipeline

| Script | Purpose | Status |
|--------|---------|--------|
| `scripts/collect_regulatory_training_data.py` | Downloads regulatory corpora from 8 sources | ✓ Working |
| `scripts/build_training_pairs.py` | Converts raw docs → ChatML fine-tuning pairs (v2) | ✓ Working |
| `scripts/finetune_regulatory_llm.py` | QLoRA fine-tuning with TRL 1.x, Qwen3-8B | ✓ Working |

### Documentation Written

| File | Content |
|------|---------|
| `docs/20260505_REGULATORY_LLM_TRAINING_DESIGN.md` | Task/dataset/experiment/evaluation design |
| `docs/20260505_ICH_GUIDELINE_REFERENCE.md` | What each ICH guideline is, which §2.6 section it governs |
| `docs/20260504_REGULATORY_LLM_DATASETS_AND_RESOURCES.md` | All public training resources, priority order |
| `docs/20260504_REGULATORY_LLM_TRAINING_PIPELINE.md` | Session log, next steps |

---

## 2. Training Data — Final State

### Raw Corpus

| Source | Examples | Style | ICH §2.6 Relevance |
|--------|---------|-------|-------------------|
| **ICH Guidelines** (17 PDFs) | 1,186 | Guidance text | ★★★☆☆ Regulatory knowledge grounding |
| **EMA EPAR** (188 medicines) | 276 | CTD nonclinical prose | ★★★★★ Best §2.6 style match |
| **openFDA Drug Labels** | 500 | FDA label prose | ★★☆☆☆ Nonclinical content, wrong genre |
| **FDA NDA Reviews** | 9 | FDA reviewer prose | ★★★★★ Best FDA style, too few |
| **Total** | **1,971** | | |

### ICH Guidelines Collected (17 PDFs)

| Guideline | What it governs | §2.6 section |
|-----------|----------------|-------------|
| M4S(R2) | CTD format — the template itself | All §2.6 |
| M3(R2) | Phase-gating: what studies required per phase | §2.6.1 framing |
| S7A | Safety pharmacology core battery (CNS/CV/respiratory) | §2.6.1, §2.6.3.7 |
| S7B | hERG/cardiac ion channel (original 2005) | §2.6.3.7 |
| S2(R1) | Genotoxicity battery (Ames, micronucleus, CA) | §2.6.3.3 |
| S1A | When carcinogenicity studies are required | §2.6.3.4 |
| S1B | How to conduct carcinogenicity (2yr rat/mouse) | §2.6.3.4 |
| S1C(R2) | Dose selection for carcinogenicity (MTD, 25× AUC) | §2.6.3.4 |
| S5(R3) | Reproductive/developmental toxicology | §2.6.3.2 |
| S6(R1) | Biologics/biotech preclinical safety | §2.6 (mAbs/gene therapy) |
| S8 | Immunotoxicity (TDAR assay) | §2.6.3.6 |
| S9 | Oncology IND nonclinical package | §2.6 (oncology) |
| E5(R1) | Ethnic factors — NMPA/PMDA bridging | §2.6.2 regional |
| E7 | Geriatric populations | §2.6 context |
| EMA PBPK | EMA PBPK reporting (67% criterion) | §2.6.2 |
| FDA PBPK 2018 | FDA PBPK format (Table 2/3, forest plots) | §2.6.2 |
| M7(R2) | Mutagenic impurities (TTC thresholds) | §2.6.3.3 |

**Missing (require manual download from ich.org — not on database.ich.org):**
- S7B(R1) 2024 — formalizes in silico hERG; S7B 2005 used instead
- S5(R3) and S6(R1) — successfully obtained manually by user and included ✓

### Training Pairs (after quality filtering)

```
Total pairs (3× augmented):     2,622
  Train:                         2,093
  Dev:                             256
  Test:                            273

Used for training (T1+T2 only): 1,316 train | 161 dev | 174 test
  Task 1 — section_generation:  1,298 train pairs
    Sources: openFDA 84%, EMA EPAR 14%, FDA NDA 1%
    Sections: admet 33%, tox_genotox 26%, pk_overview 12%,
              tox_overview 12%, overview 8%, pbpk 8%
  Task 2 — regulatory_qa:          28 train pairs (12 unique × 3 augment)
    12 expert-written Q&A pairs covering PBPK criterion, hERG thresholds,
    genotoxicity follow-up, DILI presentation, multi-region requirements,
    21 CFR Part 11, ADMET applicability domain, AI regulatory guidance
```

### Quality Fixes Applied (v2 dataset design)

| Problem (v1) | Fix (v2) | Impact |
|-------------|---------|--------|
| Sparse JSON input (65% of T1) | Sliding window: USER=words 60–140, ASST=words 0–600 | USER has real context |
| EMA cover page boilerplate (53% of EPAR) | Phrase filter drops admin text | 0% remaining |
| FDA label section headers in output (42%) | Regex strip patterns A–D | 5.8% remaining |
| Circular QA answers (100% of ICH-derived QA) | Drop all; keep 12 curated pairs only | 0% circular |
| Short responses <60 words (28%) | Raised minimum to 120 words | 0% remaining |
| ROUGE-L 0.30 target (below copy baseline) | Removed as pass/fail; diagnostic only | Honest eval |

---

## 3. Training Runs — v1 and v2 Results

### v1 vs v2 Comparison

| Parameter | v1 | v2 |
|-----------|----|----|
| Training examples | 1,316 | 2,093 (+59%) |
| Tasks included | T1+T2 only | T1+T2+T3 (all) |
| Dataset quality | Sparse JSON, sliding window, 0% citation injection | Full text, 14.9% citation injection |
| Training time | 474.7 min | 754.7 min |
| Final train loss | ~0.30 | **0.148** (−51%) |
| Final eval loss | 0.415 | **0.182** (−56%) |
| Final token accuracy | 88.7% | **95.3%** (+6.6pp) |
| Citation recall | 0.75% | **9.25%** (+12×) |
| Avg output length | 151.7w | 158.1w (eval capped at 256 tokens*) |

*Eval used old 256-token cap (code updated after container started); actual generation capability higher.

### v2 Loss Curve (every 10 optimizer steps)

| Epoch | Train Loss | Token Accuracy | Notes |
|-------|-----------|----------------|-------|
| 0.53 | 0.684 | 83.2% | |
| 0.77 | 0.518 | 87.0% | Eval: 0.525 |
| 1.00 | 0.471 | 88.4% | End epoch 1 |
| 1.15 | 0.328 | 91.7% | |
| 1.53 | 0.305 | 92.6% | |
| 2.52 | 0.163 | 96.0% | |
| 2.90 | 0.154 | 96.2% | |
| 2.98 | 0.148 | 96.5% | |
| **3.00** | **—** | **—** | **Complete** |

**Training time:** 754.7 minutes (12h 35min)  
**Final eval loss (epoch 3):** 0.182 (dev set)  
**Final dev token accuracy:** 95.3%

### v1 Loss Curve (archived)

| Epoch | Train Loss | Token Accuracy |
|-------|-----------|----------------|
| 0.97 | 0.787 | 80.3% |
| 1.93 | 0.456 | 88.3% |
| 2.90 | 0.298 | 92.4% |

Training time: 474.7 min. Eval loss: 0.415. Token accuracy: 88.7%.

### Adapters

```
models/regulatory_llm_v1/lora_adapter/   (167 MB, Qwen3-8B, r=16, 1316 examples)
models/regulatory_llm_v2/lora_adapter/   (167 MB, Qwen3-8B, r=16, 2093 examples) ← ACTIVE
  adapter_config.json
  adapter_model.safetensors
  chat_template.jinja
  tokenizer_config.json
  tokenizer.json
  README.md
```

---

## 4. Evaluation Findings and Issues

### Issue 1: Citation recall = 0.75% (critical)

The model generates regulatory prose but rarely includes specific guideline citations like "EMA/CHMP/EWP/37498/2011" or "ICH S2(R1)" or "21 CFR Part 312". Expected ≥40%.

**Root cause:** The 12 curated QA pairs (the only training examples with explicit citations) represent <1% of the training data. The openFDA and ICH guideline sections used for T1 training contain guideline references embedded in prose but they aren't explicitly formatted as citation strings.

**Fix needed:** Add citations as required outputs in the T1 section_generation prompt — e.g., explicitly instruct "cite applicable ICH guidelines by full name" in the system prompt.

### Issue 2: Output length = 151.7 words (too short)

Target is 300–600 words per section. The model averages 151 words — about half the needed length.

**Root cause:** The training targets (ASST) are capped at 600 words but the sliding window design means the first 60 words are skipped as context, so the model is actually trained on outputs starting at word 60. When generating, it stops earlier than needed.

**Fix:** Remove the sliding window from the target — use words 0–600 as the full output, make the user prompt a cleaner "write this section" instruction rather than a partial-text continuation.

### Issue 3: Style mismatch persists

85% of T1 training data is openFDA FDA drug label text. The model likely produces FDA label-style prose rather than ICH M4 CTD §2.6 nonclinical overview prose. This can only be assessed via human evaluation.

---

## 4b. Post-Training Integration (completed after §4)

### Local Model Wired into `_llm_narrative()`

`ind_assembly.py` now routes: **local Qwen3-8B adapter → guardrails → Gemini fallback**

```python
# Routing logic in _llm_narrative():
narrative = _call_local_regulatory_llm(section_type, system, user_prompt, max_new_tokens=600)
source = "local"
if not narrative or len(narrative.split()) < 30:
    narrative = _gemini_flash(...)   # Gemini fallback
    source = "gemini"
narrative, warnings = _regulatory_guardrails(narrative, section_type, data, region)
```

The local model is lazy-loaded on first call. Path set via `REGULATORY_LLM_ADAPTER` env variable (default: `models/regulatory_llm_v1/lora_adapter`). If the adapter directory doesn't exist, falls back to Gemini silently.

**76/76 gold standard still passing** after integration.

### Guardrails Applied After Every Generation

Four checks run on every narrative (local model or Gemini):

| Guardrail | Trigger | Action |
|-----------|---------|--------|
| **Citation injector** | Required ICH/EMA citations absent | Appends `[Applicable guidelines: ...]` footnote |
| **Length guard** | Output < 150 words | Logs `SHORT_OUTPUT` warning |
| **Numeric faithfulness** | >3 numbers in output not in input data | Logs `NUMERIC_MISMATCH` warning |
| **Header strip** | FDA label `§12/§13` headers present | Strips headers from output |

Required citations per section:
- `pbpk`/`pk_overview`: EMA/CHMP/EWP/37498/2011, ICH M3(R2)
- `tox_genotox`: ICH S2(R1)
- `tox_cardiac`: ICH S7B, ICH S7A
- `overview`/`tox_overview`: ICH M4S(R2), ICH M3(R2)
- `admet`: ICH M4S(R2), ICH S7B

### DPO Pipeline Built

Three-stage RL pipeline for iterative improvement:

```
Stage 1 — Collect failures:
  python scripts/collect_dpo_training_data.py --audit-failures
  → data/regulatory_training/dpo/rejected.jsonl

Stage 2 — Generate clean alternatives:
  python scripts/collect_dpo_training_data.py --gemini-pairs
  → data/regulatory_training/dpo/dpo_pairs.jsonl

Stage 3 — DPO alignment:
  python scripts/finetune_regulatory_llm.py --dpo \
    --dpo-data data/regulatory_training/dpo/dpo_pairs.jsonl \
    --resume models/regulatory_llm_v1/lora_adapter
  → models/regulatory_llm_v2_dpo/dpo_adapter/
```

**DPO Auditor rules** (10 rules in `collect_dpo_training_data.py`):

| Rule ID | Severity | Check |
|---------|---------|-------|
| CITE_001 | MAJOR | PBPK must cite EMA/CHMP/EWP/37498/2011 |
| CITE_002 | MAJOR | Genotoxicity must cite ICH S2(R1) |
| CITE_003 | MAJOR | Cardiac must cite ICH S7B |
| CITE_004 | MINOR | General must cite ICH M3(R2) |
| STYLE_001 | MAJOR | No FDA label headers (§12/§13) |
| STYLE_002 | MINOR | No bullet points/lists |
| LEN_001 | MAJOR | Output ≥ 100 words |
| LEN_002 | MINOR | Output ≥ 250 words (full section) |
| CONTENT_001 | MAJOR | PBPK must state EMA 67% criterion |
| CONTENT_002 | MAJOR | Genotoxicity must mention Ames test |
| CONTENT_003 | MAJOR | Cardiac must report hERG IC50 |

---

## 4c. V1 Regulatory Audit Results (post-training evaluation)

Ran `collect_dpo_training_data.py --audit-report` with v1 adapter on 50 test examples:

```
Overall: 27/50 pass (54%)
Avg output length: 294w
Avg MAJOR findings: 0.66

By section type:
  admet:       100% pass | 0.0 MAJOR | 290w avg   ← GOOD
  tox_overview: 100% pass | 0.0 MAJOR | 299w avg   ← GOOD
  overview:     86%  pass | 0.1 MAJOR | 288w avg   ← NEARLY THERE
  tox_genotox:   0%  pass | 1.2 MAJOR | 288w avg   ← FAIL: missing ICH S2(R1) + Ames
  pk_overview:   0%  pass | 1.7 MAJOR | 329w avg   ← FAIL: missing ICH M3(R2)
  pbpk:          0%  pass | 2.0 MAJOR | 308w avg   ← FAIL: missing EMA/CHMP + 67% criterion
```

**Key insight:** The 54% failure is *entirely* the citation rules (CITE_001–003, CONTENT_001–003).
The model produces correct-length regulatory prose — it just doesn't cite.
This confirms the v2 dataset fix (`_inject_citations()`) directly targets the root cause.

**v2 training started immediately after:**
- Dataset rebuilt with citation injection → 19.7% of targets now contain ICH citations (from 0.75%)
- 100% of prompts explicitly instruct citations
- Median output length target: 280w (from 151w — sliding window removed)
- Training: 3 epochs, ETA ~10 hours (batch 16 × 312 optimizer steps on GB10 PTX)

---

## 5. Next Steps (priority order)

### Immediate — before A/B testing

**1. Wire adapter into `_llm_narrative()` and run 76/76 gold standard**

```python
# In ind_assembly.py, add _call_local_regulatory_llm():
from transformers import AutoModelForCausalLM, AutoTokenizer
from peft import PeftModel

_LOCAL_MODEL = None
def _call_local_regulatory_llm(prompt: str, max_tokens: int = 512) -> str:
    global _LOCAL_MODEL
    if _LOCAL_MODEL is None:
        base = AutoModelForCausalLM.from_pretrained("Qwen/Qwen3-8B", device_map="auto")
        _LOCAL_MODEL = PeftModel.from_pretrained(base, "models/regulatory_llm_v1/lora_adapter")
    # ... generate and return
```

Then:
```bash
python3 backend/lib/galaxy/ai/drug_discovery/test_phase3_autoretrain_ind.py
```

**2. Human evaluation (5 documents)**

Generate §2.6.1–§2.6.3 for 5 held-out compound profiles. Score on the 5-dimension rubric (CTD compliance, scientific accuracy, regulatory interpretation, citation appropriateness, prose quality). Threshold for A/B: mean ≥ 3.5/5.

### v2 Training (data fixes first)

**Fix 1: Citation injection** — Add `"cite applicable ICH guidelines by their full identifier (e.g. ICH S2(R1), EMA/CHMP/EWP/37498/2011)"` to the system prompt. Expected to push citation recall from 0.75% to ≥20%.

**Fix 2: Output length** — Remove the 60-word context skip from the target. Generate from a full instruction prompt, not a continuation. Expected to push avg length from 152 → 350+ words.

**Fix 3: More EMA EPAR** — Expand from 188 → 1,554 catalogue entries. Expected: ~500 additional CTD-style examples, shifting the 85/14 FDA-label/CTD style ratio to ~60/40.

**Fix 4: Expert-written synthetic examples** — 50 hand-authored (structured data → §2.6 prose) pairs directly teaching the inference-time task. Highest value-per-example of any source.

### v3+ Training (after v2 validated)

- DPO alignment on audit failures (reject MAJOR-finding outputs, prefer corrected versions)
- Expand regulatory QA to 100 curated pairs (currently 12)
- Add PMDA/NMPA native examples

---

## 6. Known Open Issues

| Issue | Severity | Workaround |
|-------|---------|-----------|
| Citation recall 0.75% | High | Gemini fallback; fix in v2 training |
| Output length 151w vs 300–600w target | High | Post-process: concatenate multiple generations |
| FDA label style vs CTD style | Medium | Human review catches; fix in v2 data |
| S7B(R1) 2024 not collected (URL unavailable) | Low | S7B 2005 covers 95% of same content |
| GB10 sm_121 UserWarning in NGC 24.10 | Info only | Functional despite warning; NGC 25.04 would be native |
| tox_cardiac: only 3 training examples | Medium | Expand carcinogenicity/cardiac data in v2 |

---

## 7. File Inventory

```
scripts/
  collect_regulatory_training_data.py   # Data collection, 8 sources, auto-discovers PDFs
  build_training_pairs.py               # ChatML pair construction (v2 design)
  finetune_regulatory_llm.py            # QLoRA training, TRL 1.x compatible

data/regulatory_training/
  ich_guidelines/raw/ich/              # 17 ICH + FDA/EMA PDFs
  epar/epar_examples.jsonl             # 276 EMA EPAR nonclinical sections
  hc_sbd/hc_sbd_examples.jsonl        # 500 openFDA drug label sections
  ich_guidelines/ich_guidelines_examples.jsonl  # 1,186 ICH guidance sections
  fda_nda/fda_nda_examples.jsonl       # 9 FDA NDA review sections
  combined_regulatory_training.jsonl   # 1,971 merged raw examples
  tasks/splits/train.jsonl             # 2,093 training pairs (3× augmented)
  tasks/splits/dev.jsonl               # 256 dev pairs
  tasks/splits/test.jsonl              # 273 test pairs

models/regulatory_llm_v1/
  lora_adapter/adapter_model.safetensors  # 167 MB trained adapter
  lora_adapter/adapter_config.json
  eval_metrics.json                    # {rouge_l: 0.237, citation_recall: 0.008}
  training_manifest.json               # Full config + 474.7 min training time
  checkpoint-200/                      # Intermediate checkpoint
  checkpoint-249/                      # Final checkpoint (= lora_adapter)

docs/
  20260505_REGULATORY_LLM_TRAINING_PROGRESS.md   # This file
  20260505_REGULATORY_LLM_TRAINING_DESIGN.md     # Task/dataset/eval design
  20260505_ICH_GUIDELINE_REFERENCE.md            # ICH guideline reference
  20260504_REGULATORY_LLM_DATASETS_AND_RESOURCES.md  # All public resources
  20260504_REGULATORY_LLM_TRAINING_PIPELINE.md  # Session 1 log
```
