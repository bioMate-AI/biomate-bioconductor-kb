# Per-Client Stratification Adapter — L1 (RAG) → L2 (LoRA) Demo

**Date:** 2026-07-27
**What this is:** a runnable DEMO of the per-client LLM-adapter play from
`docs/20260727_WHERE_TO_TRAIN_MODELS.md` §3 (#1). It wires BioMate's **existing**
Ludwig training module (`backend/lib/galaxy/ai/ml_training/`, `ludwig_llm` LoRA/QLoRA,
MLflow, AWS-Batch-validated) + **existing** vLLM serving (`infra/vllm`) to the
autoimmune-stratification use case. **No core code was edited** — these are three
new files in a new example dir.

> **The moat is the client's private data + isolation, not the algorithm.** Any
> competitor can run LoRA. Nobody else has *this client's* past stratification
> decisions, assay quirks, and report house-style. A model fine-tuned on that
> can't be reproduced from public data and never leaves the client's trust boundary.

**All data here is SYNTHETIC EXAMPLE data** demonstrating the *format*, not real
client data. `stratification_instructions.jsonl` shows the shape a real per-client
corpus would take; it is not a training set.

---

## Files in this example

| File | What it is |
|---|---|
| `stratification_instructions.jsonl` | ~23 synthetic `{instruction, output}` rows: FcRn-response classification + explanation, free-text metadata harmonization with review flags, gate-3 result summaries for clinicians, report drafting in a house style, and data-isolation Q&A. Exact format consumed by `datasets.load_instruction_rows`. |
| `ludwig_llm_config.yaml` | Part A: the Ludwig `model_type: llm` LoRA config (what `LudwigModel(config)` consumes). Part B: the BioMate `TrainingConfig` that generates it. Fields match `config.py` / `ludwig_adapter.py` exactly. |
| `run_demo.md` | This file. |

---

## The two-layer flow: L1 RAG → L2 LoRA

**L1 — RAG (no training).** Index the client's documents + cohort metadata into a
closed retrieval store. The base LLM answers questions and drafts reports *grounded
in their corpus* — nothing leaves, no weights change. This is the day-one, zero-train
layer: it makes the assistant useful immediately and, critically, it **produces the
labeled `{instruction, output}` pairs** (reviewed drafts, accepted harmonizations,
signed-off stratification calls) that become the L2 training set.

**L2 — per-client LoRA (this demo).** Once enough client decisions accumulate,
fine-tune a **LoRA adapter** on their `{instruction, output}` history. The adapter
learns *how this client decides and writes* — their stratification thresholds, their
report voice, their metadata vocabulary. It is a single small weight file. The frozen
base model is shared; the adapter is the only per-client artifact.

**Why this ordering:** L1 gives value on day one and generates L2's data; L2 turns that
accumulated private data into a domain-adapted model competitors cannot clone. L3
(multimodal omics → endotype) and L4 (federated, client-side training for IRB-locked
data) extend the same engine — see the strategy doc.

```
client private docs ──► L1 RAG (closed retrieval, no train)
                              │  human-reviewed outputs
                              ▼
              {instruction, output} history  ──► L2 LoRA fine-tune (this demo)
                              │                        │  adapter weights only
                              ▼                        ▼
                        MLflow tracking          vLLM serves adapter over shared base
```

---

## How vLLM serves it: one base, many adapters

`infra/vllm` runs **one shared frozen base model** and multiplexes **many client LoRA
adapters** over it (`start-vllm.sh` discovers adapters on EFS; `sync-adapters.sh` syncs
new adapters from S3 → EFS and triggers a rolling ASG refresh). Each client gets a
private model **without a dedicated GPU per tenant** — the base weights are shared, only
the small adapter differs per request. This is what makes per-client adaptation
economical at scale.

- Train (L2, this demo) writes a LoRA adapter artifact to S3 (MLflow-tracked).
- `infra/vllm/sync-adapters.sh` syncs `s3://biomate-models/<prefix>/…/lora_adapter/` → EFS.
- vLLM loads it as a named adapter; requests tagged with the client route to *their*
  adapter over the shared base.

---

## Data isolation & IP story

- **Per-run isolation.** Each adapter trains in an **isolated AWS Batch run on one
  client's data only** and emits a **separate** LoRA weight file. There is no shared
  training corpus across clients — one tenant's weights are never activated for another
  (see the isolation Q&A rows in the JSONL).
- **Closed serving.** vLLM applies a client's adapter only to that client's requests.
- **L4 federated (IRB-locked case).** When data legally cannot leave the client, the
  adapter is trained **client-side** and only weight deltas are shared — the raw data
  never exports. This matches UCB's closed-system requirement and the federated-tensor
  precedent in the strategy doc.
- **Transparent layer stays un-trained.** The regulated primary ranking and the gate-3
  interaction test remain transparent, citable rule sets (a human signs off and must see
  *why*). This adapter is **advisory**: it drafts, harmonizes, and summarizes; a human
  still signs. One JSONL row explicitly encodes declining an "unreviewed final decision"
  request.

---

## CPU vs GPU — be honest about what runs where

| Path | Adapter | Base model | Hardware | Notes |
|---|---|---|---|---|
| **This demo default** | `lora` (no quantization) | SmolLM2-135M-Instruct | **CPU-feasible** | Small base + LoRA fits the CPU Batch tier (`process_low`, 2 cpu / 12 GB). Slow but real. |
| Larger base | `lora` | 1–8B model | **GPU** | LoRA over a real-size base needs a GPU. |
| **QLoRA** | `qlora` (4-bit) | any | **GPU** | 4-bit bitsandbytes quantization effectively requires a GPU. Set `adapter: qlora`, `quantization_bits: 4` → the config emits `quantization: {bits: 4}` and the run routes to the GPU Batch queue. |

The demo defaults to CPU-feasible (SmolLM2-135M + LoRA) so it can run end-to-end without
a GPU. Production per-client adapters on a useful-size base are a GPU job.

---

## Run it via the existing ml_training module (no new machinery)

### A. Local smoke — the CLI path (CPU, small)

The Nextflow wrapper (`biomni_workflows/nextflow_nfcore/ml_training/chemprop_train.nf`)
runs exactly this CLI inside the training container. Locally, against the demo JSONL:

```bash
cd /Users/kky/biomate-td-pr/backend/lib
python -m galaxy.ai.ml_training.cli \
  --dataset '/Users/kky/biomate-td-pr/backend/biomni_workflows/ml_training_examples/stratification_adapter/stratification_instructions.jsonl' \
  --model-type ludwig_llm \
  --task-type text_generation \
  --base-model 'HuggingFaceTB/SmolLM2-135M-Instruct' \
  --adapter lora \
  --instruction-col instruction --output-col output \
  --max-sequence-length 512 \
  --model-name acme-immunology-stratification-adapter \
  --campaign-id acme-immunology \
  --split random --epochs 3 --batch-size 4 --learning-rate 0.0001 \
  --out results
```

> Requires the LLM extras (`ludwig` + `peft`/`transformers`/`accelerate`) present in the
> `ml-training` container image. Without them the CLI raises a clear ImportError — the
> real fit runs in the image, not on a bare laptop. Writes `results/metrics.json` +
> `results/artifact/` (the LoRA adapter + manifest).

### B. Production — through the standard executor on AWS Batch

`executor_payload.build_execute_request(cfg, ...)` turns the `TrainingConfig` into a
`POST /api/nextflow/execute` request that runs through the **same** path as every other
workflow (AWS Batch, RunStateStore persistence, SSE status, billing, QC gate) — no new
execution code. For a real client, stage their private JSONL to S3 and pass it as
`s3_dataset_uri`:

```python
# (illustrative — uses only existing module functions; nothing new)
from galaxy.ai.ml_training.config import TrainingConfig, DatasetSpec, LLMSpec, Hyperparams
from galaxy.ai.ml_training.executor_payload import build_execute_request

cfg = TrainingConfig(
    name="acme-immunology-stratification-adapter",
    task_type="text_generation", model_type="ludwig_llm", featurizer="none",
    campaign_id="acme-immunology", metric="loss",
    dataset=DatasetSpec(s3_uri="s3://biomate-models/clients/acme/stratification/instructions.jsonl",
                        split="random"),
    llm=LLMSpec(base_model="HuggingFaceTB/SmolLM2-135M-Instruct", adapter="lora",
                instruction_col="instruction", output_col="output", max_sequence_length=512),
    hyperparams=Hyperparams(epochs=3, batch_size=4, learning_rate=1e-4),
).validate()

req = build_execute_request(cfg, user_id="<client-user-id>",
                            nextflow_path="ml_training/chemprop_train.nf",
                            s3_dataset_uri=cfg.dataset.s3_uri)
# POST req to /api/nextflow/execute (existing route) → Batch run → MLflow-tracked adapter → S3
```

For a **GPU QLoRA** run, set `adapter="qlora"`, `quantization_bits=4` on the `LLMSpec`
(the `.nf` TRAIN process routes to the GPU Batch queue via its process label).

### C. Serve the trained adapter

```bash
# after the Batch run writes the LoRA adapter to s3://biomate-models/<prefix>/…/lora_adapter/
infra/vllm/sync-adapters.sh          # S3 → EFS + rolling ASG refresh; adapter live in ~5 min
```

---

## What was validated (locally, no heavy installs) vs what needs Batch/GPU

**Validated locally (20/20 checks pass — see the validation summary in the delivery notes):**
- `stratification_instructions.jsonl` parses via the module's **real**
  `datasets.load_instruction_rows(DatasetSpec(path=…))` → 23 rows, every row has
  non-empty `instruction` + `output` (matches the `INSTRUCT_FIXTURE` / `_load_instruct_file`
  contract).
- `ludwig_llm_config.yaml` is valid YAML; its `ludwig_config` block equals, field-for-field,
  what `ludwig_adapter.to_ludwig_llm_config(cfg)` emits (`model_type: llm`, text
  input/output features, `prompt.template`, `trainer.type: finetune`, `adapter: {type: lora}`,
  no `quantization` for the CPU LoRA default).
- The `training_config` block builds a real `TrainingConfig` that passes `.validate()`
  (task_type=text_generation enforced, LLMSpec present, adapter in ADAPTERS).
- The CLI path (`cli._build_parser` + `build_config_from_args`) accepts the same args and
  coerces `task_type` → `text_generation` and split → `random`.

**Deferred to the Batch / GPU run (NOT run here — no heavy installs, per repo policy):**
- Ludwig's own `ModelConfig.from_dict(emitted)` schema validation (skipped — `ludwig`
  not installed locally; the module's own `test_llm_config_validates_against_ludwig_schema`
  covers this when the ML stack is present).
- The actual LoRA fine-tune (`LudwigModel.train`) — needs `ludwig` + `peft`/`transformers`
  in the `ml-training` image; produces the adapter + `metrics.json` + `manifest.json`.
- QLoRA / larger-base runs — need a GPU Batch queue.
- vLLM adapter serving round-trip — needs the EFS/ASG stack.

---

## How this becomes the per-client-adaptation product

L1 RAG ships first: it grounds answers in the client's corpus with zero training and
starts logging human-reviewed decisions. Those reviewed `{instruction, output}` pairs are
the L2 training set — so the product **generates its own moat data** as it's used. L2 then
fine-tunes a per-client LoRA on that private history through the existing `ludwig_llm`
path (isolated Batch run, MLflow-tracked, adapter-only artifact), and vLLM serves it over
a shared base so every client gets a private, domain-adapted model without a dedicated
GPU. Isolation is structural (one run, one data source, one adapter; L4 federated for
IRB-locked data), the regulated ranking/gate-3 layer stays transparent and un-trained, and
the adapter stays advisory-with-human-sign-off. The result is defensible precisely because
it's built on data no competitor holds — the client's own decisions — at the lowest build
cost, since the engine already exists and this demo only wires it to the stratification
use case.
