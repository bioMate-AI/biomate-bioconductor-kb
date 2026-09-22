# On-prem Qwen3-4B — corrected mid-training corpus, mixture run, and eval (2026-09-21)

**Honesty contract:** results below are reported as measured. The headline is that the
*dataset was corrected* (the session's goal) but the *mid-training pass did not close the
out-of-catalog gap* — and the reason is understood (a deliberately light pass + a retrieval
long-tail), not hidden.

## 1. Summary

Resumed the on-prem LLM work after a crashed session. Found the prior 4B `STAGE=full` run had
**completed** but left its result **orphaned** (the merged mid-trained base `base_domain` lived
only on spot NVMe and was never uploaded → the SFT adapter's base no longer existed). Root-caused
several issues, corrected the mid-training dataset, made the pipeline robust, trained a corrected
corpus + mixture model, and evaluated it.

## 2. Dataset correction (the core deliverable) ✅

The mid-training corpus that earlier runs trained on was **not the full prepared dataset**:

- `midtrain_all.jsonl` had been assembled (Sep 19 12:43) **before** `wkg_corpus.jsonl` was staged
  (Sep 19 13:51) → the Workflow-Knowledge-Graph corpus was silently dropped.
- The concat excluded `internal_corpus.jsonl` entirely (to avoid tool-dup vs `tools_corpus`), which
  also dropped its **workflow descriptions + Bioconductor/expert skills** text.

Rebuilt via `build_full_midtrain_corpus.sh` on a cheap CPU disk box:

| source | ~tokens |
|---|---|
| code (Nextflow/Bioconductor/workflow_json) | 17.24M |
| tools (verbalized) | 16.73M |
| chebi/go/hpo/so/edam (ontologies) | ~7.9M |
| gtn | 1.62M |
| **internal_wf_skill** (recovered) | 1.55M |
| workflow_order/db_kg/hetionet | ~1.1M |
| **wkg** (added) | 0.38M |
| **TOTAL** | **~46.4M / 173,583 docs** |

Matches the committee-v3 "44.9M corpus" target. Also built `general_replay.jsonl` (FineWeb-Edu,
550k docs, ODC-BY) for the anti-forgetting mixture. peS2o literature deferred (needs
`trust_remote_code=True`; external, not part of the prepared core). All staged to S3
`midtrain_corpus/`.

## 3. Pipeline fixes (committed)

- `7579d0208` — persist merged `base_domain` + midtrain adapter to S3 in the `full` stage (fixes the
  orphaning bug; result now recoverable/evaluable).
- `4c2e7a2d5`-era + this session — `TAG` namespacing + `FETCH_REPLAY` for A/B variants.
- multi-GPU: `torchrun` DDP + `--batch-size`/`--grad-accum` + DDP-safe device_map. **DDP is still
  broken** (both steps died, no child traceback) → added `--tee/--redirects` for next diagnosis +
  `FORCE_NGPU` to pin single-process. **Reliable path = single-GPU.**
- resume-safe `full` stage (skip midtrain if `base_domain` built; resume nested midtrain/SFT ckpts) →
  lossless on-demand↔spot switch.
- OOM fix: `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True` + `BS=2` on 24GB cards (packed-logits
  allocation blew the L4).
- perf: `attn_implementation` eager→**sdpa** (eager was pathologically slow) + seq-1024 → **9.6 s/it
  on L40S** (vs 44s eager, 66s A10G).

## 4. Training run — completed ✅

`qwen-small-full_mix` (`STAGE=full TAG=_mix`), corrected corpus + **50/50** replay mixture,
BS=2 GA=8, seq-1024, MID=800 + SFT=500. Survived a spot reclaim mid-run (auto-relaunched on L40S,
**resumed from checkpoint**). Outputs in S3 `models_20260919/small/`:

- `base_domain_mix/model.safetensors` (8.04 GB, merged mid-trained base — persisted)
- `full_mix_adapter/` (66 MB SFT adapter), `midtrain_adapter_mix/` (66 MB)
- MIDTRAIN_DONE loss 2.12 → PILOT_DONE (SFT) loss 0.497.

## 5. Eval — measured, NOT a win ⚠️

Out-of-catalog removal eval (80 cases, `eval_removal.py --direct`, OpenAI coverage judge):

| metric | value |
|---|---|
| micro step-coverage | **0.273** |
| macro step-coverage | 0.269 |
| nonzero-mean coverage | 0.428 |
| nonzero fraction | 0.637 |
| composed_rate | 1.00 |
| validity_rate | 0.925 |

- **Flat vs v2 (~0.30), still below the 0.54 frontier baseline.**
- Format health good (composed 1.0, validity 0.925 — no mode collapse).
- Per-domain strong: pharmacology 0.60, single_cell 0.39, metagenomics 0.39. Weak:
  synthetic_biology 0.0, proteomics 0.10, systems_biology 0.11, genomics 0.17.

### Why it didn't move
1. **Light mid-training dose.** Speed cuts (MID=800, seq-1024, replay-0.5) → only ~6–7M domain
   tokens seen (~14% of the 46.4M corpus). A partial pass cannot close a 0.24 gap. The dataset is
   right; the dose was too small.
2. **36% zero-coverage tail is a retrieval failure**, not a knowledge gap (committee dual-sparsity).
   Common workflows (`edger_classic`, `rgsea`) scored 0 → the removal harness/retriever isn't
   supplying the right tool blocks. Mid-training can't fix the retriever half.

## 6. Next steps

1. **Apples-to-apples control** — eval SFT-only (`sft_adapter`, raw base) on this same harness to
   isolate mid-training's true effect on one metric (v2's 0.30 may be a different metric version).
2. **Full-dose mid-training** — MID high enough to cover the corpus 1–2× at seq-2048 (L40S ~9.6 s/it
   makes an overnight pass feasible).
3. **Retriever grounding** (committee #4) — inject WKG 1-hop precede/succeed + fix family-holdout
   recall; this attacks the 36% zeros.
4. **Multi-GPU DDP** — diagnose with the now-captured child traceback; optional (single-GPU works).

## 7. Infra lessons (reusable)
- Spot GPU capacity in us-west-2 can go fully dry across all families for hours; auto-retry across
  types/AZs + on-demand bridge + checkpoint-safe switch is the working pattern.
- `attn_implementation="eager"` is a ~5–8× slowdown vs `sdpa` for these Qwen models.
- 24GB cards need `expandable_segments` + `BS=2` for a 4B at seq-2048 (packed logits).
- multi-GPU QLoRA DDP is not working in these scripts yet (undiagnosed; single-GPU is the reliable path).
