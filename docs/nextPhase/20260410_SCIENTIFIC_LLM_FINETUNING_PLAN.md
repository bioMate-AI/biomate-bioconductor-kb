# Scientific LLM Fine-Tuning Plan for BioMate Workflow Generation

*Date: 2026-04-10 | Status: Proposal*

---

## Objective

Train a compact scientific LLM (~7–8B parameters) to replace the Claude-based router and parameter-fill step in BioMate. The model learns from BioMate's own workflows and execution traces, using supervised fine-tuning (SFT) followed by reinforcement learning (RL) with real Batch execution feedback.

Target metrics:
- Routing accuracy ≥ 95% (current Claude baseline: 93.3% on 120-query benchmark)
- Required parameter fill accuracy ≥ 90%
- End-to-end Batch execution success rate ≥ 85%
- Inference cost: ≤ 5% of current Claude API cost

---

## 1. Base Model Selection

### Recommendation: Qwen2.5-7B-Instruct

| Model | Params | Domain pretraining | Tool use | Structured output | Verdict |
|-------|--------|--------------------|----------|-------------------|---------|
| **Qwen2.5-7B-Instruct** | 7B | General + code | Excellent | Excellent | **First choice** |
| OpenBioLLM-8B (Saama, 2024) | 8B | Llama-3 + 3.4B biomedical tokens | Good | Good | Second choice |
| BioMistral-7B (Labrak et al., 2024, arXiv:2402.10373) | 7B | Mistral + PubMed Central | Moderate | Moderate | Third choice |
| BioMedLM (Stanford, 2023) | 2.7B | PubMed only | Weak | Weak | Too small |

**Rationale for Qwen2.5-7B:** The primary task is structured JSON parameter extraction and workflow routing — not clinical reasoning. Qwen2.5's coding and structured output capability is the bottleneck, not biomedical domain knowledge. Domain knowledge is injected in Phase 0 (continued pretraining). GRPO training frameworks (verl, OpenRLHF) are well-tested on Qwen2.5.

**If domain pretraining is prioritized:** Use OpenBioLLM-8B as base, which already incorporates biomedical fine-tuning on top of Llama-3.

---

## 2. Phase 0: Domain Adaptation via Continued Pretraining

*Optional but recommended. Duration: 1–2 days on 4×A100.*

Inject biomedical and bioinformatics vocabulary before task-specific training.

**Data sources:**
- PubMed abstracts 2020–2025 (~2M documents, filtered to genomics, drug discovery, proteomics, structural biology)
- nf-core documentation (all pipeline READMEs + module docs from nf-co.re)
- BioMate workflow schemas: all 63 `nextflow_schema.json` files + `main.nf` files
- Nextflow language documentation (DSL2 syntax, process/workflow blocks)

**Objective:** Standard causal language modeling (CLM) on above corpus.

**Goal:** Ensure the model recognizes terminology like `fasterq-dump`, `GATK HaplotypeCaller`, `GROMACS NPT equilibration`, `CryoSPARC`, `SMILES`, without hallucinating parameter names.

---

## 3. Phase 1: Supervised Fine-Tuning (SFT)

*Duration: 3–5 days on 4×A100 80GB.*

### 3.1 Training Data Generation

BioMate already has all required source assets:

| Asset | Location | Use |
|-------|----------|-----|
| 120-query routing benchmark | `frontend/e2e/` | Ground-truth routing labels |
| 63 Nextflow workflow schemas | `subworkflows/**/nextflow_schema.json` | Parameter constraints |
| Workflow DB entries | Galaxy SQLite | Descriptions, keywords, prerequisites |
| Execution logs | `/tmp/galaxy_backend_final.log`, `execution_runs` table | Real trajectories |
| Nextflow `main.nf` files | `subworkflows/**` | Pipeline structure |

**Synthetic generation pipeline:**

For each of 63 workflows, use Claude Sonnet to generate 80–120 diverse queries covering:
- Varied user types (biologist, clinician, computational chemist, bioinformatician)
- Varied specificity (vague: "run variant calling" → precise: "GATK germline pipeline on SRR1518169 hg38 max 1M reads")
- Varied data formats (SRA accession, local FASTQ path, uploaded MRC file, SMILES string)

For each query, generate a complete multi-turn trajectory in the following format:

```
SYSTEM:
You are BioMate, a biomedical workflow assistant. You select the correct
Nextflow workflow, fill parameters, and submit jobs to AWS Batch.
Available workflows: [JSON list from DB]

USER:
"I have WGS sequencing data for sample SRR1518169. Run germline variant
calling with max 1 million spots."

ASSISTANT:
<think>
User provides an SRA accession → needs fasterq-dump + GATK germline pipeline.
Workflow: wgs_germline_gatk. Required params: input (SRR accession),
genome (default GRCh38), max_spots (user specified: 1000000).
</think>
[TOOL: select_workflow]
{"workflow": "wgs_germline_gatk", "workflow_id": 12345, "confidence": 0.97,
 "rationale": "SRA accession + germline variant calling → GATK pipeline"}

[TOOL: fill_parameters]
{"input": "SRR1518169", "genome": "GRCh38", "max_spots": 1000000,
 "outdir": "s3://biomate-nextflow-work/runs/"}

[TOOL: validate_prereqs]
{"all_satisfied": true, "missing": []}

[TOOL: submit_execution]
{"queue": "biomate-hpc-queue", "profile": "aws_batch"}
```

**Rejection sampling filter** (applied by a separate validation script):
- Routing must match ground-truth workflow (DB lookup by name)
- All required parameters must pass `jsonschema` validation against the workflow schema
- No hallucinated parameter keys (strict schema allowedProperties check)
- Tool call sequence must follow the correct order (select → fill → validate → submit)

**Negative example augmentation (15% of dataset):**
Generate examples where the model makes a routing error, detects it via re-reading the query, and self-corrects. This teaches recovery behavior (following the ReST+ReAct finding: arXiv:2312.10003 — self-correcting agents generalize better than always-correct ones).

**Target dataset size:** ~6,000–8,000 examples (80 queries × 63 workflows × ~80% pass rate after filtering).

**Additional real examples:**
- Extract all successful execution traces from the `execution_runs` DB table
- Pair with the user message that triggered them (from `conversation_states` table)
- These are gold-standard examples — weight 3× in training loss

### 3.2 Training Configuration

```yaml
model: Qwen/Qwen2.5-7B-Instruct
method: full fine-tuning (or LoRA rank=64 if VRAM constrained)
batch_size: 32
learning_rate: 2e-5
warmup_steps: 100
epochs: 3
loss: cross-entropy on assistant turns only (user/system turns masked)
sequence_length: 4096
hardware: 4× A100 80GB (AWS p4d.24xlarge or equivalent)
framework: LLaMA-Factory or transformers + deepspeed ZeRO-2
```

---

## 4. Phase 2: Offline GRPO Fine-Tuning

*Duration: 1–2 weeks on 4×A100. No Batch jobs needed.*

### 4.1 Algorithm: GRPO

Group Relative Policy Optimization (GRPO, Shao et al., 2024) is preferred over PPO because:
- No critic network needed → 40% less VRAM
- Computes advantage by comparing within a group of K rollouts per query → stable for structured output tasks
- Now the dominant algorithm for agentic RL (WebAgent-R1, Workflow-R1, Biomni-R0)

Group size K=8: generate 8 rollouts per query, compute relative advantages, update policy.

### 4.2 Reward Design (Offline Phase)

Three rewards are computable without running real Batch jobs:

| Reward | Signal | Computation |
|--------|--------|-------------|
| **R_routing** | Correct workflow selected | DB lookup: `workflow_name == ground_truth` → {0, 1} |
| **R_param** | Required params filled + schema valid | jsonschema validation: fraction of required params passing → [0.0, 1.0] |
| **R_format** | Output uses correct tool-call structure | Regex: all four tool calls present in correct order → {0, 1} |

Composite: `R_offline = 0.35·R_routing + 0.45·R_param + 0.20·R_format`

R_param is weighted highest because parameter fill is the primary failure mode in the current system (see `docs/nextPhase/20260409_BATCH_QUEUE_AND_EXECUTION_FIX.md` — `_is_path_param` bugs, genome identifier misclassification).

### 4.3 Process Rewards (Step-Level)

Rather than a single end-of-trajectory reward, apply rewards at each tool call boundary. This is the key insight from AgentPRM (arXiv:2511.08325) and ReST-MCTS* (NeurIPS 2024, arXiv:2406.03816):

```
Token position: [... select_workflow ...] → apply R_routing
Token position: [... fill_parameters ...] → apply R_param
Token position: [... validate_prereqs ...] → apply 1.0 if no schema errors
Token position: [... submit_execution ...] → apply R_format
```

Implementation: track token position during rollout generation; insert reward signals at tool-call closing brackets using the verl reward_fn hook.

### 4.4 Training Configuration

```yaml
algorithm: GRPO
group_size: 8  # K rollouts per query
kl_coeff: 0.01  # KL penalty against SFT reference model
clip_ratio: 0.2  # PPO-style clipping applied to GRPO gradient
max_grad_norm: 1.0
learning_rate: 5e-6  # lower than SFT
reward_normalize: true  # normalize rewards within each group
reference_model: biomate-sft  # frozen SFT checkpoint as KL anchor
framework: verl (Volcano Engine RL) or OpenRLHF
```

---

## 5. Phase 3: Online GRPO with Batch Execution Feedback

*Duration: 2–4 weeks. Requires real AWS Batch submissions.*

This phase adds the fourth reward: **R_exec** — did the Batch job actually succeed?

### 5.1 Reward Design (Online Phase)

| Reward | Signal | Value | Source |
|--------|--------|-------|--------|
| R_routing | Correct workflow | 0 / 1 | DB |
| R_param | Schema valid | 0.0–1.0 | jsonschema |
| R_exec | Batch job exit 0 | 0 / 1 | CloudWatch / Batch API |
| R_output | Output answers user query | 0.0–1.0 | LLM judge (Haiku) |
| R_format | Correct tool-call structure | 0 / 1 | Regex |

Composite: `R_online = 0.20·R_routing + 0.30·R_param + 0.30·R_exec + 0.10·R_output + 0.10·R_format`

**R_output (LLM judge):** After job completes, pass the user's original query + the output file list to Haiku with the prompt: *"Does this set of output files constitute a complete and correct answer to the user's question? Score 0.0–1.0."* This catches cases where the job exits 0 but produces wrong outputs (wrong genome build, truncated reads, etc.).

### 5.2 Async Reward Collection

R_exec and R_output are delayed by minutes-to-hours (Batch cold start + execution time). This requires an async reward buffer:

```
Submit batch of 64 rollouts to Batch
  ↓
Store (rollout_id, trajectory, partial_reward) in reward_buffer table
  ↓
Batch completion webhook → compute R_exec + R_output → update reward_buffer
  ↓
When buffer has ≥ 32 complete entries → trigger GRPO update step
```

The `execution_runs` table already stores `(run_id, workflow, params, batch_job_id, status)` — extend it with `rollout_id` and `rl_reward` columns to serve as the reward log. This is the same design as Aviary (arXiv:2412.21154) applied to Nextflow execution.

**Off-policy correction:** Since rewards arrive after policy has been updated, apply importance weighting using the log-probability ratio between current policy and the policy that generated the rollout.

### 5.3 Safety Constraints

Online RL against a real Batch environment incurs real AWS costs. Safeguards:

- **Max job cap:** Limit to 20 Batch job submissions per GRPO update step during training
- **Workflow whitelist for RL training:** Only submit jobs from 5 fast workflows (ADMET screening, SRA download with max_spots=1000, QC profiling, small molecule docking, sequence alignment) to minimize cost and wall-clock time
- **Reward clipping:** Clip R_exec rewards to avoid policy collapse on a single high-reward workflow type
- **Rollback trigger:** If execution success rate drops below 60% over a 50-step window, rollback to previous checkpoint

---

## 6. Data Flywheel

Once deployed, the fine-tuned model generates its own improvement data:

```
Real user query
    ↓
Fine-tuned model generates trajectory (routing + parameters)
    ↓
User approves or corrects → human preference signal
    ↓
Batch executes → R_exec reward
    ↓
Append (query, trajectory, reward) to RL training buffer
    ↓
Weekly GRPO update on accumulated buffer
    ↓
Re-evaluate on 120-query benchmark → deploy if improved
```

This is the self-improvement loop described in Biomni-R0 and BioMedAgent — the model gets better the more BioMate is used.

**User correction signal:** When a user edits parameters in the workflow viewer before executing, log the diff as a negative-to-positive reward signal: the model's original fill gets R_param computed from its output; the corrected fill gets R_param = 1.0. The GRPO update pushes the policy toward the corrected version.

---

## 7. Evaluation Protocol

### 7.1 Offline Benchmarks

| Benchmark | Queries | Metric | Current (Claude) | Target |
|-----------|---------|--------|-----------------|--------|
| Routing benchmark v9 | 120 | Exact workflow match | 93.3% | ≥ 95% |
| Parameter fill test set | 50 (hand-annotated) | Required param accuracy | ~75% | ≥ 90% |
| Schema validation | 63 workflows | 0 hallucinated params | — | 100% |

### 7.2 Online Evaluation

| Metric | Window | Target |
|--------|--------|--------|
| Batch execution success rate | Rolling 100 jobs | ≥ 85% |
| Median time to first output | Rolling 50 jobs | ≤ 120s (excl. image pull) |
| User correction rate | Rolling 200 queries | ≤ 15% |

### 7.3 A/B Deployment

Route 10% of real user traffic through the fine-tuned model (shadow mode first — log decisions but execute via Claude). Compare:
- Routing match rate vs. Claude
- Parameter fill quality (judged by schema validation)
- User correction frequency

Promote to 50% traffic when shadow-mode routing matches Claude at ≥ 95% and parameter fill accuracy is ≥ 90%.

---

## 8. Infrastructure

| Component | Spec | Purpose |
|-----------|------|---------|
| Training cluster | 4× A100 80GB (AWS p4d.24xlarge or p3.16xlarge) | SFT + GRPO training |
| RL rollout workers | 2× A10G 24GB | Inference for rollout generation |
| Reward buffer | PostgreSQL table in existing RDS | Async reward logging |
| Model serving | vLLM on g5.4xlarge | Inference endpoint |
| Experiment tracking | Weights & Biases or MLflow | Loss curves, reward curves |

**Estimated training cost (rough):**
- Phase 0 (pretraining, optional): ~$200 (4× A100 × 2 days)
- Phase 1 (SFT): ~$400 (4× A100 × 3–5 days)
- Phase 2 (offline GRPO): ~$800 (4× A100 × 1–2 weeks)
- Phase 3 (online GRPO): ~$1,500 + Batch job costs for training rollouts
- **Total: ~$3,000–4,000** (excluding Batch execution costs for Phase 3 rollouts)

**Inference cost at deployment:** A self-hosted 7B model on a g5.4xlarge (~$1.60/hr) handles ~500 routing requests/hr. At 1,000 queries/day, inference cost ≈ $3–4/day vs. current Claude API cost of ~$50–100/day (depending on prompt length and volume).

---

## 9. Relationship to Published Work

This plan implements the training recipe validated by:

| Paper | What we adopt |
|-------|--------------|
| Biomni-R0 (bioRxiv, 2025) | SFT warm-up on rejection-sampled trajectories → dual-reward GRPO |
| Aviary (arXiv:2412.21154, 2024) | Nextflow execution traces as RL environment; online RL against real tool execution |
| ReST-MCTS* (NeurIPS 2024) | Process rewards at each tool-call boundary (step-level credit assignment) |
| Workflow-R1 (arXiv:2602.01202, 2026) | GSsPO/GRPO aligned to Think-Action cycles |
| ReST meets ReAct (ICLR 2024) | 15% negative examples with self-correction for generalization |
| RobustFlow (arXiv:2509.21834, 2025) | Instruction-augmented SFT for routing robustness across query phrasings |

Key differentiator from all published work: BioMate has a **real HPC execution environment** (AWS Batch) producing unambiguous exit-code rewards, validated workflow schemas for parameter correctness checking, and an existing 120-query routing benchmark for evaluation. Most academic papers use simulated or web-based environments; BioMate's execution traces are directly grounded in scientific reality.

---

## 10. Phased Milestones

| Phase | Duration | Deliverable | Success Criterion |
|-------|----------|-------------|-------------------|
| 0 | 1–2 days | Domain-adapted base model | Perplexity on nf-core docs < base model |
| 1 | 1 week | `biomate-sft-7b` checkpoint | Routing accuracy ≥ 88% on benchmark |
| 2 | 2 weeks | `biomate-grpo-offline-7b` | Routing ≥ 93%, param fill ≥ 85% |
| 3 | 4 weeks | `biomate-grpo-online-7b` | Routing ≥ 95%, exec success ≥ 85% |
| Deploy | 1 week | Shadow-mode A/B test | Matches Claude routing at ≥ 95% |
| Flywheel | Ongoing | Weekly GRPO updates from user traffic | Monotonic improvement on routing benchmark |

---

*Document generated 2026-04-10. See also: `docs/nextPhase/20260409_RL_WORKFLOW_GENERATION_SURVEY.md` for the literature review underpinning this plan.*
