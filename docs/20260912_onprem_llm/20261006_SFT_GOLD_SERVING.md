# On-prem 9B SFT-from-gold: serving + DEV LLM-mixture wiring

**Date:** 2026-10-06
**Author:** Yaoyun Zhang (automated run)
**Scope:** DEV ONLY. Reversible. Flag default **OFF**.
**Artifact:** LoRA adapter `s3://biomate-models-399683337364/biomate-core-local-trial/20260912/serving/sft_gold_9b_20261006/`
(58 MB, r16/α32, no CPT merge), base `Qwen/Qwen3.5-9B` @ `c202236235762e1c871ad0ccb60c8ee5ba337b9a`.
Eval that certified it: `docs/20260912_onprem_llm/20261006_SFT_FROM_COLLECTED_GOLD.md`.

---

## TL;DR

- **Code wiring is DONE, committed, flag-gated OFF** — ships inert with the next sync and is a one-env-var
  flip to enable, one flip to disable. tsc clean, unit tests pass, py3.9 module-load verified.
- **The GPU endpoint was NOT launched in this session, and the dev flag was NOT turned ON**, on purpose —
  two steps are gated by the user's own standing rules / live cost (see **What is blocked / left for you**).
  A reviewed, ready-to-run standing-endpoint launcher + smoke test are committed.
- **Honest architecture finding:** BioMate has **no per-task LLM router**. The clean, minimal, correct
  integration is a per-task tag at the single documented backend chokepoint (`/internal/llm/generate`).
  **Findings synthesis routes cleanly. Task decomposition does NOT** — explained below; I did not hack it.

---

## 1. How model selection actually works (ground truth)

There is no "mixture" to plug into. Every component (`~30` call sites) constructs its own
`LLMClient(config)` and calls `.generate()`, which routes through ONE global fallback chain defined in
`backend/config/llm_providers.yml` (gemini-pro → gemini-flash → claude → gpt-4o → ollama). The only
task-agnostic override is the global `BIOMATE_LOCAL_ONLY=1` switch, which sends **everything** to a single
local endpoint (`backend/lib/galaxy/ai/local_inference.py`, `frontend/server/local-llm.ts`). There is no
per-task selection anywhere.

The one real chokepoint is **`backend/lib/galaxy/webapps/galaxy/api/llm_internal.py`**
(`POST /internal/llm/generate`) — documented as "the single chokepoint" that re-routes the frontend's LLM
calls through the canonical chain. The Node `llmGenerate()` (`frontend/server/llm-client.ts`) proxies to it.
That is where per-task routing belongs, and that is where I added it.

**Per-task pluggability verdict:**
| Task | Live call site | Cleanly pluggable? |
|---|---|---|
| **Findings synthesis** | `routes.ts` `/analyze` → `llmGenerate({…, jsonMode})` → `/internal/llm/generate` | **YES** — single call, format matches the model's `findings` training. Wired. |
| **Task decomposition** | `galaxy-assistant.ts` `analyzeIntent()` — a bespoke **Gemini→llmGenerate→Anthropic** 3-provider classifier cascade | **NO** — not a single swap, and its intent-classification schema ≠ the model's harness `task_decomposition` training format. NOT force-wired (would risk regressing classification). Hook is ready; see §3. |
| (dead) `task_decomposer.py`, `workflow_generator.py` et al. | `self.llm_client.generate_structured(...)` | N/A — `generate_structured` has **no definition anywhere** in the tree (4 callers, all wrapped in `try/except → fallback`), so these paths are effectively dead. Not wired. |

---

## 2. What I changed (all additive, default OFF)

1. **`backend/lib/galaxy/ai/sft_gold_inference.py`** (new) — task-scoped client for the sft_gold vLLM
   endpoint. `enabled()` reads the master flag; `enabled_for(task)` also checks the allowlist; `agenerate()`
   calls the OpenAI `/chat/completions` with `temperature 0` + `enable_thinking:false` (parity with the eval
   shim). Origin-pinned (URL origin must equal `BIOMATE_SFT_GOLD_ORIGIN`), like `local_inference.py`. Raises
   on any error so the caller falls back. py3.9-safe.
2. **`backend/lib/galaxy/webapps/galaxy/api/llm_internal.py`** — reads optional `task` from the body; when
   `sft_gold_inference.enabled_for(task)`, tries the adapter FIRST and returns `model_used:"sft_gold"`; on
   **any** error (or flag OFF / task not allowlisted) falls through to the existing chain unchanged.
3. **`frontend/server/llm-client.ts`** — `LlmGenerateOptions.task?: string`, forwarded as `task` in the
   request body only when present.
4. **`frontend/server/routes.ts`** — the findings `/analyze` call now passes `task: 'findings'`.
5. **`frontend/server/__tests__/llm-client.test.ts`** — asserts `task` is forwarded when provided, omitted
   otherwise.

No production workflow files touched. No `llm_providers.yml` change (routing policy lives in the flag, not the chain).

---

## 3. The flag + exact wiring

**Master flag (default OFF):** `BIOMATE_SFT_GOLD_ENABLED` — must be `1` to route anything.

Full env set (all on the **dev Galaxy container**; findings runs server-side there):
```
BIOMATE_SFT_GOLD_ENABLED=1
BIOMATE_SFT_GOLD_URL=http://<gpu-private-ip>:8000/v1
BIOMATE_SFT_GOLD_ORIGIN=http://<gpu-private-ip>:8000     # must equal URL origin (scheme://host:port)
BIOMATE_SFT_GOLD_MODEL=sft_gold                          # default; the vLLM --lora-modules name
BIOMATE_SFT_GOLD_TASKS=findings,decomposition            # allowlist (default)
# BIOMATE_SFT_GOLD_KEY=...                                # optional bearer
# BIOMATE_SFT_GOLD_TIMEOUT_MS=120000                      # optional
```

- **Findings** is live end-to-end once the flag is on: dev Node tags the `/analyze` call `task:'findings'`
  → backend `/internal/llm/generate` → sft_gold.
- **Decomposition** is in the allowlist so the backend hook will route any call tagged `task:'decomposition'`,
  but **no live call site is tagged** (the `analyzeIntent` cascade is not a clean swap and its schema differs
  from training — see §1). To actually route decomposition later, the minimal correct step is: add a single
  non-streaming decomposition call that uses the harness `task_decomposition` prompt format and tag it
  `task:'decomposition'` — do **not** redirect the `analyzeIntent` classifier, which would feed sft_gold an
  off-distribution schema.

### How to turn it OFF (instant, reversible)
Set `BIOMATE_SFT_GOLD_ENABLED=0` (or unset it) in `/opt/biomate/.env` on dev and run
`BIOMATE_RESYNC_GALAXY_ENV=1 bash scripts/sync_to_dev.sh`. Everything immediately falls back to the cloud
chain. Nothing else needs reverting; the code is inert when the flag is off. (Stopping the GPU box alone also
makes every sft_gold call fail → clean fallback, but leaves the flag on; prefer flipping the flag.)

---

## 4. The endpoint (serving plan — reviewed, ready to run)

**Launcher:** `evaluation/local_trial/serve_sft_gold_standing.sh` (committed). **Smoke test:**
`evaluation/local_trial/smoke_sft_gold.py`.

- **Instance:** `g6e.xlarge` = **1× L40S 48 GB**, on-demand (NOT spot — serving must persist), us-west-2,
  subnet `subnet-0254e4c3634b41bfc`, VPC `vpc-00059887828237f1f` (**same VPC as the dev backend**
  `i-06696b0d91f4346e0` / private `172.31.37.246`), IAM profile `biomate-core-trial-20260912` (S3 read).
- **Serve command** (same base + R16-LoRA topology as `build_eval_vllm_v8.sh`):
  `vllm serve <base> --served-model-name Qwen/Qwen3.5-9B --enable-lora --lora-modules sft_gold=<dir>
  --max-lora-rank 16 --dtype bfloat16 --max-model-len 4096 --gpu-memory-utilization 0.9 --port 8000`,
  under a `systemd` unit (`Restart=always`). Base pulled from HF, adapter from the serving S3 prefix.
- **Endpoint URL:** `http://<gpu-private-ip>:8000/v1` (written to
  `…/serving/standing_logs/endpoint.txt` and echoed as `ENDPOINT …` in the boot log once healthy). Clients
  call `model="sft_gold"` (base is `model="Qwen/Qwen3.5-9B"`).
- **Security group:** dedicated `biomate-sft-gold-serve`, inbound tcp/8000 **only from the dev backend SG
  `sg-0b2188a4d48d989b8`** (source-SG, intra-VPC/private). **No public ingress.**

### ⚠️ Sizing deviation from the task brief (deliberate, evidence-based)
The brief assumed `g6.2xlarge` (L4 24 GB). The repo's own `serve_eval_routing.sh` documents that the base
resolves to a **multimodal `Qwen3_5ForConditionalGeneration`**, heavier than a text-only 9B, and needed a
**48 GB L40S (g6e)**; 24 GB only worked for short routing prompts with `--enforce-eager` + util 0.95 + tiny
KV. For a standing findings endpoint (longer context) the safe choice is the 48 GB L40S. Launcher defaults to
`g6e.xlarge`; override with `INSTANCE_TYPE=` if you want to retry 24 GB.

### ⚠️ Parity caveat (must be confirmed by the smoke test)
The **certified** gold numbers came from the transformers text-backbone shim (`harness_shim.py`, which uses
`load_text_model` to extract the Qwen3.5 text backbone and drop vision/MTP weights). vLLM serves the **full
multimodal** model and applies the same LoRA to the attn+MLP projections. For a greedy, no-think, text-only
LoRA these should be close, but they are **not provably identical**. `smoke_sft_gold.py` runs the
decomposition + findings prompts against base and sft_gold so you can eyeball that the served adapter behaves
like the evaluated one (terse subtask list; bounded findings narration) before trusting it on dev.

---

## 5. Standing cost + auto-stop

- **~\$1.86/h** on-demand (g6e.xlarge, us-west-2). ~\$45/day if left running 24/7 — hence the safeguards.
- **Idle auto-stop:** a `systemd` watchdog polls vLLM `/metrics` (`vllm:e2e_request_latency_seconds_count`);
  if it hasn't advanced for `IDLE_MINUTES` (default **60**) it runs `shutdown -h now`.
- **Hard backstop:** stop unconditionally after `MAX_HOURS` (default **12**).
- The instance launches with `--instance-initiated-shutdown-behavior stop`, so `shutdown -h now` **STOPS
  (not terminates)** the box with **no IAM API permission required**; EBS persists, restart is instant.
- Manual: `aws ec2 stop-instances --region us-west-2 --instance-ids <IID>` (stop) /
  `terminate-instances` (delete). The launcher prints both.

---

## 6. Why param_prefill and workflow routing are NOT routed here

From the certified eval (`20261006_SFT_FROM_COLLECTED_GOLD.md`):
- **param_prefill — NOT routed.** `must_not_fill` violations regressed **34 → 49** (+15; precision
  0.820→0.761); the adapter over-fills. F1 ≈ base but the over-fill is a real regression, only partially
  absorbed by the schema guardrail. Keep param extraction on the rule+LLM guardrail path.
- **workflow routing — NOT routed.** Routing is carried by the **dense retriever** (model-invariant); the
  adapter was −2.5pt (within CI, i.e. no gain). No reason to add a hop.
These two are excluded by simply keeping them out of `BIOMATE_SFT_GOLD_TASKS`. The allowlist is the guard.

The tasks it **wins** and that we route (or stand ready to route): **findings** (+15pt ROUGE-1, indicative),
**task_decomposition** (+23pt structure, n=30 wide CI), knowledge/litqa (+6.5pt via coverage). Findings is
wired; decomposition is hook-ready per §3.

---

## 7. Verification done this session (local, real)

- **Backend policy** (`sft_gold_inference`, loaded in isolation on py3.9): default **OFF**; with the flag on,
  `enabled_for` returns **True** for `findings`/`decomposition` and **False** for `param_prefill`, `routing`,
  and `None`; `_config()` rejects an unset URL and an origin mismatch, accepts a matching origin. ✔
- **py3.9 module-load / compile** of `sft_gold_inference.py` and `llm_internal.py`. ✔ (the heavy
  `galaxy.ai/__init__` import fails locally on an unrelated scipy issue — not introduced here.)
- **tsc** `--noEmit` clean (0 errors). ✔
- **vitest** `server/__tests__/llm-client.test.ts` — 7/7 pass incl. the new `task`-forwarding case; `task`
  omitted when not provided ⇒ **OFF path is byte-identical to today**. ✔

The flag-ON path (sft_gold actually answering) cannot be verified without the live endpoint + the dev env
var, both of which are the blocked steps below.

---

## 8. What is blocked / left for you to decide

I stopped short of two live actions rather than work around the rules:

1. **Launch the GPU endpoint.** Not permission-blocked (root AWS available), but a *standing, billable* box
   cannot be verified end-to-end this session because step 2 below is blocked — so standing it up would be
   cost with no completable loop (the "no speculative expensive deploy" rule). **Decision for you:** run
   `bash evaluation/local_trial/serve_sft_gold_standing.sh`, grab the `ENDPOINT` URL, then
   `python3 smoke_sft_gold.py http://<ip>:8000/v1` from the dev backend (the only host the SG admits).
2. **Turn the dev flag ON.** The dev Galaxy env comes from `/opt/biomate/.env` **on the dev box** (applied via
   `BIOMATE_RESYNC_GALAXY_ENV=1 bash scripts/sync_to_dev.sh`). Editing that file is an out-of-band dev change,
   which your standing rule ("never modify dev out-of-band; SSM read-only") prohibits me from doing. **Decision
   for you:** add the §3 env block (with the real endpoint IP) to `/opt/biomate/.env` and run the resync.
3. **Deploy the code to dev.** `scripts/sync_to_dev.sh` ships the **entire working tree**, which in this
   worktree currently carries many unrelated modified/deleted files (see `git status`). Syncing from here
   would push that unrelated WIP to dev. I committed my change on this branch instead; **run the sync from a
   clean tree** (or cherry-pick these commits onto the deploy branch) to land it. The flag is OFF, so landing
   the code changes nothing until step 2.
4. **Production rollout** — explicitly out of scope (DEV only). Decide later, after dev findings quality is
   confirmed against the parity caveat in §4.
