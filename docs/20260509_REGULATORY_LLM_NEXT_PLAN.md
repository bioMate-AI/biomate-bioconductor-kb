# Regulatory LLM — Next Phase Plan

**Date:** 2026-05-09  
**Current state:** v4 adapter active (92% audit, 13% citation_recall, ROUGE-L 0.576)

---

## Priority 1 — Replace citation_recall with LLM judge (1 day)

**Why:** citation_recall is substring matching; tells us nothing about citation
correctness or contextual appropriateness. The 13% number is uninterpretable
without knowing whether citations land in the right sections.

**What:**
- Add `evaluate_regulatory_citation_accuracy()` to `scripts/finetune_regulatory_llm.py`
- Use existing `evaluation/core/llm_judge.py` (Claude Haiku primary, Gemini Flash fallback)
- Judge prompt: given (section_type, generated_text), rate 3 binary signals:
  1. `correct_guideline` — cited guideline governs this section type (not just present)
  2. `contextual_placement` — citation appears adjacent to a relevant claim
  3. `no_hallucinated_citation` — no guideline cited that doesn't exist or doesn't apply
- Run on all 34 tox_genotox + 26 pk_overview + 31 tox_overview test examples
- This replaces the noisy 5-sample audit; gives reliable per-section signal

**Files:** `scripts/finetune_regulatory_llm.py`, `scripts/evaluate_regulatory_llm.py` (new)

---

## Priority 2 — Retrieval-based ICH citation guardrail (2 days)

**Why:** `_regulatory_guardrails()` currently only injects missing citations as a
footer footnote. It doesn't verify that the cited guideline actually governs the
claim. A retrieval check catches wrong-section citations before the document is
assembled.

**What:**
- Build `_verify_citation_against_corpus(citation_id, claim_text)` in ind_assembly.py
- Index the 17 ICH PDFs in `data/regulatory_training/ich_guidelines/raw/ich/` with
  BM25 (rank_bm25, already in backend deps) — no GPU needed
- At post-generation in `_regulatory_guardrails()`: for each citation found in text,
  retrieve top-3 chunks from that guideline's text; check if the claim is grounded
- If claim not grounded → flag as `CITATION_UNGROUNDED` warning (not removed, flagged)
- Separate from the injection guardrail: injection adds missing citations, retrieval
  verifies existing ones

**Files:** `backend/lib/galaxy/ai/drug_discovery/ind_assembly.py`,
`backend/lib/galaxy/ai/drug_discovery/ich_corpus.py` (new)

---

## Priority 3 — DPO alignment now that classifier is fixed (3 days)

**Why:** The section classifier carcinogenicity/tox_genotox bug was the root cause of
all DPO pairs having identical chosen=rejected text. Now that it's fixed, DPO pairs
can be properly collected and used for alignment training.

**What:**
- Re-run `scripts/collect_dpo_training_data.py` on v4 outputs:
  - Generate text with v4 adapter (chosen = passes audit)
  - Generate text with base Qwen3-8B (rejected = fails audit)
  - Collect ~200 (chosen, rejected) pairs per failing section type
- Focus on tox_genotox (still 20-30% audit pass) — needs citation alignment most
- Train v5 with SFT (v4 data) + DPO (new pairs), 2-3 epochs DPO phase

**Files:** `scripts/collect_dpo_training_data.py`, `scripts/finetune_regulatory_llm.py`

---

## Priority 4 — Complete §2.6.4–2.6.6 sections (2 days)

**Why:** The sections list in `assemble()` declares "2.6.4", "2.6.5", "2.6.6" but
the parts list only has tabulated study summaries. The three written summary
sections are missing:
- §2.6.4 Pharmacology Written Summary
- §2.6.5 Pharmacokinetics Written Summary  
- §2.6.6 Toxicology Written Summary

ICH M4S(R2) requires all six written summaries. Currently the DOCX output is
missing ~40% of the required document structure.

**What:**
- Add `_section_2641_pharm_written()`, `_section_2651_pk_written()`,
  `_section_2661_tox_written()` methods to INDAssembler
- Wire into `assemble()` parts list
- These are shorter tabulated formats (not LLM prose) — extractable from campaign data

**Files:** `backend/lib/galaxy/ai/drug_discovery/ind_assembly.py`

---

## Priority 5 — v5 training (after P1-P3, ~1 week out)

**Dataset for v5:**
- Clean v4 dataset (1727 pairs) as SFT base
- DPO pairs from P3 (~200 pairs, tox_genotox focused)
- Expanded tox_genotox SFT: curate 50 high-quality single-study genotox summaries
  from FDA NDA reviews (manually extracted from the 5 available PDFs)
- Expected: tox_genotox audit 20%→>70%, citation_recall >20%

---

## What NOT to do next

- **More training runs** without DPO or new data — v4 is at the SFT ceiling for
  this dataset; another SFT run won't move tox_genotox past 30%
- **Expand raw corpus further** before fixing the evaluation signal — adding more
  data without a reliable eval metric is shooting in the dark
- **Full §2.6 document testing** until the LLM judge is in place — we can't
  measure what we can't evaluate

---

## Start order

1. P1 (LLM judge) today — fast, unblocks measurement of all future work
2. P2 (retrieval guardrail) in parallel — independent of P1
3. P4 (§2.6.4-2.6.6) after P2 — uses same IND assembly code path
4. P3 (DPO) after P1 is producing reliable scores to validate DPO effectiveness
5. P5 (v5 training) after P3 DPO pairs ready
