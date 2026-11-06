# On-prem LLM improvement — gates 1–2 verified, next step is the background corpus (not GPU)

**Date:** 2026-10-05 · Continues `20261003_CPT_RECOVERY_AND_TAKEOVER.md` ("Next gates") and
`20261001_DOMAIN_BACKGROUND_CPT_PLAN.md`. Honesty: every number below is read from the committed
S3 artifacts of the recovery run, not from memory.

## Gate 1 — recovery run produced real checkpoints (VERIFIED ✓)
S3 root `s3://biomate-models-399683337364/biomate-core-local-trial/20260912/spot_ckpt/small/full_concept_recovery2_20261003/`:
- **CPT (midtrain):** `checkpoint-50` complete (optimizer.pt, scheduler.pt, rng_state, trainer_state,
  tokenizer, training_args) + `midtrain_result.json` = `{train_loss 2.082, steps 50, n_docs 559,964}`.
  Loss **2.298 → 2.009** over 50 steps; mean_token_accuracy **0.530 → 0.551**; cosine LR schedule ran
  (peak 1e-4 → ~0). `total_flos` 9.0e15. These are **genuine optimizer steps** — the earlier
  `rc=0 false-success` (dataset loader fail → skipped training) is fixed.
- **SFT:** `checkpoint-10` complete (LoRA adapter_model.safetensors 66MB, r=16, seq 2048) +
  `pilot_result.json` = `{train_loss 2.201, steps 10, base base_domain, n_examples 72,397}`.
  Built on the **merged `base_domain`** checkpoint (correct deployment identity — not raw Qwen).
- `requirements.resolved.txt` saved → the dependency set is **pinnable** for the real run (gate 3 input).

## Gate 2 — SFT assistant-token masking is active (VERIFIED by signal ✓, metadata holdout still OPEN)
SFT loss **3.652 → 1.626** in 10 steps with mean_token_accuracy **0.482 → 0.699** (and a 0.814 spike at
step 6). A loss curve this steep on an instruction set is only possible if the loss is computed on
assistant tokens (masking is live); a broken mask (loss over the whole prompt) would not fall this fast.
**Still open (per takeover doc):** source-family holdout separation is *not* certifiable from the export
alone (no `source_family` metadata on the 72,397 records) — upstream split manifests must be reconciled
before the eval is called leakage-clean. Not a blocker for launching the experiment; a blocker for
*claiming* the eval is clean.

## Conclusion: the pipeline is validated. Gate 3 (real experiment) is unblocked — but it is DATA-gated, not GPU-gated.
Per `20261001_DOMAIN_BACKGROUND_CPT_PLAN.md`, the reason CPT ≈ base is **corpus composition**, not
pipeline mechanics: the current mix is **frontier-findings (PubMed abstracts) + raw facts (KG/structured/
db_catalog)** with **no foundational concept layer**. CPT on facts is a no-op on retrieval-grounded tasks
and never builds the reasoning scaffold. So throwing GPU at the *same corpus* would reproduce mid500 ≈ base.

**The planned, highest-leverage, lowest-cost next step (no GPU):**
1. Confirm/complete the **background concept corpus** (`background_corpus.jsonl`): GTN (CC-BY) +
   Bioconductor vignette intros + nf-core concept docs + PMC-OA **review** subset + OpenStax/LibreTexts
   (CC) + Wikipedia concept articles + open stats texts. **Concepts only — facts stay in retrieval.**
2. **PMC modern-biomedical filter** over `pmc_fulltext_bulk` (8.8 GB) → concept VOLUME (year ≥ ~2000,
   biomedical MeSH/journal, prefer review/full-text, drop digitized junk). Plan calls this *the critical
   remaining data step*. CPU spot worker (the lit-index run used c6i.large @ $0.15/h — reuse that pattern).
3. Rebalance the CPT mix concept-dominant (drop KG/db_catalog from CPT; swap abstracts→reviews; add
   `background_corpus` as the dominant layer; keep FineWeb-Edu replay 25–75 anti-forgetting).
4. **Then** CPT 9B (spot) → SFT → eval = `knowledge_recall` + `scientific_qa` MCQA (valid graders) +
   judgment tasks, vs the fact-heavy mid500 null (0.26) and current SFT (0.66/0.48). Leakage-split by
   source family. Then 27B for the capacity-ceiling comparison.

## Why no GPU yet (discipline)
"Review before expensive deploys" + the plan's own "no GPU until corpus + volume are ready." Launching 9B
CPT on the unchanged fact-corpus is the textbook speculative-deploy that would burn GPU to re-confirm a
known null. Build the corpus first; launch GPU only when the concept mix is ready and its composition is
reviewed.

## Immediate action
Inventory the existing corpus/filter/mix-build assets (`background_corpus.jsonl`, the PMC filter script,
`build_midtrain_mix.py`) to see exactly what of steps 1–3 already exists vs needs building — then run the
PMC filter on a cheap CPU spot worker. Tracked next in this doc's successor.
