# ScienceBuddy Source Dig + BioMate Necessity Audit

**Date:** 2026-10-20
**Status:** decision note (dig + audit complete; no code adopted yet)
**Scope:** Evaluate the open-source **ScienceBuddy** (arXiv:2609.17523, `github.com/Gen-Verse/ScienceBuddy`, MIT) for what BioMate can reuse or be inspired by, judged against a code-level audit of what BioMate **already has**. Two questions drove this: *(1) are the candidate adoptions actually necessary to BioMate?* and *(2) why not take the RL stack?*

**One-sentence conclusion:** ScienceBuddy is strong *independent validation* that BioMate is on the right architecture (harness-primary + verifiable rewards + gated self-improvement); **most candidate adoptions are redundant because BioMate already has production-grade equivalents**, and the dig surfaces only three genuine gaps — two small and concrete (a unified model export-and-verify gate; AST/schema validation of generated code), and one large that is really about **wiring BioMate's own dormant self-improvement machinery**, not importing anything.

---

## 1. What ScienceBuddy is

An interactive scientific agent (biomedicine: a reported 224 tools / 22 modules, Python/R/Bash execution) plus the part the repo actually ships: **recursive-in-recursive (double-recursive) self-improvement**.

- **Inner recursion (model fixed):** a frozen auxiliary "improver" LLM rewrites the agent's **harness** — a standalone Python program exposing `run(task, api)` — and candidates are selected on a held-out Val set.
- **Outer recursion (harness fixed):** the task model is GRPO-trained under the selected harness; the trained model becomes the base for the next round's harness search.

**Decisive caveat for reuse:** the GRPO optimization is **not in the repo**. The `skyrl/` submodule is unchecked-out (pinned to `NovaSky-AI/SkyRL`); everything in-repo is an *adapter* around that pinned trainer, and the training plane hard-requires 8×A100 + vLLM + Ray + FSDP + Docker-isolated execution. The value to lift is the **data plane and the discipline**, not the optimizer. License is **MIT** (reusable with attribution).

**Scale honesty:** results are on a frozen **Qwen3.5-4B**, a 715 Train / 90 Val / 90 Test biomedical-QA split, 3 cycles, verifier-assisted *simulated* feedback — modest scale, high engineering discipline.

### Code-level landmarks (for anyone reading the repo at `/Users/kky/sciencebuddy-dig`)

- `coevolve/selection.py::select_candidates` — generates all proposals **blind** (before any Val score), dedups by digest, preflights, scores parent + candidates **in parallel** on the same held-out Val, accepts a winner only on **zero runtime errors AND strictly-more-correct than parent** (ties keep parent).
- `coevolve/program.py::propose` + `validate_program` — the improver reads a bounded evidence catalog (requires evidence from **≥2 distinct tasks**), issues `read`/`propose`/`skip`, and proposes a full-file replacement with a *testable hypothesis* + 2–4 evidence IDs; `validate_program` uses **`ast`** to enforce the `run(task, api)` contract and reject the known `task.get("system")` footgun.
- `coevolve/command_schema.py` — JSON-Schema-validated (`Draft202012Validator`) `read`/`propose`/`skip` protocol with per-record field conditioning and a bounded repair loop.
- `coevolve/protocol.py` — **stdlib-only** crash-safe, content-addressed (sha256) file handoff: immutable `request/accepted/result.json`, atomic hardlink writes, a `producer_load_checked` gate, "never overwrite the base model."
- `harness/broker.py::run_episode` — async agent loop (`generate`/`execute`/`submit`/`end` ops), host-owned budgets (model calls, tool calls, tokens, seconds), tool-history clipping, **controller vs. execution container separation**.
- `data/verifier.py::grade_answer` — binary `<answer>…</answer>` extraction (exactly one), normalized match → `{score, passed, answer_format_valid}`.
- `coevolve/evidence.py` + `feedback.py` — hard isolation: "test results never enter proposals"; the reviewer sees **public content only**, replies are **enum-constrained**, PRM interpretations are "hypotheses, not verified causes."
- `training/trajectory.py::to_generator_output` — pure function, one row per model call, **terminal reward on the last token** broadcast across the episode (one rewarded attempt per multi-tool episode); zero-call failures dropped, not errored.
- `coevolve/worker.py` — **export-and-verify**: a successful training exit is explicitly *insufficient*; the producer must reload the exported checkpoint in a fresh process and prove non-degenerate generation before the stage is accepted.

---

## 2. BioMate audit — what already exists

Two code-level audits of `/Users/kky/biomate-review`. Legend: EXISTS / PARTIAL / ABSENT, LIVE / DORMANT.

### Harness / composer / execution plane

| Capability | Status | Evidence |
|---|---|---|
| Verifier-gated candidate selection / self-improvement | **EXISTS but DORMANT** (prototype only); production **manual** | Full Propose-Probe-Compose + blind selection + verifiers in `grounded-prototype/research/{harness_improver.py:140, h2_biomate.py, verifiers.py:230}` + vendored `research/vendor/harness2/core/selection.py:268` — **not imported by `backend/`/`frontend/`**. Production `pattern_router.py::decide:427` uses a benchmark-baseline gate but is flag-OFF (`BIOMATE_PATTERN_ROUTER_ENABLED` default false) and only *routes*. Production improvement = correction logging (`ai_assistant.py::record_workflow_correction:1541`, `learn_from_outcome:1074`). |
| AST / structural validation of generated code/workflows | **ABSENT in production** (regex) | `.nf` validation is regex heuristics — `ai/compute/sandbox/validator.py:81 validate_nextflow_source` (header: "a determined attacker can obfuscate past regexes"). `ast` only in the dormant `research/h2_biomate.py:93`. |
| Structured command / tool-call schema | **EXISTS / LIVE** | Native Anthropic + Gemini tool-use with JSON `input_schema` (`frontend/server/galaxy-assistant.ts` run_code `:102`, etc.); parsed as native `tool_use`. No local jsonschema Draft (provider-enforced). |
| Durable crash-safe job/run handoff | **EXISTS / LIVE** (content-addressed immutability PARTIAL) | `ai/runs/{run_state_store.py:29,159, completion_poller.py:86, orphan_finalizer.py, bootstrap.py:47}` + Redis store + `acquire_completion_lock` idempotency + AWS Batch path (`nextflow_executor.py`). Results persist as S3 outputs, not content-addressed immutable artifacts. |
| Agent rollout loop + budgets + sandbox | **EXISTS / LIVE** (token-budget accounting PARTIAL) | Composer loop `galaxy-assistant.ts` `MAX_TOOL_TURNS=5` (Claude) / `12` (Gemini), timeouts via `AbortSignal.timeout`; Docker sandbox `code-runner.ts::runViaDocker:244` `--network=none --memory=2g --cpus=2 --pids-limit`, stdout/stderr truncation; backend `.nf` head sandbox `ai/compute/sandbox/`. No running token/model-call budget accumulator. |

### Model-training / RL plane

| Capability | Status | Evidence |
|---|---|---|
| RL (GRPO/PPO) | **EXISTS / DORMANT** (launch-gated) | `evaluation/local_trial/train_grpo_decomp.py:187` wraps **TRL `GRPOTrainer`** (Qwen3.5-9B QLoRA), dry-run-proven, launch-gated on the SFT-decomp adapter in S3 (`run_grpo_decomp_9b.sh`). Generic TRL GRPO/DPO infra `ai/ml_training/trl_trainer.py:86,138`. Molecule RL `ai/drug_discovery/reinvent4_trainer.py` (REINVENT4). |
| Reward / verifier contract | **EXISTS / LIVE** (rich) | `evaluation/core/base_adapter.py:74 score→[0,1]`; routing binary, admet/boin composite, decomposition node_f1+edge_f1 (`datasets/decomposition_v2/score.py:8`); RL reward `decomp_reward.py:275` bounded [−0.5,1.0]; **execution grader** `execution_grader.py:153` (terminal + S3 content, pluggable contracts) + tier→reward ladder `graded_run_store.py:26`; inference-time `ai/verification_layer.py` (majority_vote/self_consistent/verified_sample). |
| SFT / DPO | **EXISTS / LIVE** (+ some dormant) | SFT `train_qlora_pilot.py` (TRL `SFTTrainer`, assistant-only loss, degeneracy guard `:172`); grounded + **execution-grounded** DPO `train_dpo_grounded.py` (chosen=ran, rejected=same-domain failed). Regulatory `scripts/finetune_regulatory_llm.py` + `regulatory_training_worker.py:17` — `prompt_rules` LIVE, `post_train_lora` DORMANT (witness-gated). |
| On-prem serving | **EXISTS / LIVE** | vLLM OpenAI endpoint `serve_sft_gold_standing.sh:81` (L40S, base + `sft_gold` LoRA); client `ai/local_inference.py:41` + `ai/sft_gold_inference.py`. |
| Trajectory→data + credit assignment | **PARTIAL** | Text-level rollout→SFT `latch_traj_to_sft.py:66`; execution reward store `graded_run_store.py:126` → `{run_id: reward}`. Reward is **terminal/per-run scalar**, no per-token/advantage tensors. |
| Token/logprob capture for training | **ABSENT** | No `prompt_ids/completion_ids/old_logprobs` capture; GRPO regenerates + scores on-policy inside TRL (no offline store needed for current design). |
| Model export / deploy verification gate | **PARTIAL** | Three *separate* guards — pre-save degeneracy `train_qlora_pilot.py:172`, adapter-effect reload sanity `eval_holdout.py:89`, **manual** served smoke `smoke_sft_gold.py:76`. No single automatic reload→prove→block gate (a broken-adapter deploy occurred 2026-10-07). |

---

## 3. Necessity verdict (per candidate adoption)

| ScienceBuddy item | BioMate equivalent | Necessary? |
|---|---|---|
| Structured command schema | LIVE provider-enforced tool-use | **No** — redundant. |
| Durable crash-safe handoff | LIVE, arguably stronger (cross-worker, Redis, Batch) | **No** — only content-addressed immutable manifests missing (minor). |
| Rollout loop + budgets + sandbox | LIVE (turn caps + timeouts + Docker isolation) | **No** — small gap: token/model-call budget accounting. |
| RL trainer (SkyRL) | Own TRL stack (GRPO/SFT/DPO) | **No** — don't import a second framework. |
| trajectory→data / logprob capture | On-policy inside TRL | **No** for current arch; only if BioMate goes disaggregated RL. |
| Strict verifier-gated selection | Built in prototype, DORMANT; prod manual | **Partly** — primitive exists; the need is **wiring**, with ScienceBuddy's stricter gate as a tweak. |
| AST/structural validation of generated code | ABSENT (regex only) | **Yes (medium)** — genuine gap; sandbox is the real security boundary, AST hardens the contract check. |
| Unified export-and-verify deploy gate | PARTIAL (3 separate guards) | **Yes (high)** — genuine gap; prevents a repeat of the 2026-10-07 incident. |

---

## 4. Why not the RL stack (answering Q2 directly)

Skip **SkyRL** because **BioMate already has its own RL stack** (home-grown over **TRL**: GRPO-9B dry-run + launch-gated, live SFT, live grounded/execution DPO, execution-grounded reward, vLLM serving) — not because RL or the local model is out of scope (it is central). Importing an 8×A100/Ray/FSDP/vLLM framework would duplicate what TRL already does at a saner single-GPU-spot scale.

The RL-side things actually worth taking are **not a trainer**:
1. **The unified export-and-verify gate** (gap, high value) — ScienceBuddy's `worker.py` reload→prove-non-degenerate→block, consolidating BioMate's three partial guards.
2. **The coupling idea** (strategy bet) — BioMate's GRPO trains *decomposition in isolation*; ScienceBuddy's contribution is training the model **under a verifier-selected, evolving harness**. This is the concrete expression of "tune the local LLM + a harness together," and it is the one architectural idea BioMate has not wired. It is a research bet, not a code lift.

Explicitly **de-prioritized:** `trajectory.py` + `RecordingPolicy` (the most "portable" code) — they solve a disaggregated/offline-RL problem BioMate's on-policy-TRL design does not currently have.

---

## 5. Recommended next actions (prioritized)

1. **Unified model export-and-verify gate** (small, high certainty). Consolidate `train_qlora_pilot.py:172` + `eval_holdout.py:89` + `smoke_sft_gold.py` into one automatic step that reloads the exported checkpoint in a fresh process, asserts non-degenerate generation on a fixed probe set, and **programmatically blocks** promotion. Models ScienceBuddy `coevolve/worker.py`.
2. **AST/schema contract validation** of generated `.nf`/code as a layer in front of the regex pre-check (`sandbox/validator.py`), modeled on `program.py::validate_program` — validate structure/contract, not just security (the Docker sandbox remains the security boundary).
3. **Wire the dormant self-improvement loop** (`grounded-prototype/research/` + `pattern_router`) toward production, adopting ScienceBuddy's stricter selection gate (zero-error + strictly-better + parallel held-out Val) and evidence discipline (≥2 distinct tasks; test results never enter proposals). Large lift; the primitive already exists.
4. **Token/model-call budget accounting** in the chat agent loop (minor).

Non-actions: do not import SkyRL; do not build a logprob/trajectory store; do not re-implement the command schema, durable handoff, or rollout loop (already present).

---

## 6. References

- Paper: *ScienceBuddy: Recursive-in-Recursive Self-Improvement for Interactive Scientific Agents*, arXiv:2609.17523.
- Repo: `github.com/Gen-Verse/ScienceBuddy` (MIT), cloned at `/Users/kky/sciencebuddy-dig`; `skyrl/` submodule = pinned `NovaSky-AI/SkyRL`, unchecked-out.
- Related internal: `docs/20261019_HARNESS2_DIG_AND_BIOMATE_FIT.md` (the Harness2 dig — same RSI lineage, verifier-free variant), `docs/20261019_DECOMP_ORCHESTRATION_AND_FEEDBACK_DESIGN.md`, `docs/20260912_onprem_llm/20261006_DECOMP_STAGE2_GRPO_DESIGN.md`.
