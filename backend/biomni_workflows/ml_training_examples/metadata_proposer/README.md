# Metadata-Mapping PROPOSER — Constrained Decoding + OOD Evaluation

**Date:** 2026-07-27
**What this is:** the FIRST concrete experiment for BioMate's internal per-client
model — a metadata-mapping **proposer** that PROPOSES grounded ontology candidates
and **ABSTAINs** rather than ever emitting an ungrounded ID.

> This is the survey-adjusted design. `docs/20260727_HARMONIZATION_SURVEY.md`
> verified that LLM-ALONE metadata mapping is ~96% accurate in-dictionary but
> **collapses to ~17% out-of-dictionary and hallucinates ontology IDs**. So the
> model here is *never* trained to emit an ID. It SELECTs a candidate retrieved
> from a real ontology, or ABSTAINs. A hallucinated ID is structurally impossible.

All data here is a **hand-encoded realistic SEED** (real EFO/Mondo/HPO/CL IDs),
demonstrating the format and the evaluation — not a full corpus. See "What real
bootstrap data to use next".

---

## The core invariant

```
input (free-text metadata)
      │
      ▼
  RETRIEVER  ── deterministic string/synonym/token match over ontology_seed.csv
      │            → ranked shortlist of GROUNDED candidates  (or []  for OOD)
      ▼
  PROPOSER   ── SELECT the best candidate  ─┐  output space = { the retrieved
      │         (only if it clears margin)  │  candidate IDs } ∪ { ABSTAIN }
      │      ── else ABSTAIN               ─┘  ⇒ an ungrounded ID CANNOT be emitted
      ▼
  term_id  (always a real ontology ID from the seed)  OR  ABSTAIN (no ID)
```

Because every candidate ID comes verbatim from `ontology_seed.csv`, and the
proposer can only SELECT a candidate or ABSTAIN, **the hallucinated-ID rate is 0
by construction**. The evaluation proves it empirically as well.

---

## Files

| File | What it is |
|---|---|
| `build_bootstrap.py` | Hand-encoded seed of free-text→canonical pairs with **real** EFO/Mondo/HPO/CL IDs, plus explicit **out-of-dictionary negatives** that must ABSTAIN. Writes `ontology_seed.csv`, `train.jsonl`, `eval.jsonl`, and the LoRA `instructions_{train,eval}.jsonl`. |
| `constrained_decoder.py` | The `Retriever` (deterministic grounded shortlist) + `Proposer` (SELECT/ABSTAIN ranker). CPU, no GPU, no network. `llm_select_from_candidates` is the LLM drop-in point. |
| `evaluate.py` | OOD evaluation — in-dict accuracy, OOD abstention rate, hallucinated-ID rate (=0). Writes `eval_metrics.json`; exits non-zero if the invariant is ever violated. |
| `ludwig_llm_config.yaml` | GPU drop-in — the Ludwig `model_type: llm` LoRA config, mirroring `stratification_adapter/`. Trains on `instructions_train.jsonl`. |
| `ontology_seed.csv`, `*.jsonl`, `eval_metrics.json` | Generated artifacts (run `build_bootstrap.py`). |

---

## Run it (stdlib only, no GPU, no installs)

```bash
cd backend/biomni_workflows/ml_training_examples/metadata_proposer
python3 build_bootstrap.py      # builds seed + splits + instruction rows
python3 evaluate.py             # runs the proposer over eval.jsonl, prints metrics
```

### Eval results (this seed)

**Held-out eval split (24 rows):**

| Metric | Value |
|---|---|
| In-dictionary accuracy | **100.0%** (19/19 correct SELECT of gold) |
| OOD abstention rate | **100.0%** (5/5 correctly abstained) |
| OOD leakage (got an ID) | **0** |
| **Hallucinated-ID rate** | **0.0%** (0/19 emitted IDs) |

**Full dataset stress-test (all 81 rows, tricky abbreviations included):**

| Metric | Value |
|---|---|
| In-dictionary accuracy | **96.8%** (61/63) |
| OOD abstention rate | **100.0%** (18/18) |
| **Hallucinated-ID rate** | **0.0%** (0/61 emitted) |

The 2 in-dict "misses" (`rheum. arthritis`, `rheumatoid arth.`) **ABSTAIN**
rather than emit a wrong ID — the safe failure mode (they route to human review).
This ~97% in-dict / 0-hallucination profile matches the survey's in-dict figure
honestly, and is exactly where the per-client LoRA earns its keep (below).

---

## How the LLM upgrade slots in (CPU baseline → per-client LoRA)

The deterministic `Proposer` is the **CPU baseline / oracle-of-record**. The
per-client LoRA is a **drop-in replacement for the decision step only** — it reads
the SAME retrieved candidate list and answers `SELECT <n>` / `ABSTAIN`:

1. `build_bootstrap.py` already renders each row as an `{instruction, output}`
   pair (`instructions_train.jsonl`) where the instruction is the value **plus its
   retrieved candidate list** and the output is `SELECT <n>` or `ABSTAIN` — never a
   raw ID.
2. Fine-tune a LoRA adapter on it through BioMate's **existing** `ludwig_llm` path
   (`ludwig_llm_config.yaml`; same module as `stratification_adapter`).
3. At inference, `constrained_decoder.llm_select_from_candidates(instruction,
   candidates, generate_fn)` calls the adapter and **parses** its output: only
   `SELECT <n>` pointing at a retrieved candidate is accepted; the harness maps
   `<n>` back to that candidate's real `term_id`. Anything else → ABSTAIN.

So even a fine-tuned (or hallucinating) LLM is **decoding-constrained to grounded
IDs**. The LoRA's job is to raise in-dict accuracy on the client's own
abbreviations/vocabulary and to learn *their* abstain threshold — e.g. it can learn
that `rheum. arthritis` → candidate #2 (which the deterministic ranker abstained
on). It never gains the ability to invent an ID.

### Per-client adapter product path (Ludwig LoRA → vLLM multi-adapter)

- **Train (L2):** one **isolated AWS Batch run per client**, on that client's
  private reviewed-mapping history only, emits a **single LoRA weight file**
  (MLflow-tracked). No shared training corpus across clients.
- **Serve:** `infra/vllm` runs **one shared frozen base** and multiplexes **many
  client LoRA adapters** over it (`sync-adapters.sh` S3→EFS + rolling refresh).
  Each client gets a private, domain-adapted proposer **without a dedicated GPU**.
- **Isolation & IP:** structural (one run, one data source, one adapter). For
  IRB-locked data the L4 federated path trains client-side and shares only weight
  deltas. The regulated ranking/gate layer stays transparent; this adapter is
  **advisory** — it proposes, a curator confirms.

This is the same engine as `stratification_adapter/` — this example only wires it
to the metadata-harmonization use case with the grounding guarantee baked in.

---

## Relationship to the deterministic Nextflow harmonizer

`nextflow_nfcore/subworkflows/database/metadata_harmonizer/main.nf` is the
**production deterministic grounding layer** (exact→synonym→token→fuzzy cascade,
ontology-grounded, human-in-the-loop, no ID invention). This example is its
**per-client learned upgrade**: same grounding contract, but the SELECT/ABSTAIN
decision can be a client-adapted LoRA instead of a fixed threshold — improving
recall on the client's messy vocabulary without ever relaxing the no-hallucination
guarantee. The `Retriever` here is the same string/synonym/token idea as the `.nf`
cascade, reused as the constrained-decoding candidate generator.

---

## What real bootstrap data to use next (replaces the hand seed)

The 28-term seed is a demonstration. At scale, replace `build_bootstrap.py`'s
hand-encoded `ONTOLOGY_SEED` + `IN_DICT` with:

1. **`text2term` over full EFO + Mondo (+ HPO + CL + UBERON)** to build the real
   candidate dictionary and to generate high-confidence `{free-text → term_id}`
   silver labels (`text2term` mappings above a confidence cutoff = positives). See
   `docs/20260727_RESOURCE_REGISTRY.md` §8 (text2term / MetaHarmonizer, EFO/Mondo/
   HPO/CL/UBERON).
2. **Real OOD negatives from client free-text** — clinical notes, assay codes,
   administrative labels, novel endotype names — that `text2term` maps below the
   cutoff. These become the ABSTAIN training signal.
3. **The client's reviewed history** as the L2 fine-tune corpus (the accepted
   SELECTs and the confirmed ABSTAINs), produced by the L1 RAG + human-review loop
   described in `stratification_adapter/run_demo.md`.

The evaluation harness (`evaluate.py`) is unchanged — it already reports the three
metrics against whatever seed/split is present, and enforces hallucinated-ID = 0.
