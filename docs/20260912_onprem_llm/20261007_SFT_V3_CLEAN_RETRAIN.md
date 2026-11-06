# 2026-10-07 — SFT v3 CLEAN retrain of the on-prem 9B (empty-mask root cause + fix)

**Goal:** one clean, correct v3 QLoRA SFT retrain of the on-prem 9B, scored on the
REAL-distribution decomposition benchmark. The prior v3 run was DEGENERATE (empty
assistant-loss mask → untrained adapter: `train_loss=0.0007`, `2.17 it/s` @ seq 2048,
cumulative `num_tokens≈4089`). Root cause had to be fixed BEFORE spending GPU.

Repo: `/Users/kky/biomate-review` (branch `cursor/tutorial-live-recording-and-report-editing-4ea7`).
Code fix commit: `5ae31cc03`.

---

## STEP 0 — Empty-mask root cause: FOUND, FIXED, PROVEN (local, no GPU)

### What the prior analysis assumed vs. what is actually true
The task framing was: "the degenerate v3 run trained on `base_med` (CPT base) whose
chat template lacks `{% generation %}` markers; the valid v2 run used the clean base
`Qwen/Qwen3.5-9B@c202236`, so just use the clean base."

**That framing is contradicted by the evidence.** Both the v2 and the degenerate-v3
training logs on S3 show `[spot] downloading base Qwen/Qwen3.5-9B` — i.e. **both runs
used the SAME clean base**, not `base_med`. The v3 launcher
(`run_sft_v3_real_9b.sh`) comment itself says "the clean base Qwen/Qwen3.5-9B @ c202236".
So the base is NOT the difference.

### The real root cause
`train_qlora_pilot.py` uses `SFTConfig(assistant_only_loss=True)`. TRL builds the
supervised-token mask via `tokenizer.apply_chat_template(..., return_assistant_tokens_mask=True)`,
which produces a **non-empty** mask **only when the chat template wraps the assistant
turn in `{% generation %}…{% endgeneration %}`**.

I pulled the exact tokenizer for `Qwen/Qwen3.5-9B` revision `c202236…` from HF and
inspected `chat_template.jinja`: it renders the assistant turn (lines ~89–130) with
**no `{% generation %}` markers** — only an `add_generation_prompt` branch (a different
thing). Tokenizing real v3 rows through it (transformers 5.x):

```
v2 data, ORIG template: empty mask = 300/300 rows, supervised = 0 / 97,065 tokens (0.0%)
v3 data, ORIG template: empty mask = 300/300 rows, supervised = 0 / 102,629 tokens (0.0%)
transformers warns: "return_assistant_tokens_mask==True but chat template does not contain `{% generation %}` keyword."
```

So **both** datasets yield an empty mask on the clean base's own template. The
box-side training logs confirm the signature: TRL's pipeline runs
`Building labels → Dropping fully masked examples`, and the degenerate v3 run ended
with cumulative `num_tokens≈4089` (~7 supervised tokens/step) at `2.17 it/s`,
`train_loss 0.0007`. (The "v2 worked" run accumulated ~5,000 supervised tokens/step at
~17 s/it, `loss 0.4–1.5` — an undefined, transformers/TRL-version-dependent fallback
that happened to populate a mask for the v2 mix but not the v3 mix. **Not something to
bet GPU money on.**)

### The fix (deterministic, version-independent)
`ensure_generation_markers()` in `train_qlora_pilot.py`: split the
`<|im_start|>assistant\n` header OUT of the supervised span, then wrap the assistant
body + any `tool_calls` + the closing `<|im_end|>` in a **balanced** `{% generation %}`
block. The tokenizer's `chat_template` is patched in-code at load time (so it is
version-independent of whatever fallback TRL/transformers would otherwise use). Raises
loudly if the known Qwen3.5 anchors are absent (a future template change can never
silently reintroduce the bug).

### Proof (the mandatory supervised-token count)
Operating on the **loaded** `tok.chat_template` (the exact object the trainer uses),
over 300+ real v3 rows:

```
render byte-equality (patched vs original): 500/500 identical  → NO train/serve drift
patched mask: empty rows = 0/500
supervised fraction: mean 29.8%, min 1.0%, max 84.7%
total supervised = 35,761 / 169,124 tokens (21.1%)
supervised span (row 0) = '<think>\n\n</think>\n\n[{"sub_task": …}]<|im_end|>\n'  (exactly the assistant body)
```

Additional belt-and-suspenders in the trainer:
- `assert_nonempty_mask()` runs **before any GPU step**: samples 64 rows, asserts
  supervised>0 and fraction≥2%, else exits non-zero (fail-fast, pennies not dollars).
  Validated: PASSES on the patched template (19.6% on 64 rows), RAISES on the original
  (0/16 rows, 0.0%).
- The existing post-train guard (exit 7 if `train_loss<0.05` or `steps/s>1.5`) is kept.
- LoRA adapter cast to bf16 before save (prior 116 MB fp32 → ~58 MB).

### Deployment of the fix
The box pulls a flat code tarball from S3. I took the **exact proven v3real tarball**
and swapped in ONLY the fixed `train_qlora_pilot.py` (291 files, all others byte-identical
to the proven run), and uploaded it:
- backup of pre-fix tarball → `code/evaluation_local_trial_sftv3real_prebugfix_20261007.tgz`
- fixed tarball → `code/evaluation_local_trial_sftv3real.tgz` (canonical, picked up by the launcher) and `…_sftv3real_maskfix.tgz`

---

## STEP 1 — TRAIN (in progress)

- Launcher: `run_sft_v3_real_9b.sh` with `TAG=_v3clean`,
  `SFT_DATA=sft_from_gold_v3_real_20261007.jsonl` (22,361 rows: v2 mix + 219 real decomp
  + 854 `must_not_fill` anchors).
- Base: `Qwen/Qwen3.5-9B @ c202236…`; seq 2048, lora-r 16, batch 1 × grad-accum 16,
  `SFT_OVERRIDE=550`, `SAVE_STEPS=25` (incremental S3 mirror), `WORKER_MAX_SECONDS=16200`.
- Infra: **SPOT-first**, cycles 10 instance types × 4 subnets, 6 h deadline, fast-fail
  boot-grace 420 s, resume-safe (checkpoints mirror to S3 every 120 s), self-terminates.
  One box at a time. Pre-launch check: no GPU boxes were running (no double-launch).
- Outputs: adapter → `models_20260919/med/sft_v3clean_adapter/`; ckpts →
  `spot_ckpt/med/sft_v3clean/`; logs → `spot_logs/med/sft_v3clean/`.

**Predicted outcome (grounded in the healthy v2 log):** `assert_nonempty_mask` passes
(~20% supervised); `loss` starts ~1.5–2.0 and settles ~0.5–1.0; ~17 s/it; post-train
guard passes; adapter ~58 MB. _[to be confirmed from the live log]_

Status: _awaiting spot capacity / training log — fill in._

---

## STEP 2 — EVAL (pending training completion)

Base vs new ckpt, each result uploaded immediately:
1. `decomposition_real` + its `score.py` — THE headline (out-of-synthetic-generator);
   node/edge-F1 overall; per-class directional (val n=68, thin on non-seq — say so).
2. `decomposition_v2` — compare to prior ckpt-275 win (node 0.73 / edge 0.79).
3. RealBio regression guard: routing / param_prefill / litqa2 / findings; specifically
   whether the 854 anchors bring param_prefill `must_not_fill` down from 61 toward base 34.

Status: _pending._

---

## Honesty / open items
- The v2-vs-v3 divergence on the box (same base, same template) was an undefined
  version-dependent masking fallback; the fix removes the dependence entirely rather
  than relying on it. If `decomposition_real` does NOT beat base, that is the real
  finding (synthetic win didn't transfer to real topologies) and will be reported plainly.
