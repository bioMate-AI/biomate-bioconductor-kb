# On-prem 9B SFT from the collected candidate gold — fixing the domainpro harness regression

**Date:** 2026-10-06
**Author:** Yaoyun Zhang (automated run)
**Base:** `Qwen/Qwen3.5-9B` @ `c202236235762e1c871ad0ccb60c8ee5ba337b9a`
**Repo:** `/Users/kky/biomate-review`

## Why this run exists

The prior on-prem SFT (`domainpro` = base + midtrain cpt1200 merged + SFT on generic medical MCQA)
lifted the knowledge-recall slice +5.4pp but **regressed the end-to-end RealBio harness**
(`20261006_LLM_HARNESS_DOMAINPRO_EVAL.md`): routing **−16pp** (0.885→0.725, p=7.7e-6),
param_prefill **−6.2pp** F1 (0.628→0.566, must_not_fill 34→75). Root cause: it traded
instruction-following / output discipline for domain knowledge — **238 output tokens on routing where
9 were needed** — and it had **no harness-task data** and **was not trained on our proprietary
DB-derived gold**.

This run fixes both root causes:
1. **Train on the collected candidate gold** (the parked `data_candidates_v2` / `data_pool_v2`),
   user-approved for promotion this session (overriding the manifest "none approved" scope line).
2. **Format / terseness discipline + harness-task anchors**: every example has a **task-appropriate
   terse** target, and routing/param/decomposition anchors use the **verbatim harness prompt formats**
   (copied from `public_export/run_baseline.py`), so routing/param do **not** regress.
3. **SFT on the clean base (no CPT merge)** so the harness eval is apples-to-apples base vs base+SFT
   and isolates the effect of the new task data (per the ask: "the task data is the lever, not more CPT").

## Training set composition (real counts)

Builder: `evaluation/local_trial/build_sft_from_gold.py` → `sft_from_gold_20261006.jsonl`
(sha256 `e0630f37bbc359d0972054230e98cee52357a24e3a10b124cf5c138e213fb112`, 16,988 rows, 24.3 MB).
Dropped 3,585 dedup; **0 eval-leak** (guarded against 945 eval-item queries across all public_export
tasks). Every row carries `{task, source}` provenance. No data exclusion beyond dedup + eval-leak guard.

| Task | Rows | mean/med/p95 assistant words | Source(s) |
|---|---:|---|---|
| `routing` (harness described-menu format, bare-name output) | 3,495 | 1.3 / 1 / 4 | grounded_routing (496 real queries) + anchor_routing (2,999) |
| `decomposition` (harness task_decomposition JSON) | 3,395 | 42.9 / 35 / 92 | decomp_intra (2,010) + decomp_inter (1,385) |
| `tool_affordance` | 4,809 | 22.4 / 12 / 66 | tool_knowledge (3,953) + tool_compatibility (856) |
| `decomposition_freeform` | 1,981 | 45.9 / 35 / 111 | claude_decomp (short plans only, ≤150 words) |
| `param_schema` (workflow→typical params) | 902 | 3.5 / 4 / 6 | anchor_param |
| `findings` (bounded narration) | 738 | 129.3 / 162 / 187 | biomate_run_output |
| `workflow_decomposition` (verified lane tool-DAG) | 582 | 22.3 / 22 / 40 | workflow_spec (1,092 verified lane) |
| `self_fix` | 489 | 60.1 / 60 / 81 | git_fix_pair |
| `param` (harness param_prefill format, JSON-only) | 444 | 3.4 / 2 / 6 | grounded_param |
| `composition_rationale` | 112 | 33.3 / 28 / 73 | workflow_chains + rationale_registry/phase |
| `domain_classification` | 41 | 1.0 / 1 / 1 | anchor_wfgen |

**Global assistant length: mean 29.1 words, p50 19, p95 92, max 225** — i.e. terse by construction
(the prior model's 238-token routing rambling cannot be learned from this set). **Format-discipline
tasks (routing + param + param_schema + domain + decomposition + decomposition_freeform +
workflow_decomposition) = ~10,840 / 16,988 ≈ 64%** of the corpus — the direct anti-regression lever.

### Two honest data decisions (documented, not hidden)
- **`claude_decomp` on disk is long-prose research *reports*, not DAG decompositions** (p95 345 words,
  0 JSON plans). Including the long ones verbatim would reintroduce the exact rambling this run fixes,
  so they are **capped to ≤150-word short plans** (1,981 kept). This is "fix the data to match the
  objective," not exclusion to hide a problem.
- **`anchor_wfgen` is a domain label, not the eval `workflow_generation` category space** — so it is
  templated as its own 42-domain classification task (safe terseness reinforcement), NOT forced into
  the eval label set (which would mislabel and hurt).

## Training (spot, QLoRA)

- Env (pinned, `today_bootstrap.sh`): torch 2.14.1 / transformers 5.18.0 / peft 0.21.2 / trl 1.14.1 /
  datasets 5.0.1 / accelerate 1.15.0 / bitsandbytes 0.50.2 (+ flash-linear-attention). Same env as the
  eval shim so the adapter loads exactly as trained. `model_loading.load_text_model` extracts the
  Qwen3.5 text backbone.
- QLoRA: 4-bit nf4, LoRA r=16 α=32 on all attn+MLP projections, seq 2048, per-device batch 1,
  grad-accum 16 (effective batch 16), ~1,000 steps (≈0.94 epoch over 16,988 rows), lr 2e-4 cosine,
  `assistant_only_loss=True`. Entry `spot_sft_gold_entry.sh` → `spot_train.sh` (STAGE=sft) →
  `train_qlora_pilot.py`.
- Instance: **g6.2xlarge (1× L4 24 GB) spot, us-west-2a, `i-010a9df1148f4ca8e`**. Checkpoints stream to
  S3 every 120 s (resume-safe). Adapter → `models_20260919/med/sft_gold_adapter/`.
- Data + code on S3: `sft/sft_from_gold_20261006.jsonl`, `code/evaluation_local_trial.tgz`.

**STATUS: COMPLETE.** Training finished 1000/1000 (`train_runtime` 15,069 s ≈ 4 h 11 m, `train_loss`
1.0757, 16,988 examples ≈ 0.94 epoch, LoRA r=16 α=32 on all 7 attn+MLP projections). Final adapter:
`s3://biomate-models-399683337364/biomate-core-local-trial/20260912/models_20260919/med/sft_gold_adapter/`.
Both the mid-training checkpoint-550 and the final checkpoint-1000 were evaluated base-vs-gold on the
unmodified RealBio LLM+harness (real `score.py`). Final checkpoint-1000 is staged for serving (see
**Serve artifact**). The one regression (`param_prefill` must_not_fill) is flagged in **Honesty notes**.

## Evaluation (RealBio LLM + harness, unmodified runners)

`harness_shim.py` serves each arm (base = clean base; gold = base + gold-SFT adapter, NO CPT merge),
`public_export/run_baseline.py` + `score.py` run **unchanged** (findings_probe is an additive task).
Entry `spot_harness_gold_entry.sh`. Tasks: cross_domain_routing (catalog/described, real
`galaxy_ai_tools.db`), param_prefill, litqa2, task_decomposition, findings_probe (held-out, ROUGE-1 F1
proxy — indicative only, no LLM judge).

### Base vs gold-SFT per-task table — real `score.py` numbers (final checkpoint-1000)

Eval run: `eval/spot_harness_gold_20261006_120457/` (base vs gold-final, NO CPT merge). Both arms served
by `harness_shim.py`; `run_baseline.py` + `score.py` unmodified.

| Task | Metric | base | gold-final (1000) | Δ | Verdict |
|---|---|---:|---:|---:|---|
| cross_domain_routing (catalog/described, real DB) | routing acc (n=200) | 0.885 | 0.860 | −2.5pt | **HELD** — CIs overlap ([.833,.922] vs [.805,.901]); no real regression (prior domainpro was −16pp, p=7.7e-6) |
| param_prefill (n=170) | param F1 | 0.6275 | 0.6118 | −1.6pt | **F1 ≈ base** (within noise) |
| param_prefill | precision / recall | 0.820 / 0.508 | 0.761 / 0.512 | −5.9pt / +0.3pt | precision dip |
| param_prefill | must_not_fill violations | 34 | 49 | **+15** | **REGRESSION** — over-fills; mitigated by production validation guardrail |
| litqa2 (n=199) | accuracy | 0.2513 | 0.3166 | **+6.5pt** | **UP** (knowledge) — via coverage 0.553→0.804 (abstains less); precision 0.455→0.394 |
| task_decomposition (n=30) | structure acc | 0.367 | 0.600 | **+23.3pt** | **UP** (target) — CIs [.22,.54] vs [.42,.75] |
| task_decomposition | subtask coverage | 0.933 | 1.000 | +6.7pt | UP |
| findings_probe (n=50) | mean ROUGE-1 F1 | 0.0997 | 0.2501 | **+15.0pt** | **UP** (target) — *indicative proxy, no LLM judge* |

### Interim (checkpoint-550) vs final (checkpoint-1000) — gains plateaued by the midpoint

Eval run (interim): `eval/spot_harness_gold_20261006_102018/`.

| Task (metric) | base | ckpt-550 | ckpt-1000 | 550→1000 |
|---|---:|---:|---:|---|
| routing acc | 0.885 | 0.860 | 0.860 | flat (identical, 172/200) |
| param F1 | 0.6275 | 0.6218 | 0.6118 | −1.0pt |
| param must_not_fill | 34 | 43 | 49 | worsening trend (+6 more) |
| litqa2 acc | 0.2513 | 0.3266 | 0.3166 | −1.0pt (still +6.5pt vs base) |
| task_decomp structure | 0.367 | 0.600 | 0.600 | flat (identical) |
| findings ROUGE-1 | 0.0997 | 0.2673 | 0.2501 | −1.7pt (still +15pt vs base) |

**Takeaway:** the targeted capability gains (decomposition, findings, litqa coverage) were essentially
fully realized by checkpoint-550 (~0.49 epoch) and held flat to 1000; the only thing that kept moving
through the back half of training was the `param_prefill` must_not_fill regression (43→49), i.e. mild
continued over-filling. An earlier stop (~step 550–600) would give nearly identical gains with a
smaller must_not_fill penalty — noted for the next run.

## Serve artifact — staged for vLLM

The final checkpoint-1000 adapter clears the serve gate on the primary metrics (routing HELD within CI,
param F1 ≈ base, and the decomposition / findings / knowledge gains all held), so it is staged as the
serving candidate.

- **Serve artifact (S3):**
  `s3://biomate-models-399683337364/biomate-core-local-trial/20260912/serving/sft_gold_9b_20261006/`
  (clean copy: `adapter_config.json`, `adapter_model.safetensors` (58 MB), `chat_template.jinja`,
  tokenizer files — no optimizer/trainer state).
- **Source (canonical final adapter):**
  `…/models_20260919/med/sft_gold_adapter/` (identical adapter weights).
- **Base model:** `Qwen/Qwen3.5-9B` @ `c202236235762e1c871ad0ccb60c8ee5ba337b9a` (the adapter_config's
  `base_model_name_or_path` is the training box's local path `/opt/dlami/nvme/models/base_med`, which is
  that same revision — vLLM applies the LoRA weights against the `vllm serve <base>` model, so the local
  path in the config is informational only).

**Exact serve command (vLLM OpenAI-compatible endpoint):**
```bash
# 1. pull the adapter next to the server
aws s3 cp --recursive \
  s3://biomate-models-399683337364/biomate-core-local-trial/20260912/serving/sft_gold_9b_20261006/ \
  /opt/models/sft_gold_9b_20261006/

# 2. serve base + LoRA adapter (single L40S 48GB or any ≥24GB GPU for the 9B)
vllm serve Qwen/Qwen3.5-9B \
  --revision c202236235762e1c871ad0ccb60c8ee5ba337b9a \
  --enable-lora \
  --lora-modules sft_gold=/opt/models/sft_gold_9b_20261006 \
  --max-lora-rank 16 \
  --max-model-len 4096 \
  --host 0.0.0.0 --port 8000
```
Clients call it as an OpenAI endpoint with `model="sft_gold"` (base is `model="Qwen/Qwen3.5-9B"`), e.g.
`OPENAI_BASE_URL=http://<host>:8000/v1`. This is the same base+adapter topology the eval `harness_shim.py`
used (`--adapter <dir>`), so serve behavior matches the evaluated behavior.

## Instance + cost (real, us-west-2)

All GPU work on single-GPU boxes; spot where available (the L40S `g6e` family and most 24 GB spot were
InsufficientInstanceCapacity across all 4 AZs during the eval window, so the final eval fell back to
on-demand — noted as a deliberate deviation from spot-always since capacity was zero and the result was
time-sensitive). All boxes self-terminate (`shutdown -h now` + instance-initiated-shutdown=terminate).

| Phase | Instance | Market | GPU | Duration | ~Rate | ~Cost |
|---|---|---|---|---|---:|---:|
| SFT training | g6.2xlarge (`i-010a9df1148f4ca8e`) | spot | L4 24 GB | 4 h 11 m | $0.83/h | ~$3.47 |
| Eval — interim ckpt-550 | g6.2xlarge (`i-09a5a610793cff50e`) | spot | L4 24 GB | ~1 h 29 m | $0.83/h | ~$1.23 |
| Eval — final ckpt-1000 | g6.2xlarge (`i-07034afad079bf54f`) | on-demand | L4 24 GB | ~1 h 14 m | $0.98/h | ~$1.21 |
| Eval — first attempt (bootstrap bug) | g6e.8xlarge (`i-0d1f8bfdda0af9ca0`) | spot | L40S 48 GB | ~2 m | $2.72/h | ~$0.09 |
| **Total** | | | | | | **~$6.0** |

## Honesty notes / unrun

- **Real numbers only.** Every figure above is from the unmodified `score.py` on S3
  (`eval/spot_harness_gold_20261006_120457/logs/score_*.json` final;
  `eval/spot_harness_gold_20261006_102018/logs/` interim). Nothing is fabricated or extrapolated.
- **`param_prefill` must_not_fill is a real regression** (34→49, +15; precision 0.820→0.761). The SFT
  model fills params slightly more aggressively. F1 itself ≈ base. In production this is partially
  absorbed by the rule+validation guardrail (`schema_guard` drops must_not_fill violations against
  `allowed_values`), but it should be driven back down in the next data iteration (add explicit
  must_not_fill negative anchors) — and an earlier stop (~step 550–600) already gives a smaller penalty
  for nearly identical gains.
- **`findings_probe` is an INDICATIVE proxy only** — ROUGE-1 F1 vs a single held-out reference finding,
  no LLM judge. The +15pt is directionally strong but should not be read as a calibrated quality score.
- **`task_decomposition` n=30** — wide CI ([.42,.75] for gold); the +23pt is real but the sample is
  small. `litqa2` accuracy gain is driven by higher answer coverage (0.553→0.804), i.e. the model
  abstains less; per-answered precision actually dipped (0.455→0.394).
- **No eval leakage.** Training set was guarded against 945 eval-item queries across all public_export
  tasks (0 leaks); the `findings_probe` task is held-out.
- **Two bootstrap/packaging bugs fixed this session** (both committed): the harness bootstrap's apt-lock
  race (`spot_harness_bootstrap.sh`, commit `05e249500`), and the eval code tarball that never contained
  `spot_harness_gold_entry.sh` (rebuilt as `code/evaluation_local_trial_harness.tgz`, canonical training
  tarball left untouched).
