# Regulatory LLM — Implementation Handoff

**Date:** 2026-05-14
**Purpose:** Capture all open requirements so this work can be resumed by anyone (or any session) without re-deriving the state.
**Status:** v6 trained and production-wired (eval 4/5 checkers above target); v7 DPO in progress; v8 China-market enrichment staged but not run.

---

## What is done

| Component | Status | Where |
|---|---|---|
| 9 deterministic checkers (FDA reviewer checklist v2) | ✅ all built | `backend/lib/galaxy/ai/drug_discovery/*.py` |
| 5 checker-grounded synthetic SFT task generators | ✅ 2,688 examples | `scripts/generate_*_sft_task.py` |
| v6 SFT training | ✅ complete | `models/regulatory_llm_v6/lora_adapter` |
| v6 evaluation | ✅ 4/5 above target | `evaluation/results/regulatory_v6/summary.json` |
| §2.6.2 / §2.6.4 / §2.6.6 written-summary builders | ✅ in production | `ind_assembly.py:section_26*` |
| Production wiring (v6 auto-loaded) | ✅ done | `_resolve_adapter_path()` |
| Synthetic DPO pair pool | ✅ 2,658 pairs | `data/regulatory_training/dpo/synthetic_pairs.jsonl` |
| TGA AusPAR scraper | ✅ committed | `scripts/scrape_auspar_nonclinical.py` |
| Health Canada SBD scraper | ✅ committed | `scripts/scrape_canada_sbd.py` |
| NMPA CDE scraper | ✅ committed | `scripts/scrape_nmpa_cde_reviews.py` |
| UI design v2 for Claude Design | ✅ committed | `docs/20260512_REGULATORY_LLM_STUDIO_UI_V2.md` |
| Pipeline reference doc | ✅ committed | `docs/20260512_REGULATORY_LLM_V6_V7_PIPELINE.md` |

---

## What is in progress

### Rejection-sampling DPO pair collection
- **Running:** Docker container `v6-rs` (`fa5b1fd560dc`)
- **Target:** ~50 phase_gating pairs from v6 real failures
- **ETA:** ~3hr
- **Command in case it dies:**
  ```bash
  docker run --rm -d --gpus all --ipc=host --ulimit memlock=-1 \
    --ulimit stack=67108864 -v "$PWD":/workspace -w /workspace \
    --name v6-rs biomate/regulatory-llm-train:latest \
    python scripts/build_dpo_pairs.py \
      --mode rejection-sample \
      --adapter models/regulatory_llm_v6/lora_adapter \
      --task phase_gating \
      --max-pairs 50 --n-samples 4 \
      --out data/regulatory_training/dpo/rejection_pairs_phase_gating.jsonl
  ```

---

## What is queued (ready to run, needs nothing creative)

### v7 DPO training

**Prerequisite:** rejection-sampling completes (above).

```bash
# 1. Merge synthetic + rejection-sampled pairs
cat data/regulatory_training/dpo/synthetic_pairs.jsonl \
    data/regulatory_training/dpo/rejection_pairs_phase_gating.jsonl \
    > data/regulatory_training/dpo/merged_pairs.jsonl

# 2. Train v7
bash scripts/train_v7.sh data/regulatory_training/dpo/merged_pairs.jsonl

# 3. Evaluate v7
python scripts/evaluate_v6.py \
    --adapter models/regulatory_llm_v7/lora_adapter \
    --out evaluation/results/regulatory_v7/test_predictions.jsonl
```

**Expected lift:** phase_gating 70% → ~85%; other checkers unchanged or +1-2pp.

**Decision gate after eval:** if phase_gating < 80%, run a second rejection-sampling round targeting hERG/duration mistakes specifically.

### Real-distribution holdout test

**Prerequisite:** network access for scraping (current sandbox blocks egress to tga.gov.au, hres.ca, cde.org.cn).

On any network-connected host:

```bash
python scripts/scrape_auspar_nonclinical.py --seed
python scripts/scrape_canada_sbd.py --seed
# CDE: populate SEED_URLS with real review IDs first
python scripts/scrape_nmpa_cde_reviews.py --urls-file <real_cde_urls.txt>
```

Then run evaluate_v6 against the scraped corpus to measure distribution-shift performance — the gap vs synthetic-test pass rate is the single most important unknown.

---

## What needs human decisions

### v8 China-market enrichment

**Blocked on:**
1. **Decision:** ship v7 (English/FDA-EMA) to first customer first, or wait and bundle China readiness?
2. **Data:** ~200-500 real CDE review URLs needed before scraper produces useful data
3. **Quality control:** Chinese-fluent regulatory reviewer to validate generated zh-CN prose (or Chinese-language LLM judge in eval stack)

**Implementation plan when unblocked:**

1. Bilingual MRSD task variant (Chinese regulatory framing, same arithmetic) — 500 examples
   - New file: `scripts/generate_mrsd_sft_task_zh.py`
   - Mirror of task5 with translated prompts/responses; reuse `mrsd_verifier.py` unchanged
2. NMPA-specific checker
   - New file: `backend/lib/galaxy/ai/drug_discovery/nmpa_compliance.py`
   - Checks: ethnic bridging citation when WOCBP, Chinese GLP referencing for China-conducted studies, CDE technical guideline IDs
3. Translate ICH guideline citations in `ich_corpus.py` BM25 index to support Chinese citation patterns
4. v8 SFT mix: 5,892 (existing) + 500 (NMPA scraped) + 500 (bilingual MRSD) = ~6,900 stratified by language

### UI implementation

**Blocked on:** Claude Design build cycle. Spec is `docs/20260512_REGULATORY_LLM_STUDIO_UI_V2.md`.

Build priority (per spec):
1. Evaluate v2 tab — per-checker pass rates with drill-down
2. Task Generators tab
3. Fine-Tune pipeline view
4. DPO Pairs tab
5. Authoring modal (lowest priority)

Backend API endpoints needed (defined in spec):
```
GET /api/regulatory/generators
GET /api/regulatory/generators/:id/stats
GET /api/regulatory/dpo/pairs
GET /api/regulatory/training/jobs
GET /api/regulatory/evaluation/:version
```

### First-customer pilot

**Blocked on:** sales / partnership. No code work needed.

Required materials when pilot starts:
- Pilot agreement (template doesn't exist)
- Onboarding doc explaining what v6/v7 is good at and not good at
- A way for pilot user to upload nonclinical inputs and get a §2.6.x draft back
- Feedback capture (likely a simple form, or just observer notes)

---

## Deferred / nice-to-have

These are documented but not staged for execution:

1. **B1 numeric traceability checker** — requires `campaign_wetlab` table join. Higher effort than the 9 existing checkers.
2. **B2 unit specificity checker** — parsing AUC type, matrix, analyte. Needs unit grammar.
3. **Cross-section consistency (D1/D2) as RL reward** — exists as eval checker, not yet wired into training as a hard constraint.
4. **v8 RL training** — composite reward over all checkers. Only if v7 plateaus and a real customer has unmet asks.
5. **TipTap regulatory document editor** — frontend exists at `frontend/client/src/components/regulatory-document-editor.tsx` but never visually verified post-v6.
6. **PMDA (Japan) coverage** — same path as NMPA but Japanese sources. Lower priority than China by market size.

---

## Critical files for handoff

If someone picks this up cold, read these in order:

1. `docs/20260512_REGULATORY_LLM_V6_V7_PIPELINE.md` — architecture reference
2. `docs/20260509_FDA_REVIEWER_CHECKLIST_V2.md` — the 9-checker spec
3. `docs/20260510_DOCUMENT_GENERATION_APPROACH.md` — why checker-first generation
4. `docs/20260512_REGULATORY_LLM_STUDIO_UI_V2.md` — UI spec for Claude Design
5. `docs/20260514_REGULATORY_LLM_IMPLEMENTATION_HANDOFF.md` — this doc

Memory keys (for AI assistants): `project_regulatory_llm_v6.md`, `feedback_citation_metric.md` in `/home/yzhang/.claude/projects/-home-yzhang-biomate/memory/`.

---

## One-sentence "what is this" pitch

A regulatory LLM that drafts ICH M4 CTD Module 2.6 nonclinical sections, where every training example is provably correct against a deterministic FDA-reviewer-style checker — so the same code that filters training data also evaluates the model, guards inference, and rewards RL: a metric improvement is by construction a product-quality improvement.
