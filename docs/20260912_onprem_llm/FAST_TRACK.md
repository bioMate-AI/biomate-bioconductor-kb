# BioMate local LLM: maximum 32B, ASAP

**Scope correction:** The implementation and training target is the main BioMate assistant, not the IND model. T22/T23 and IND datasets/adapters are excluded. See [BioMate trial scope](BIOMATE_SCOPE.md). This overrides earlier conditional IND references.

**Resource strategy update:** [Using correction logs, commits, knowledge, teachers and controlled harness improvement](RESOURCE_STRATEGY.md), with [measured local knowledge inventory](RESOURCE_AUDIT.json). This adds the verified experience pipeline and data-quality fixes to the urgent deployment plan.

**User constraints confirmed 12 September 2026:** maximum 32B local LLM; earliest practical delivery. This document supersedes the initial broad model search and first-release schedule. The task catalog, data contract and scientific evaluation requirements remain applicable.

## Decision

Start with **one shared local model**, existing BioMate tools/retrieval/validators and task-specific prompts. Get a limited deployment of the official post-trained checkpoint working before making BioMate-specific fine-tuning a prerequisite. In parallel, prepare verified data for the first LoRA/SFT improvement. No foundation-model pretraining, DPO, RL or multiple specialist deployments on the initial critical path.

**Checkpoint clarification (applies to the earlier 3.5 candidate):** `Qwen/Qwen3.5-27B` is already the official **post-trained assistant checkpoint**, despite lacking an `-Instruct` suffix. Use it as the starting checkpoint for BioMate SFT, not a raw pretrained base. Its thinking and instruct/non-thinking modes are configurations of the same checkpoint, not two separately trained models. The official card explicitly identifies the checkpoint as post-trained and documents `chat_template_kwargs: {"enable_thinking": false}` for non-thinking operation. No separate official “better Instruct” checkpoint was verified in this review. Prefer the official checkpoint over community derivatives until the latter show reproducible improvements on BioMate's held-out tasks. [Official checkpoint and mode documentation](https://huggingface.co/Qwen/Qwen3.5-27B).

For the urgent deployment, use non-thinking mode first for routing, extraction, JSON and short summaries; evaluate thinking mode for difficult planning, code and scientific synthesis with explicit latency/output budgets. Both modes still need tool/validator checks. Fine-tune the post-trained checkpoint on reviewed BioMate traces while testing retention of instruction following and tool use. A raw pretrained base would require additional general assistant post-training as well as domain adaptation, adding work that does not address the immediate integration gaps.

1. **First candidate: Qwen3.8-27B, official post-trained checkpoint.** This supersedes the earlier 3.5 recommendation following verification of the newer release. It retains the Qwen3.5 architectural foundation and supports local serving, vision and configurable thinking. Published improvements are vendor evidence; BioMate performance remains unmeasured. [Official model card](https://huggingface.co/Qwen/Qwen3.8-27B).
2. **Comparison/fallback candidate: Qwen3.5-27B.** Use the identical BioMate development cases and runtime checks. If 3.8 has a deployment blocker after four engineering hours with hardware/artifacts ready, proceed with the passing 3.5 checkpoint. Neither model should be deployed until its tool loop and local-only boundary pass. Qwen3-30B-A3B is no longer in the initial two-candidate comparison.
3. **Exclude Qwen3-32B under a strict cap:** the official count is 32.8B. Also exclude MoE models above 32B total even if activated parameters are smaller. Quantization changes storage, not parameter count. [Official model card](https://huggingface.co/Qwen/Qwen3-32B).

Check total parameters from the actual shipped architecture/artifacts, including optional vision components. Keep only one candidate resident for the first pilot. If hardware cannot support either at acceptable latency, evaluate a smaller approved model; do not exceed the ceiling or silently fall back to a cloud API.

## Delivery targets

These are planning targets starting when a usable local inference host, access and reviewers are available. They do not claim training has started or guarantee quality by a calendar deadline.

| Deadline | Deliverable | Required evidence |
|---|---|---|
| First 24 hours | Local gateway, selected model and core chat/tool path | Valid JSON, streaming, actual tool request/observation round trip, source/model identity and no external inference fallback. |
| 48–72 hours | Limited local pilot for passing capabilities | Locked smoke results; actual run/output evidence; local outage/fallback tests; no external inference/embedding traffic; prior-local-artifact rollback. |
| Days 2–5 | First accepted training corpus and independent dev/test data | Rights/lineage, reviewed targets, no cross-split source/duplicate leakage and task coverage report. |
| Days 5–10 | First SFT adapter candidate | Measured training throughput, adapter save/reload proof and improvement against the unchanged local base on independent tasks. If training/runtime/data are not ready, retain the passing base; do not report an adapter as delivered. |

Full feature parity is a separate milestone, dated only after the baseline identifies the remaining gaps. Fully air-gapped workflow/data infrastructure may take longer than localizing the LLM; establish that boundary immediately.

## What to make work first

Initial scope: intent/domain routing, literal data and schema-grounded parameters, workflow/input selection, the main scientific assistant with real tool calls, grounded findings, and essential session context. Run only workflows whose tools, storage and required evidence are available locally or otherwise explicitly permitted by the customer's data-access policy.

Use one gateway for both text helpers and tool-capable chat; migrate direct Flash/Claude/OpenAI calls on every enabled path. Disable external fallbacks and cloud-key gates. Preserve tool-call IDs, observations, schemas and streaming. Replace cloud-environment claims in prompts with actual deployment capabilities. The audit found the existing Ollama path lacks tool execution, so pointing that path at a new model is not sufficient.

Later capabilities: multi-paper/vision workflows, autonomous repair, additional domains and regulatory documents. They may enter the pilot only after their own evidence/validator tests pass. If IND is customer-critical, move T22/T23 into the first tranche and allocate a regulatory reviewer; do not compress its validation to fit the deadline. Clearly label any unavailable feature.

## Small, concrete data and evaluation batches

Prepare a **200-case operational smoke suite**: 50 routing/clarification; 40 parameter/input mapping; 35 real tool/workflow trajectories; 25 evidence/findings; 20 memory/follow-up; 15 malformed-output/local-outage; 15 adversarial/permission/egress cases. Cases can check multiple properties. Keep it separate from training and reserve it for pilot acceptance, using development fixtures for iteration. It does not establish statistical equivalence to the API system or validate every scientific domain.

For the first training experiment, target **2,000 accepted items**:

| Group | Items |
|---|---:|
| Intent, extraction and parameter mapping | 700 |
| Workflow/tool selection and prerequisite handling | 400 |
| Complete tool-use/scientific-code trajectories | 400 |
| Grounded evidence and findings | 250 |
| Memory, corrections and clarification | 150 |
| Observed failures and recovery | 100 |

Add **300 independent development items and 500 locked evaluation items**, grouped by source/project/study before generating augmentations. These are additional to training; complete trajectories contain multiple turns. Include negative cases, corrections, tool errors and long contexts across the mixture. Actual rendered inputs, schemas, evidence, tool observations and verified outputs are required. Do not use the contaminated regulatory test splits as independent evidence.

Start SFT with one configuration and one saved/reloaded adapter; expand the hyperparameter search only if evidence requires it. Inspect label masking and a short training batch before the full run. Adapt the loader correctly for the selected architecture and prove actual quantization if using QLoRA. Select checkpoints on dev; evaluate the locked set only after selection. Keep only an adapter that improves task outcomes without violating release gates. The initial data counts do not guarantee that the model will pass.

## Hardware and operational defaults

The 32B limit is not a memory specification. The 27B language weights alone are approximately 54 GB at 16-bit or 13.5 GB raw at 4-bit; vision, quantization metadata, cache and runtime overhead add memory. Determine precision from actual GPU/VRAM and validate the quantized artifact. Do not buy hardware from these weight-only figures.

Start load testing with one active request and a bounded context budget, increasing concurrency after measurement. Preserve enough context for real BioMate prompts and tool observations; do not truncate essential schemas or history to claim low latency. Do not copy the model card's large-context multi-GPU example as a minimum hardware requirement.

For structured helpers, use the selected model’s supported non-thinking setting rather than the old `/no_think` prefix. For Qwen3.8, explicitly test reasoning-effort and multi-turn reasoning-history serialization against the pinned serving recipe; keep internal reasoning separate from user-visible output and tool observations. Test reasoning budgets separately for difficult code/tool tasks. Record actual model/runtime/precision and p95 latency. No latency guarantee is credible until the host is known.

**Remaining operational input:** GPU model, number of GPUs, VRAM per GPU and the host/endpoint to use. Also confirm whether data APIs are allowed or the whole deployment is air-gapped. Documentation and dataset preparation can proceed without those answers; a real serving/training run cannot be honestly scheduled without the resources.

## Checkpoint choice before training

Qwen3.8-27B is already post-trained, so begin with these assistant weights, then apply BioMate SFT/LoRA. Do not wait for a separately named Instruct edition. Thinking and non-thinking are modes, not a choice between raw base and assistant weights. Compare the two candidates on development data before choosing the SFT starting point; keep the locked pilot/test suites for acceptance. An existing Qwen3.5 adapter must not be reused on 3.8 merely because tensor shapes match; train and validate against the chosen base revision.
